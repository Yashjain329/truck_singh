import 'package:supabase_flutter/supabase_flutter.dart';

class MyTripsServices {
  final _client = Supabase.instance.client;

  Future<Map<String, String?>> getUserProfile(String userId) async {
    final profile = await _client
        .from('user_profiles')
        .select('custom_user_id, role')
        .eq('user_id', userId)
        .maybeSingle();

    if (profile == null) return {};
    return {
      'custom_user_id': profile['custom_user_id'] as String?,
      'role': profile['role'] as String?,
    };
  }

  Future<List<Map<String, dynamic>>> getShipmentsForUser(String userId) async {
    final profile = await getUserProfile(userId);
    final customId = profile['custom_user_id'];
    final role = profile['role'];

    if (customId == null || role == null) {
      return [];
    }

    // Use complex fetch for all roles to ensure creators see their shipments
    // regardless of their current role (e.g. a Truck Owner who acted as a Shipper)
    return _getShipmentsComplex(customId);
  }

  // Helper to fetch shipments where user is EITHER shipper, agent, or truckowner
  Future<List<Map<String, dynamic>>> _getShipmentsComplex(String customId) async {
    try {
      final response = await _client
          .from('shipment')
          .select()
          .or('shipper_id.eq.$customId,assigned_agent.eq.$customId,assigned_truckowner.eq.$customId')
          .order('created_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching complex shipments: $e");
      return [];
    }
  }

  Future<Map<String, int>> getRatingEditCounts() async {
    final response = await _client
        .from('ratings')
        .select('shipment_id, edit_count');

    if (response.isNotEmpty) {
      final Map<String, int> editCounts = {};
      for (var row in response) {
        editCounts[row['shipment_id']] = row['edit_count'] as int;
      }
      return editCounts;
    }
    return {};
  }

  // NEW: Batch fetch user names for "Managed By" tag
  Future<Map<String, String>> getUserNames(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    try {
      // Remove duplicates
      final uniqueIds = userIds.toSet().toList();

      final response = await _client
          .from('user_profiles')
          .select('custom_user_id, name')
      // Changed .in_() to .filter() to resolve "method not defined" error
          .filter('custom_user_id', 'in', uniqueIds);

      final Map<String, String> names = {};
      for (var row in response) {
        if (row['custom_user_id'] != null && row['name'] != null) {
          names[row['custom_user_id']] = row['name'];
        }
      }
      return names;
    } catch (e) {
      print('Error fetching user names: $e');
      return {};
    }
  }
}