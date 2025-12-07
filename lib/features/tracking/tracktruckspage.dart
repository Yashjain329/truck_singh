import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_toolkit/features/trips/shipment_details.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class TrackTrucksPage extends StatefulWidget {
  final String truckOwnerId;
  const TrackTrucksPage({required this.truckOwnerId, super.key});

  @override
  State<TrackTrucksPage> createState() => _TrackTrucksPageState();
}

class _TrackTrucksPageState extends State<TrackTrucksPage> {
  final supabase = Supabase.instance.client;
  Map<String, Marker> _markers = {};
  GoogleMapController? _mapController;
  BitmapDescriptor? _truckIcon;
  RealtimeChannel? _realtimeChannel;
  List<String> _driverIds = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _fetchLimit = 100;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadTruckIcon();
    await _fetchInitialLocations();

    if (_driverIds.isNotEmpty) {
      _setupRealtimeSubscription();
    }
  }

  @override
  void dispose() {
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  Future<void> _loadTruckIcon() async {
    try {
      _truckIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(40, 40)),
        'assets/cargo-truck.png',
      );
    } catch (e) {
      print("Error loading truck icon: $e");
      _truckIcon = BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _fetchInitialLocations() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await supabase.rpc(
        'get_loc_for_owner_drivers',
        params: {'p_owner_id': widget.truckOwnerId},
      ).limit(_fetchLimit);

      _driverIds = (response as List<dynamic>)
          .map<String>((e) => e['custom_user_id'].toString())
          .toList();

      if (response.length >= _fetchLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: Fetched $_fetchLimit drivers (max limit). Some trucks may not display.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      _updateMarkersFromData(response);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Failed to fetch truck locations: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel = supabase.channel('public:driver_locations')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'driver_locations',
        callback: (payload) => _handleRealtimeUpdate(payload),
      )
      ..subscribe();
  }

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    final eventType = payload.eventType;
    final record = (eventType == PostgresChangeEvent.delete)
        ? payload.oldRecord
        : payload.newRecord;

    if (record.isEmpty) return;

    final customUserId = record['custom_user_id'] as String?;

    if (customUserId != null && _driverIds.contains(customUserId)) {
      if (mounted) {
        setState(() {
          if (eventType == PostgresChangeEvent.delete) {
            _markers.remove(customUserId);
          } else {
            final marker = _createMarkerFromData(record);
            if (marker != null) {
              _markers[customUserId] = marker;
            }
          }
        });
      }
    }
  }

  Future<void> _navigateToShipmentDetails(String driverId) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Fetching shipment details...')));

    try {
      final response = await supabase
          .from('shipment')
          .select()
          .eq('assigned_driver', driverId)
          .neq('booking_status', 'Completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!mounted) return;

      if (response != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShipmentDetailsPage(
              shipment: response,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active shipment found for this driver.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Failed to get shipment details. $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showLimitDialog() async {
    final List<int?> limits = [10, 20, 50, 100];

    final selectedValue = await showDialog<int?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Driver Display Limit'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroup<int>(
                  groupValue: _fetchLimit,
                  onChanged: (value) => Navigator.of(context).pop(value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: limits.map((limit) {
                      return RadioListTile<int>(
                        title: Text(limit.toString()),
                        value: limit??0,
                      );
                    }).toList(),
                  ),
                )
              ]
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        );
      },
    );

    if (selectedValue != null && selectedValue != _fetchLimit) {
      setState(() => _fetchLimit = selectedValue);
      await _fetchInitialLocations();
    }
  }

  Marker? _createMarkerFromData(Map<String, dynamic> item) {
    final lat = item['location_lat'];
    final lng = item['location_lng'];
    final customUserId = item['custom_user_id'];
    final lastUpdatedAt = item['last_updated_at'];

    if (lat == null || lng == null || customUserId == null) return null;

    bool isStale = false;

    if (lastUpdatedAt != null) {
      final lastUpdate = DateTime.tryParse(lastUpdatedAt) ?? DateTime.now();
      isStale = DateTime.now().difference(lastUpdate).inMinutes > 15;
    }

    return Marker(
      markerId: MarkerId(customUserId),
      position: LatLng(lat, lng),
      icon: _truckIcon ?? BitmapDescriptor.defaultMarker,
      alpha: isStale ? 0.6 : 1.0,
      infoWindow: InfoWindow(
        title: "Driver $customUserId",
        snippet:
        "Updated: ${_formatTimestamp(lastUpdatedAt)}\nTap for shipment details",
        onTap: () => _navigateToShipmentDetails(customUserId),
      ),
    );
  }

  void _updateMarkersFromData(List<dynamic> data) {
    if (!mounted) return;

    final tempMarkers = <String, Marker>{};

    for (var item in data) {
      final marker = _createMarkerFromData(item);
      if (marker != null) {
        tempMarkers[marker.markerId.value] = marker;
      }
    }

    setState(() => _markers = tempMarkers);

    _zoomToFitMarkers();
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return "never";
    try {
      return timeago.format(DateTime.parse(isoString));
    } catch (e) {
      return "a while ago";
    }
  }

  void _zoomToFitMarkers() {
    if (_markers.isEmpty || _mapController == null) return;

    final positions = _markers.values.map((m) => m.position).toList();

    if (positions.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(positions.first, 15),
      );
      return;
    }

    double south = positions.first.latitude;
    double north = positions.first.latitude;
    double west = positions.first.longitude;
    double east = positions.first.longitude;

    for (var pos in positions) {
      if (pos.latitude < south) south = pos.latitude;
      if (pos.latitude > north) north = pos.latitude;
      if (pos.longitude < west) west = pos.longitude;
      if (pos.longitude > east) east = pos.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Track My Trucks"),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showLimitDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
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
              markers: Set.of(_markers.values),
            ),

            if (_isLoading)
              const Center(child: CircularProgressIndicator()),

            if (!_isLoading && _errorMessage != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white.withValues(alpha: 0.85),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            if (!_isLoading && _markers.isEmpty && _errorMessage == null)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No active trucks found for your account.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _zoomToFitMarkers,
        label: const Text("Center Map"),
        icon: const Icon(Icons.center_focus_strong),
      ),
    );
  }
}