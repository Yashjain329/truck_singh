import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/services/driver/routing_service.dart';

class DriverRouteTrackingPage extends StatefulWidget {
  final String driverId;

  const DriverRouteTrackingPage({super.key, required this.driverId});

  @override
  State<DriverRouteTrackingPage> createState() =>
      _DriverRouteTrackingPageState();
}

class _DriverRouteTrackingPageState extends State<DriverRouteTrackingPage> {
  GoogleMapController? _mapController;
  final RouteService _routeService = RouteService();
  StreamSubscription<Position>? _positionStream;

  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  String? _shipmentStatus;

  LatLng? _currentDriverPos;
  List<RouteOption> _routeOptions = [];
  int _selectedRouteIndex = 0;
  bool _isLoading = true;
  String _errorMessage = "";

  double _distanceRemainingKm = 0.0;
  double _fuelCostRemaining = 0.0;

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializePage() async {
    try {
      await _loadShipmentData();
      await _getCurrentLocation();

      if (_pickupLocation != null && _dropLocation != null) {
        await _calculateTargetAndFetchRoutes();
        _startLiveTracking();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Error initializing: $e";
      });
    }
  }

  Future<void> _loadShipmentData() async {
    final response = await Supabase.instance.client
        .from('shipment')
        .select(
          'booking_status, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude',
        )
        .eq('assigned_driver', widget.driverId)
        .neq('booking_status', 'Completed')
        .maybeSingle();

    if (response == null) throw "No active shipment found for this driver.";

    if (!mounted) return;

    setState(() {
      _shipmentStatus = response['booking_status'];
      _pickupLocation = LatLng(
        response['pickup_latitude'],
        response['pickup_longitude'],
      );
      _dropLocation = LatLng(
        response['dropoff_latitude'],
        response['dropoff_longitude'],
      );
    });
  }

  Future<void> _getCurrentLocation() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showErrorSnackBar("Enable location services!");
      throw "Location services disabled";
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        _showErrorSnackBar("Location permission denied!");
        throw "Permission denied";
      }
    }

    Position pos = await Geolocator.getCurrentPosition();

    if (!mounted) return;

    setState(() {
      _currentDriverPos = LatLng(pos.latitude, pos.longitude);
    });
  }

  Future<void> _calculateTargetAndFetchRoutes() async {
    LatLng target;

    if (_shipmentStatus == "Assigned" || _shipmentStatus == "Accepted") {
      target = _pickupLocation!;
    } else {
      target = _dropLocation!;
    }

    if (_currentDriverPos != null) {
      var routes = await _routeService.getTrafficAwareRoutes(
        _currentDriverPos!,
        target,
      );

      if (!mounted) return;

      setState(() {
        _routeOptions = routes;
        _isLoading = false;

        if (routes.isNotEmpty) {
          _updateStatsFromRouteOption(routes[0]);
        }
      });
    }
  }

  void _startLiveTracking() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen((Position pos) {
          LatLng newPos = LatLng(pos.latitude, pos.longitude);

          if (!mounted) return;

          setState(() {
            _currentDriverPos = newPos;
          });

          _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
        });
  }

  void _updateStatsFromRouteOption(RouteOption route) {
    double km = route.distanceMeters / 1000.0;
    double fuel = route.fuelCost;

    setState(() {
      _distanceRemainingKm = km;
      _fuelCostRemaining = fuel;
    });
  }

  void _showFuelDisclaimerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⛽ Fuel Cost Estimation"),
        content: Text(
          "Fuel cost is an estimate:\n\n"
          "• Mileage: ${_routeService.truckKPL.toStringAsFixed(1)} km/l\n"
          "• Fuel Price: ₹${_routeService.fuelPricePerLiter.toStringAsFixed(2)}\n",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Set<Polyline> _createPolylines() {
    Set<Polyline> set = {};

    for (int i = 0; i < _routeOptions.length; i++) {
      bool selected = i == _selectedRouteIndex;

      set.add(
        Polyline(
          polylineId: PolylineId("route_$i"),
          points: _decodePoly(_routeOptions[i].polylineEncoded),
          color: selected ? Colors.blue : Colors.grey,
          width: selected ? 6 : 4,
          zIndex: selected ? 10 : 1,
          onTap: () {
            if (!mounted) return;
            setState(() {
              _selectedRouteIndex = i;
              _updateStatsFromRouteOption(_routeOptions[i]);
            });
          },
        ),
      );
    }

    return set;
  }

  Set<Marker> _createMarkers() {
    Set<Marker> markers = {};

    if (_currentDriverPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("driver"),
          position: _currentDriverPos!,
          infoWindow: const InfoWindow(title: "You (Driver)"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (_pickupLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("pickup"),
          position: _pickupLocation!,
          infoWindow: const InfoWindow(title: "Pickup"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    if (_dropLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("drop"),
          position: _dropLocation!,
          infoWindow: const InfoWindow(title: "Drop"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    return markers;
  }

  // ✅ FINAL FIX — Works with your flutter_polyline_points version
  List<LatLng> _decodePoly(String encoded) {
    // Required in your installed version
    PolylinePoints(apiKey: "YOUR_GOOGLE_API_KEY_HERE");

    // decodePolyline is STATIC — must be called via class
    final List<PointLatLng> points = PolylinePoints.decodePolyline(encoded);

    return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoading ? "Loading..." : "Driver Route Tracking"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showFuelDisclaimerDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentDriverPos ?? _pickupLocation!,
                    zoom: 12,
                  ),
                  markers: _createMarkers(),
                  polylines: _createPolylines(),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  padding: const EdgeInsets.only(bottom: 120),
                  onMapCreated: (controller) => _mapController = controller,
                ),

                /// Route Options Chips
                if (_routeOptions.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _routeOptions.asMap().entries.map((entry) {
                          int index = entry.key;
                          bool selected = index == _selectedRouteIndex;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              backgroundColor: selected
                                  ? Colors.indigo
                                  : Colors.white,
                              label: Text(
                                "${entry.value.durationFormatted} • ${(entry.value.distanceMeters / 1000).toStringAsFixed(1)} km",
                                style: TextStyle(
                                  color: selected ? Colors.white : Colors.black,
                                ),
                              ),
                              onPressed: () {
                                if (!mounted) return;
                                setState(() {
                                  _selectedRouteIndex = index;
                                  _updateStatsFromRouteOption(entry.value);
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                /// Info Panel
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _infoCol(
                            "Remaining",
                            "${_distanceRemainingKm.toStringAsFixed(1)} km",
                          ),
                          _infoCol(
                            "Fuel Cost",
                            "₹${_fuelCostRemaining.toStringAsFixed(2)}",
                          ),
                          _infoCol("Status", _shipmentStatus ?? "-"),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 100,
                  left: 20,
                  child: ElevatedButton(
                    child: const Icon(Icons.zoom_out_map),
                    onPressed: () {
                      if (_currentDriverPos != null &&
                          _pickupLocation != null &&
                          _dropLocation != null) {
                        LatLngBounds bounds = LatLngBounds(
                          southwest: LatLng(
                            min(
                              min(
                                _pickupLocation!.latitude,
                                _dropLocation!.latitude,
                              ),
                              _currentDriverPos!.latitude,
                            ),
                            min(
                              min(
                                _pickupLocation!.longitude,
                                _dropLocation!.longitude,
                              ),
                              _currentDriverPos!.longitude,
                            ),
                          ),
                          northeast: LatLng(
                            max(
                              max(
                                _pickupLocation!.latitude,
                                _dropLocation!.latitude,
                              ),
                              _currentDriverPos!.latitude,
                            ),
                            max(
                              max(
                                _pickupLocation!.longitude,
                                _dropLocation!.longitude,
                              ),
                              _currentDriverPos!.longitude,
                            ),
                          ),
                        );

                        _mapController?.animateCamera(
                          CameraUpdate.newLatLngBounds(bounds, 60),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _infoCol(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
