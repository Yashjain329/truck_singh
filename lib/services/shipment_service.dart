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

      final updateField = companyId.startsWith('TRUK') ? 'assigned_truckowner' : 'assigned_agent';
      await _supabase.from('shipment').update({
        'booking_status': 'Accepted',
        updateField: companyId,
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

      final updateField = customUserId.startsWith('TRUK') ? 'assigned_truckowner' : 'assigned_agent';

      final shipmentsRes = await _supabase
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq(updateField, customUserId);

      return List<Map<String, dynamic>>.from(shipmentsRes);
    } catch (e) {
      print("Error fetching assigned shipments: $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getShipmentsByStatus({
    required List<String> statuses,
    String? searchQuery,
  }) async {
    try {
      var query = Supabase.instance.client
          .from('shipment')
          .select()
          .inFilter('booking_status', statuses);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        query = query.or(
          'shipment_id.ilike.%$q%,pickup.ilike.%$q%,drop.ilike.%$q%',
        );
      }
      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in getShipmentsByStatus: $e');
      throw Exception('Failed to fetch shipments by status.');
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
}