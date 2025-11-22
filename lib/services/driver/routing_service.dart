import 'dart:async';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_toolkit/config/config.dart';
import 'package:http/http.dart' as http;

class RouteService {
  final double truckKPL =  7.0; // km per litre
  final double fuelPricePerLiter = 100.0;

  Future<List<RouteOption>> getTrafficAwareRoutes(
      LatLng start,
      LatLng end,
      ) async {
    const String url =
        "https://routes.googleapis.com/directions/v2:computeRoutes";

    final body = jsonEncode({
      "origin": {
        "location": {
          "latLng": {"latitude": start.latitude, "longitude": start.longitude},
        },
      },
      "destination": {
        "location": {
          "latLng": {"latitude": end.latitude, "longitude": end.longitude},
        },
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": true,
      "routeModifiers": {"avoidTolls": false, "avoidHighways": false},
      "units": "METRIC",
    });

    final headers = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": AppConfig.googleMapsApiKey,
      "X-Goog-FieldMask":
      "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.routeLabels",
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> routesJson = data['routes'] ?? [];
        return routesJson.map((r) => _parseRoute(r)).toList();
      }
      return [];
    } catch (e) {
      print("Service Error: $e");
      return [];
    }
  }

  RouteOption _parseRoute(dynamic json) {
    int distanceMeters = json['distanceMeters'] ?? 0;
    String durationStr = json['duration'] ?? "0s";
    int durationSeconds = 0;
    if (durationStr.endsWith('s')) {
      durationSeconds =
          int.tryParse(durationStr.substring(0, durationStr.length - 1)) ?? 0;
    }
    double distanceKm = distanceMeters / 1000.0;
    double fuelNeededLiters = distanceKm / truckKPL;
    double estimatedCost = fuelNeededLiters * fuelPricePerLiter;

    return RouteOption(
      polylineEncoded: json['polyline']['encodedPolyline'] ?? "",
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      fuelCost: estimatedCost,
      tags: (json['routeLabels'] as List?)?.cast<String>() ?? [],
    );
  }
}

class RouteOption {
  final String polylineEncoded;
  final int durationSeconds;
  final int distanceMeters;
  final double fuelCost;
  final List<String> tags;

  RouteOption({
    required this.polylineEncoded,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.fuelCost,
    required this.tags,
  });

  String get durationFormatted {
    int minutes = (durationSeconds / 60).round();
    if (minutes >= 60) return "${minutes ~/ 60}h ${minutes % 60}m";
    return "$minutes min";
  }
}