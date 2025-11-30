import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_toolkit/config/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShipmentTrackingPage extends StatefulWidget {
  final String shipmentId;

  const ShipmentTrackingPage({required this.shipmentId, super.key});

  @override
  State<ShipmentTrackingPage> createState() => _ShipmentTrackingPageState();
}

class _ShipmentTrackingPageState extends State<ShipmentTrackingPage> {
  final supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  RealtimeChannel? _realtimeChannel;

  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  LatLng? _truckLocation;
  DateTime? _lastUpdated;
  String? _driverId;
  BitmapDescriptor? _truckIcon;

  double _heading = 0.0;

  final Set<Marker> _markers = {};
  final Set<Polyline> _bluePolylines = {};

  bool _isLoading = true;
  String? _errorMessage;
  bool _followTruck = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadTruckIcon();
    await _fetchShipmentData();
  }

  Future<void> _loadTruckIcon() async {
    final ByteData data = await rootBundle.load('assets/cargo-truck.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 48,
    );
    final frame = await codec.getNextFrame();
    final resized = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    _truckIcon = BitmapDescriptor.bytes(resized!.buffer.asUint8List());
  }

  Future<void> _fetchShipmentData() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .rpc('get_track_data', params: {'p_shipment_id': widget.shipmentId})
          .single();

      _driverId = data['driver_id'];

      final pickupLat = data['pickup_latitude'];
      final pickupLng = data['pickup_longitude'];
      final dropLat = data['dropoff_latitude'];
      final dropLng = data['dropoff_longitude'];

      if (pickupLat != null && pickupLng != null) {
        _pickupLocation = LatLng(
          (pickupLat as num).toDouble(),
          (pickupLng as num).toDouble(),
        );
      }

      if (dropLat != null && dropLng != null) {
        _dropLocation = LatLng(
          (dropLat as num).toDouble(),
          (dropLng as num).toDouble(),
        );
      }

      if (mounted) _setMarkers();

      await _drawRoute();
      await _fetchTruckLocation();

      if (_driverId != null) _setupRealtimeSubscription();

      if (_mapController != null) _zoomToFitMarkers();
    } catch (e) {
      _errorMessage = "Failed to fetch data: $e";
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getRelativeTime(DateTime time) {
    final duration = DateTime.now().difference(time);

    if (duration.inSeconds < 60) {
      return 'Last updated: Just now';
    } else if (duration.inMinutes < 60) {
      return 'Last updated: ${duration.inMinutes} min${duration.inMinutes > 1 ? 's' : ''} ago';
    } else if (duration.inHours < 24) {
      return 'Last updated: ${duration.inHours} hr${duration.inHours > 1 ? 's' : ''} ago';
    } else {
      return 'Last updated: ${DateFormat('dd MMM HH:mm').format(time)}';
    }
  }

  LatLng? _findNearestPointOnRoute(LatLng truck, List<LatLng> routePoints) {
    LatLng? nearestPoint;
    double minDistance = double.infinity;

    for (var point in routePoints) {
      final distance = _calculateDistance(truck, point);
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = point;
      }
    }

    return nearestPoint;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const R = 6371e3;
    final lat1 = p1.latitude * pi / 180;
    final lat2 = p2.latitude * pi / 180;
    final dLat = (p2.latitude - p1.latitude) * pi / 180;
    final dLng = (p2.longitude - p1.longitude) * pi / 180;

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  Future<void> _fetchTruckLocation() async {
    if (_driverId == null) return;

    try {
      final driverData = await supabase
          .from('driver_locations')
          .select('last_latitude, last_longitude, updated_at, heading')
          .eq('custom_user_id', _driverId!)
          .single();

      if (driverData['last_latitude'] != null &&
          driverData['last_longitude'] != null) {
        _truckLocation = LatLng(
          (driverData['last_latitude'] as num).toDouble(),
          (driverData['last_longitude'] as num).toDouble(),
        );

        _lastUpdated = DateTime.tryParse(driverData['updated_at'] ?? '');
        _heading = (driverData['heading'] as num?)?.toDouble() ?? _heading;

        if (mounted) _updateMarkers();
      }
    } catch (e) {
      print('Error fetching driver location: $e');
    }
  }

  void _setupRealtimeSubscription() {
    if (_driverId == null) return;

    _realtimeChannel = supabase.channel(
      'public:driver_locations:custom_user_id=eq.$_driverId',
    );

    _realtimeChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'driver_locations',
          callback: (payload) {
            final lat = (payload.newRecord['last_latitude'] as num?)
                ?.toDouble();
            final lng = (payload.newRecord['last_longitude'] as num?)
                ?.toDouble();
            final updatedAt = payload.newRecord['updated_at'];

            _heading =
                (payload.newRecord['heading'] as num?)?.toDouble() ?? _heading;

            if (lat == null || lng == null) return;

            setState(() {
              _truckLocation = LatLng(lat, lng);
              _lastUpdated = DateTime.tryParse(updatedAt ?? '');
              _updateMarkers();

              if (_followTruck && _mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLng(_truckLocation!),
                );
              }
            });
          },
        )
        .subscribe();
  }

  void _setMarkers() {
    _markers.clear();

    if (_pickupLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("pickup"),
          position: _pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: "Pickup"),
        ),
      );
    }

    if (_dropLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("drop"),
          position: _dropLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Drop"),
        ),
      );
    }

    if (_truckLocation != null && _truckIcon != null) {
      _markers.add(
        Marker(
          markerId: MarkerId(_driverId!),
          position: _truckLocation!,
          icon: _truckIcon!,
          rotation: _heading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }
  }

  Future<void> _updateMarkers() async {
    _setMarkers();

    if (_truckLocation != null && _bluePolylines.isNotEmpty) {
      final routePoints = _bluePolylines.first.points;
      final nearest = _findNearestPointOnRoute(_truckLocation!, routePoints);

      if (nearest != null) {
        final polylinePoints = PolylinePoints(
          apiKey: AppConfig.googleMapsApiKey,
        );

        final routesResponse = await polylinePoints.getRouteBetweenCoordinatesV2(
          request: RoutesApiRequest(
            origin: PointLatLng(
              _truckLocation!.latitude,
              _truckLocation!.longitude,
            ),
            destination: PointLatLng(
              nearest.latitude,
              nearest.longitude,
            ),
            travelMode: TravelMode.driving,
            routingPreference: RoutingPreference.trafficAware,
          ),
        );

        if (routesResponse.routes.isNotEmpty && mounted) {
          final route = routesResponse.routes.first;

          final rawPoints = route.polylinePoints ?? [];
          final points = rawPoints
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();

          setState(() {
            _bluePolylines.removeWhere(
                  (p) => p.polylineId.value == "deviation_red",
            );

            _bluePolylines.add(
              Polyline(
                polylineId: const PolylineId("deviation_red"),
                color: Colors.red,
                width: 4,
                points: points,
                patterns: [
                  PatternItem.dash(20),
                  PatternItem.gap(10),
                ],
              ),
            );

            _markers.add(
              Marker(
                markerId: const MarkerId("rejoin_point"),
                position: nearest,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
              ),
            );
          });
        }
      }
    }
  }


  Future<void> _drawRoute() async {
    if (_pickupLocation == null || _dropLocation == null) return;

    final polylinePoints = PolylinePoints(apiKey: AppConfig.googleMapsApiKey);

    final routesResponse = await polylinePoints.getRouteBetweenCoordinatesV2(
      request: RoutesApiRequest(
        origin: PointLatLng(
          _pickupLocation!.latitude,
          _pickupLocation!.longitude,
        ),
        destination: PointLatLng(
          _dropLocation!.latitude,
          _dropLocation!.longitude,
        ),
        travelMode: TravelMode.driving,
        routingPreference: RoutingPreference.trafficAware, // optional
      ),
    );

    if (routesResponse.routes.isNotEmpty) {
      final route = routesResponse.routes.first;
      final List<PointLatLng> rawPoints = route.polylinePoints ?? [];
      final points = rawPoints
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      if (mounted) {
        setState(() {
          _bluePolylines.clear();
          _bluePolylines.add(
            Polyline(
              polylineId: const PolylineId("route_blue"),
              color: Colors.blue,
              width: 5,
              points: points,
            ),
          );
        });
      }
    }
  }

  void _zoomToFitMarkers() {
    if (_markers.isEmpty || _mapController == null) return;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        _markers.map((m) => m.position.latitude).reduce(min),
        _markers.map((m) => m.position.longitude).reduce(min),
      ),
      northeast: LatLng(
        _markers.map((m) => m.position.latitude).reduce(max),
        _markers.map((m) => m.position.longitude).reduce(max),
      ),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _zoomToTruck() {
    if (_truckLocation == null || _mapController == null) return;
    setState(() => _followTruck = true);
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(_truckLocation!, 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Tracking #${widget.shipmentId}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchShipmentData,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _zoomToFitMarkers();
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(20.5937, 78.9629),
              zoom: 5,
            ),
            markers: _markers,
            polylines: _bluePolylines,
            onCameraMove: (_) {
              if (_followTruck) _followTruck = false;
            },
          ),

          if (_lastUpdated != null)
            Positioned(
              left: 16,
              bottom: 16,
              child: Card(
                color: Colors.black.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _getRelativeTime(_lastUpdated!),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),

          if (_isLoading) const Center(child: CircularProgressIndicator()),

          if (!_isLoading && _errorMessage != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _zoomToFitMarkers,
            label: const Text("Fit to Route"),
            icon: const Icon(Icons.zoom_out_map),
            heroTag: 'fit-to-route',
          ),
          const SizedBox(height: 10),
          if (_truckLocation != null)
            FloatingActionButton.extended(
              onPressed: _zoomToTruck,
              label: const Text("Follow Truck"),
              icon: const Icon(Icons.my_location),
              heroTag: 'follow-truck',
              backgroundColor: _followTruck ? Colors.teal : null,
              foregroundColor: _followTruck ? Colors.white : null,
            ),
        ],
      ),
    );
  }
}
