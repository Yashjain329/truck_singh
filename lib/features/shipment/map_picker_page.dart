import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../config/config.dart';
import 'form_step/address_step.dart';

String GOOGLE_MAPS_API_KEY = AppConfig.googleMapsApiKey;

// Localization helper
class AppLocalizations {
  final Map<String, dynamic> _localizedStrings;
  AppLocalizations(this._localizedStrings);

  String translate(String key, [Map<String, String>? params]) {
    var text = _localizedStrings[key] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }

  static Future<AppLocalizations> load(String languageCode) async {
    final jsonString = await rootBundle.loadString(
      'assets/translations/$languageCode.json',
    );
    final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
    return AppLocalizations(jsonMap);
  }
}

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({Key? key}) : super(key: key);

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 5,
  );

  LatLng _selectedPosition = _initialCameraPosition.target;
  // ignore: unused_field
  GoogleMapController? _mapController;
  bool _isGeocoding = false;

  AppLocalizations? loc;

  @override
  void initState() {
    super.initState();
    _loadLocalization();
  }

  Future<void> _loadLocalization() async {
    loc = await AppLocalizations.load('en');
    if (mounted) setState(() {});
  }

  Future<void> _confirmSelection() async {
    setState(() => _isGeocoding = true);
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng':
            '${_selectedPosition.latitude},${_selectedPosition.longitude}',
        'key': GOOGLE_MAPS_API_KEY,
      });

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
          final description = data['results'][0]['formatted_address'];
          final place = Place(
            description: description,
            lat: _selectedPosition.latitude,
            lng: _selectedPosition.longitude,
          );
          if (mounted) Navigator.pop(context, place);
        }
      }
    } catch (e) {
      debugPrint(
        loc?.translate('reverse_geocode_error', {'error': e.toString()}),
      );
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loc == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loc!.translate('select_location_title')),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (controller) => _mapController = controller,
            onCameraMove: (CameraPosition pos) {
              _selectedPosition = pos.target;
            },

            onCameraIdle: () {},

            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_pin,
                size: 50,
                color: Colors.red,
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                icon: _isGeocoding
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _isGeocoding
                      ? loc!.translate('getting_address')
                      : loc!.translate('confirm_location'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isGeocoding ? null : _confirmSelection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
