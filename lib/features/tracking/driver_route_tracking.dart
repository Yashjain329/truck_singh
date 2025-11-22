import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/services/driver/routing_service.dart';

class DriverRouteTrackingPage extends StatefulWidget {
  final String driverId; // Pass current driver's custom_user_id
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
  String _targetLabel = "Loading...";

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
        _calculateTargetAndFetchRoutes();
        _startLiveTracking();
      }
    } catch (e) {
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

    if (response == null) {
      throw "No active shipment found for this driver.";
    }

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
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackBar("Enable location services!");
      throw "Location services are disabled.";
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorSnackBar("Location permission denied!");
        throw "Location permission denied.";
      }
    }

    Position pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentDriverPos = LatLng(pos.latitude, pos.longitude);
    });
  }

  void _calculateTargetAndFetchRoutes() async {
    LatLng target;
    if (_shipmentStatus == "Assigned" || _shipmentStatus == "Accepted") {
      target = _pickupLocation!;
      _targetLabel = "To Pickup";
    } else {
      target = _dropLocation!;
      _targetLabel = "To Dropoff";
    }

    if (_currentDriverPos != null) {
      var routes = await _routeService.getTrafficAwareRoutes(
        _currentDriverPos!,
        target,
      );

      if (mounted) {
        setState(() {
          _routeOptions = routes;
          _isLoading = false;
          if (routes.isNotEmpty) {
            _updateStatsFromRouteOption(_routeOptions[0]);
          }
        });
      }
    }
  }

  void _startLiveTracking() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
              (Position pos) {
            LatLng newPos = LatLng(pos.latitude, pos.longitude);
            setState(() {
              _currentDriverPos = newPos;
            });
            _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
          },
        );
  }

  void _updateStatsFromRouteOption(RouteOption route) {
    double distanceKm = route.distanceMeters / 1000.0;
    double fuel = route.fuelCost;

    setState(() {
      _distanceRemainingKm = distanceKm;
      _fuelCostRemaining = fuel;
    });
  }

  void _showFuelDisclaimerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("⛽ Fuel Cost Estimation"),
          content: Text(
            "The remaining fuel cost is an **ESTIMATE** based on the following constants:\n\n"
                "• Truck Mileage: **${_routeService.truckKPL.toStringAsFixed(1)} km per Liter (KPL)**\n"
                "• Fuel Price: **₹${_routeService.fuelPricePerLiter.toStringAsFixed(2)} per Liter**\n\n"
                "This figure does not account for actual traffic, load weight, driver behavior, or real-time fuel price fluctuations. It is for **planning purposes only**.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Set<Polyline> _createPolylines() {
    Set<Polyline> polylines = {};
    for (int i = 0; i < _routeOptions.length; i++) {
      bool isSelected = (i == _selectedRouteIndex);
      polylines.add(
        Polyline(
          polylineId: PolylineId("route_$i"),
          points: _decodePoly(_routeOptions[i].polylineEncoded),
          color: isSelected ? Colors.blue : Colors.grey,
          width: isSelected ? 6 : 4,
          zIndex: isSelected ? 10 : 0,
          onTap: () {
            setState(() {
              _selectedRouteIndex = i;
              // FIX: Update stats immediately on route selection
              _updateStatsFromRouteOption(_routeOptions[i]);
            });
          },
        ),
      );
    }
    return polylines;
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

  List<LatLng> _decodePoly(String encoded) {
    return PolylinePoints.decodePolyline(
      encoded,
    ).map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  void _showErrorSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    }
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
        title: Text(
          _isLoading ? "Loading shipment..." : "Driver Route Tracking",
        ),
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
            padding: const EdgeInsets.only(bottom: 120.0),
            onMapCreated: (controller) => _mapController = controller,
          ),
          if (_routeOptions.isNotEmpty)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _routeOptions.asMap().entries.map((entry) {
                    bool isSelected = entry.key == _selectedRouteIndex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        backgroundColor: isSelected
                            ? Colors.indigo
                            : Colors.white,
                        label: Text(
                          "${entry.value.durationFormatted} • ${(entry.value.distanceMeters / 1000).toStringAsFixed(1)}km",
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        onPressed: () => setState(() {
                          _selectedRouteIndex = entry.key;
                          _updateStatsFromRouteOption(entry.value);
                        }),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
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
                if (!_isLoading &&
                    _currentDriverPos != null &&
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