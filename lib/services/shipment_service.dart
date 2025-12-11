import 'dart:developer' as dev;

import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import "../services/user_data_service.dart";

class ShipmentService {
  static final _supabase = Supabase.instance.client;

  // Removed _enrichShipperData as data is now fetched directly

  static Future<List<Map<String, dynamic>>>
  getAvailableMarketplaceShipments() async {
    try {
      final response = await _supabase
          .from('shipment')
          .select('*') // Simplified query: select all columns including 'shipper_name'
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

      // 1. Fetch the user's role to determine where to store the ID
      final userProfile = await _supabase
          .from('user_profiles')
          .select('role')
          .eq('custom_user_id', companyId)
          .maybeSingle();

      final String role = userProfile?['role']?.toString().toLowerCase() ?? '';

      // 2. Determine which column to update based on role or ID prefix
      final Map<String, dynamic> updateData = {
        'booking_status': 'Accepted',
      };

      if (role.contains('truck') || role.contains('owner') || companyId.startsWith('TRUK')) {
        updateData['assigned_truckowner'] = companyId;
      } else {
        // Default to agent for 'agent' role or others
        updateData['assigned_agent'] = companyId;
      }

      await _supabase
          .from('shipment')
          .update(updateData)
          .eq('shipment_id', shipmentId);
    } catch (e) {
      print("Error accepting marketplace shipment: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllMyShipments() async {
    try {
      UserDataService.clearCache();
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('shipment')
          .select('*') // Simplified query
          .or('assigned_agent.eq.$customUserId,assigned_truckowner.eq.$customUserId');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching assigned shipments: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingShipments() async {
    try {
      UserDataService.clearCache();
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('shipment')
          .select('*') // Simplified query
          .or('assigned_agent.eq.$customUserId,assigned_truckowner.eq.$customUserId')
          .isFilter('assigned_driver', null)
          .neq('booking_status', 'Completed');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching assigned shipments: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getShipmentByStatus({
    required String status,
  }) async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('shipment')
          .select('*') // Simplified query
          .or('assigned_agent.eq.$customUserId,assigned_truckowner.eq.$customUserId')
          .eq('booking_status', status);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
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

      final response = await _supabase
          .from('shipment')
          .select('*') // Simplified query
          .or('assigned_agent.eq.$customUserId,assigned_truckowner.eq.$customUserId')
          .eq('booking_status', 'Completed');

      return List<Map<String, dynamic>>.from(response);
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
      await _supabase
          .from('shipment')
          .update({'assigned_truck': truckNumber}).eq('shipment_id', shipmentId);
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
      await _supabase
          .from('shipment')
          .update({'assigned_driver': driverUserId}).eq('shipment_id', shipmentId);
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

  static Future<List<Map<String, dynamic>>> getAvailableTrucks() async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('trucks')
          .select()
          .eq('status', 'available')
          .eq('truck_admin', customUserId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
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
          .eq('truck_admin', customUserId);

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
          .eq('owner_custom_id', customUserId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error getting trucks: $e");
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getDriverDetails(
      {required String userId}) async {
    try {
      if (userId.isEmpty) {
        throw Exception("Driver custom Id is null");
      }

      final profileResponse = await _supabase
          .from('user_profiles')
          .select('name, email,role')
          .eq('custom_user_id', userId)
          .single();

      return Map<String, dynamic>.from(profileResponse);
    } catch (e) {
      print("Error getting trucks: $e");
      rethrow;
    }
  }



  static Future<Map<String, dynamic>?> getActiveShipmentForDriver() async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) {
        throw Exception("User not logged in or has no custom ID");
      }

      final response = await _supabase
          .from('shipment')
          .select()
          .eq('assigned_driver', customUserId)
      // FIXED: Use the correct filter syntax for your package version
          .neq('booking_status','Completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if(response == null) return null;

      return Map<String, dynamic>.from(response);
    } catch (e) {
      rethrow;
    }
  }

}