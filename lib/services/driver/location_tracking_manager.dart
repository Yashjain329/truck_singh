import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'geofence_service.dart';
import 'local_database_helper.dart';
import 'notification_helper.dart';

class LocationTrackingManager {
  final ServiceInstance serviceInstance;
  final SupabaseClient supabaseClient;
  final String userId;
  final String customUserId;

  StreamSubscription<Position>? _positionStreamSub;
  Timer? _syncTimer;
  Map<String, dynamic>? _activeShipment;

  LocationTrackingManager({
    required this.serviceInstance,
    required this.supabaseClient,
    required this.userId,
    required this.customUserId,
  });

  void setActiveShipment(Map<String, dynamic>? shipment) {
    _activeShipment = shipment;
  }

  /// Start location tracking + offline sync
  Future<void> start() async {
    await _checkPermissions();

    // Auto-sync every 5 minutes
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
          (_) => _syncOfflineLocations(),
    );

    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );

    _positionStreamSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onLocationUpdate, onError: _onLocationError);
  }

  void stop() {
    _positionStreamSub?.cancel();
    _syncTimer?.cancel();
  }

  Future<void> _onLocationUpdate(Position pos) async {
    final data = {
      'custom_user_id': customUserId,
      'user_id': userId,
      'location_lat': pos.latitude,
      'location_lng': pos.longitude,
      'last_updated_at': DateTime.now().toIso8601String(),
    };

    final connectivity = await Connectivity().checkConnectivity();

    // === OFFLINE MODE ===
    if (connectivity == ConnectivityResult.none) {
      await LocalDatabaseHelper.instance.insertLocation(data);
      NotificationHelper.updateNotification(
        'Tracking Active (Offline)',
        'Location stored locally.',
      );
    }

    else {
      await _syncOfflineLocations();
      try {
        await supabaseClient.rpc('update_driver_loc', params: {
          'user_id_input': userId,
          'custom_user_id_input': customUserId,
          'longitude_input': pos.longitude,
          'latitude_input': pos.latitude,
          'heading_input': pos.heading,
          'speed_input': pos.speed,
          'shipment_id_input': _activeShipment?['shipment_id'],
        });

        final time = DateFormat('HH:mm').format(DateTime.now());
        NotificationHelper.updateNotification(
          'Tracking Active',
          'Updated at $time',
        );
      } catch (e) {
        NotificationHelper.updateNotification(
          'Tracking Error',
          'Upload failed: $e',
        );
      }
    }

    if (_activeShipment != null) {
      final newStatus =
      await GeofenceService.checkGeofences(pos, _activeShipment!);

      if (newStatus != null) {
        _activeShipment!['booking_status'] = newStatus;
      }
    }
    serviceInstance.invoke('update', {
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  }

  void _onLocationError(dynamic error) {
    NotificationHelper.updateNotification(
      'Tracking Error',
      'Unable to fetch location.',
    );
  }
  Future<void> _syncOfflineLocations() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    final db = LocalDatabaseHelper.instance;
    final cached = await db.getAllLocations();

    if (cached.isNotEmpty) {
      try {
        await supabaseClient
            .from('driver_locations')
            .upsert(cached, onConflict: 'user_id');

        await db.clearAllLocations();
      } catch (e) {
        print("⚠ Error syncing cached locations: $e");
      }
    }
  }
  Future<void> _checkPermissions() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }
}