import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';
import "../services/user_data_service.dart";

class ShipmentService {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>>
  getAvailableMarketplaceShipments() async {
    try {
      final response = await _supabase
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('booking_status', 'Pending');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching marketplace shipments: $e");
      rethrow;
    }
  }

  static Future<void> acceptMarketplaceShipment({
    required String shipmentId,
  }) async {
    try {
      final companyId = await UserDataService.getCustomUserId();
      if (companyId == null) {
        throw Exception("Could not find company ID for the current user.");
      }

      await _supabase.from('shipment').update({
        'booking_status': 'Accepted',
        'assigned_agent': companyId,
      }).eq('shipment_id', shipmentId);
    } catch (e) {
      print("Error accepting marketplace shipment: $e");
      rethrow;
    }
  }
  static Future<List<Map<String, dynamic>>> getAllMyShipments() async {
    try {
      UserDataService.clearCache();
      final customUserId = await UserDataService.getCustomUserId();
      print(customUserId);
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final shipmentsRes = await _supabase
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('assigned_agent', customUserId);

      return List<Map<String, dynamic>>.from(shipmentsRes);
    } catch (e) {
      print("Error fetching assigned shipments: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getShipmentByStatus({
    required String status,
  }) async {
    try {

      print("STATUS FROM CHAT PROVIDERd: '${status}'");

      final customUserId = await UserDataService.getCustomUserId();

      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      var query = await _supabase
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('assigned_agent', customUserId)
          .eq('booking_status', status);


      final response =  query;
      print("STATUS FROM CHAT PROVIDERe: '${response.length}'");

      dev.log("Yo message", name: "ShipmentService");


      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("STATUS FROM CHAT PROVIDERf: '${e}'");

      print("Error fetching shipments by status: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllMyCompletedShipments() async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final shipmentsRes = await _supabase
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('assigned_agent', customUserId)
          .eq('booking_status', 'Completed');
      return List<Map<String, dynamic>>.from(shipmentsRes);
    } catch (e) {
      print("Error fetching completed shipments: $e");
      rethrow;
    }
  }

  static Future<void> assignTruck({
    required String shipmentId,
    required String truckNumber,
  }) async {
    try {
      print(truckNumber);
      await _supabase.from('shipment').update(
          {'assigned_truck': truckNumber}).eq('shipment_id', shipmentId);
    } catch (e) {
      print("Error assigning truck: $e");
      rethrow;
    }
  }

  static Future<String?> getStatusByShipmentId({required String shipmentId}) async {
    try {
      if (shipmentId.isEmpty) {
        throw Exception("Invalid ShipmentId");
      }
      final response = await Supabase.instance.client
          .from('shipment')
          .select('booking_status')
          .eq('shipment_id', shipmentId)
          .single();

      return response['booking_status'] as String?;
    } catch (e) {
      print('Error in getShipmentsByStatus: $e');
      throw Exception('Failed to fetch shipments by status.');
    }
  }

  static Future<void> assignDriver({
    required String shipmentId,
    required String driverUserId,
  }) async {
    try {
      await _supabase.from('shipment').update(
          {'assigned_driver': driverUserId}).eq('shipment_id', shipmentId);
    } catch (e) {
      print("Error assigning driver: $e");
      rethrow;
    }
  }
  static Future<void> updateStatus(String shipmentId, String newStatus) async {
    try {
      await _supabase
          .from('shipment')
          .update({'booking_status': newStatus}).eq('shipment_id', shipmentId);
    } catch (e) {
      print("Error updating shipment status: $e");
      rethrow;
    }
  }

  static Future<List<Map<String,dynamic>>> getAvailableTrucks() async {
    try{
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

    final response =  await _supabase
        .from('trucks')
        .select()
        .eq('status', 'available')
      .eq('truck_admin',customUserId);

      return List<Map<String, dynamic>>.from(response);
    }
    catch (e) {
      print("Error getting all loads: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllTrucks() async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('trucks')
          .select()
          .eq('truck_admin', customUserId); // All trucks of current user

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error getting trucks: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getSharedShipments() async {
    try {
      final response = await _supabase.rpc(
        'get_shipments_shared_with_me',
      );

      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      print("Error fetching shared shipments: $e");
      rethrow;
    }
  }


    static Future<String?> getTrackTrucks({
      required String truckId,
    }) async {
      try {
        final customUserId = await UserDataService.getCustomUserId();
        if (customUserId == null) {
          throw Exception("User not logged in or has no custom ID");
        }

        final response = await _supabase
            .from('trucks')
            .select('current_location')
            .eq('truck_admin', customUserId)
            .eq('truck_number', truckId)
            .maybeSingle();

        if (response == null) return null;

        return response['current_location']?.toString();
      } catch (e) {
        print("Error getting truck location: $e");
        rethrow;
      }
    }


  static Future<List<Map<String, dynamic>>> getAllDrivers() async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('driver_relation')
          .select('driver_custom_id')
          .eq('owner_custom_id', customUserId); // All trucks of current user

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error getting trucks: $e");
      rethrow;
    }
  }


  static Future<Map<String, dynamic>> getDriverDetails(
      {required String userId}
      ) async {
    try {

      if(userId.isEmpty){
        throw Exception("Driver custom Id is null");
      }

  final profileResponse = await _supabase
      .from('user_profiles')
      .select('name, email,role')
     // .eq('owner_custom_id', customUserId)
      .eq('custom_user_id', userId)
      .single();

      return Map<String, dynamic>.from(profileResponse);
    } catch (e) {
      print("Error getting trucks: $e");
      rethrow;
    }
  }






}