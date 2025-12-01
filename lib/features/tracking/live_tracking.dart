import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

import '../../services/driver/background_location_service.dart';

class LiveTrackingPage extends StatefulWidget {
  const LiveTrackingPage({super.key});

  @override
  State<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends State<LiveTrackingPage> {
  final supabase = Supabase.instance.client;
  GoogleMapController? mapController;
  Marker? _driverMarker;
  BitmapDescriptor? _truckIcon;
  bool _isTrackingEnabled = false;
  bool _isLoading = true;

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(19.0330, 73.0297),
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    await Future.wait([_loadTruckIcon()]);

    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    service.on('update').listen((event) {
      if (event != null && event['lat'] != null && event['lng'] != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateLocationOnMap(
              event['lat'],
              event['lng'],
              heading: event['heading'] ?? 0,
            );
          }
        });
      }
    });

    if (mounted) {
      setState(() {
        _isTrackingEnabled = isRunning;
        _isLoading = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTruckIcon();
  }

  Future<void> _loadTruckIcon() async {
    try {
      final config = createLocalImageConfiguration(context);
      _truckIcon = await BitmapDescriptor.asset(
        config,
        'assets/cargo-truck.png',
      );

      if (mounted) setState(() {});
    } catch (e) {
      print("Error loading truck icon: $e");
      _truckIcon = BitmapDescriptor.defaultMarker;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _isTrackingEnabled = false);
      return;
    }

    setState(() => _isTrackingEnabled = !_isTrackingEnabled);

    if (_isTrackingEnabled) {
      await BackgroundLocationService.startService();
      _showSnackBar("Live tracking service started.");
    } else {
      BackgroundLocationService.stopService();
      _showSnackBar("Live tracking service stopped.");
    }
  }

  Future<bool> _handleLocationPermission() async {
    if (await handler.Permission.notification.request().isDenied) {
      _showErrorSnackBar(
        "Notification permission is required for tracking service.",
      );
      return false;
    }
    final serviceStatus = await handler.Permission.location.serviceStatus;
    if (serviceStatus.isDisabled) {
      _showErrorSnackBar("Enable location services in your device settings.");
      await handler.openAppSettings();
      return false;
    }

    var permissionStatus = await handler.Permission.location.request();

    if (permissionStatus.isDenied) {
      _showErrorSnackBar("Location permission required.");
      return false;
    }

    if (permissionStatus.isPermanentlyDenied) {
      _showErrorSnackBar(
        "Location permission permanently denied. Enable in settings.",
      );
      await handler.openAppSettings();
      return false;
    }

    // Upgrade to Always
    if (await handler.Permission.locationAlways.isDenied) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Background Location Required"),
          content: const Text(
            "To track your location when app is closed:\n\n"
            "→ Go to Settings → Permissions → Location\n"
            "→ Select 'Allow all the time'\n",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                handler.openAppSettings();
                Navigator.pop(context);
              },
              child: const Text("Go to Settings"),
            ),
          ],
        ),
      );
      return false;
    }

    return true;
  }

  void _updateLocationOnMap(double lat, double lng, {double heading = 0}) {
    if (!mounted) return;

    final newLatLng = LatLng(lat, lng);

    setState(() {
      _driverMarker = Marker(
        markerId: const MarkerId("driver"),
        position: newLatLng,
        icon: _truckIcon ?? BitmapDescriptor.defaultMarker,
        rotation: heading,
        anchor: const Offset(0.5, 0.5),
      );
    });

    mapController?.animateCamera(CameraUpdate.newLatLng(newLatLng));
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Switch(
                value: _isTrackingEnabled,
                onChanged: (_) => _toggleTracking(),
                activeTrackColor: Colors.green.shade200,
                activeThumbColor: Colors.green,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              onMapCreated: (controller) => mapController = controller,
              initialCameraPosition: _kInitialPosition,
              markers: _driverMarker != null ? {_driverMarker!} : {},
              myLocationButtonEnabled: true,
              myLocationEnabled: true,
              zoomControlsEnabled: false,
            ),
    );
  }
}
