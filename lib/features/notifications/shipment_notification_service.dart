import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'notification_manager.dart';

class ShipmentNotificationService {
  static final ShipmentNotificationService _instance =
      ShipmentNotificationService._internal();
  factory ShipmentNotificationService() => _instance;
  ShipmentNotificationService._internal();

  final NotificationManager _notificationManager = NotificationManager();
  final SupabaseClient _supabase = Supabase.instance.client;

  // Update shipment status + notify users
  Future<void> updateShipmentStatus({
    required String shipmentId,
    required String newStatus,
    String? notes,
    String? location,
  }) async {
    try {
      final shipment =
          await _supabase
                  .from('shipment')
                  .select(
                    'shipper_id, assigned_driver, assigned_agent, pickup, drop',
                  )
                  .eq('shipment_id', shipmentId)
                  .single()
              as Map<String, dynamic>?;

      if (shipment == null) {
        debugPrint("❌ Shipment not found: $shipmentId");
        return;
      }

      // Update main table
      await _supabase
          .from('shipment')
          .update({'booking_status': newStatus})
          .eq('shipment_id', shipmentId);

      debugPrint(
        ">>> Inserting shipment update. Driver ID from fetched data: "
        "${shipment['assigned_driver']}",
      );

      // Insert update log
      await _supabase.from('shipment_updates').insert({
        'shipment_id': shipmentId,
        'status': newStatus,
        'notes': notes ?? 'Status updated to $newStatus',
        'location': location,
        'timestamp': DateTime.now().toIso8601String(),
        'assigned_driver': shipment['assigned_driver'],
        'updated_by_user_id': _supabase.auth.currentUser?.id,
      });

      // Notify involved users
      await _createShipmentStatusNotifications(shipment, newStatus, shipmentId);

      debugPrint('✅ Shipment status updated: $shipmentId -> $newStatus');
    } catch (e) {
      debugPrint('❌ Error updating shipment status: $e');
      rethrow;
    }
  }

  // Notify all users associated with this shipment
  Future<void> _createShipmentStatusNotifications(
    Map<String, dynamic> shipment,
    String newStatus,
    String shipmentId,
  ) async {
    try {
      final pickup = shipment['pickup'] ?? 'origin';
      final drop = shipment['drop'] ?? 'destination';

      // Collect all custom_user_ids
      final List<String> customUserIds = [
        if (shipment['shipper_id'] != null) shipment['shipper_id'],
        if (shipment['assigned_driver'] != null) shipment['assigned_driver'],
        if (shipment['assigned_agent'] != null) shipment['assigned_agent'],
      ].cast<String>();

      if (customUserIds.isEmpty) return;

      // Fetch user profiles in one query
      final profiles = await _supabase
          .from('user_profiles')
          .select('user_id')
          .inFilter('custom_user_id', customUserIds);

      for (final profile in profiles) {
        final userId = profile['user_id'];
        if (userId == null) continue;

        await _notificationManager.createShipmentNotification(
          userId: userId,
          shipmentId: shipmentId,
          status: newStatus,
          pickup: pickup,
          drop: drop,
        );
      }
      debugPrint(
        '✅ Notifications created for ${profiles.length} users (shipment: $shipmentId)',
      );
    } catch (e) {
      debugPrint('❌ Error creating shipment status notifications: $e');
    }
  }

  // Assign driver + notify parties
  Future<void> assignDriverToShipment({
    required String shipmentId,
    required String driverCustomId,
  }) async {
    try {
      await _supabase
          .from('shipment')
          .update({'assigned_driver': driverCustomId})
          .eq('shipment_id', shipmentId);

      final shipment =
          await _supabase
                  .from('shipment')
                  .select('assigned_agent, pickup, drop')
                  .eq('shipment_id', shipmentId)
                  .single()
              as Map<String, dynamic>?;
      if (shipment == null) {
        debugPrint("❌ Shipment not found for assignment");
        return;
      }

      await _createDriverAssignmentNotifications(
        shipment,
        driverCustomId,
        shipmentId,
      );

      debugPrint('✅ Driver $driverCustomId assigned to shipment $shipmentId');
    } catch (e) {
      debugPrint('❌ Error assigning driver: $e');
      rethrow;
    }
  }

  // Notify driver + agent after assignment
  Future<void> _createDriverAssignmentNotifications(
    Map<String, dynamic> shipment,
    String driverCustomId,
    String shipmentId,
  ) async {
    try {
      final pickup = shipment['pickup'] ?? 'origin';
      final drop = shipment['drop'] ?? 'destination';

      final profiles = await _supabase
          .from('user_profiles')
          .select('user_id, name, custom_user_id')
          .inFilter('custom_user_id', [
            driverCustomId,
            shipment['assigned_agent'],
          ]);

      // DRIVER NOTIFICATION
      final driverProfile = profiles.firstWhere(
        (p) => p['custom_user_id'] == driverCustomId,
        orElse: () => {},
      );
      String driverName = driverCustomId;
      if (driverProfile.isNotEmpty) {
        driverName = driverProfile['name'] ?? driverCustomId;
        await _notificationManager.createNotification(
          userId: driverProfile['user_id'],
          title: 'New Shipment Assignment',
          message:
              'You have been assigned to shipment $shipmentId from $pickup to $drop.',
          type: 'shipment',
          sourceId: shipmentId,
        );
      }

      // AGENT NOTIFICATION
      final agentProfile = profiles.firstWhere(
        (p) => p['custom_user_id'] == shipment['assigned_agent'],
        orElse: () => {},
      );
      if (agentProfile.isNotEmpty) {
        await _notificationManager.createNotification(
          userId: agentProfile['user_id'],
          title: 'Driver Assigned to Shipment',
          message:
              'Driver $driverName has been assigned to shipment $shipmentId.',
          type: 'shipment',
          sourceId: shipmentId,
        );
      }
    } catch (e) {
      debugPrint('❌ Error creating driver assignment notifications: $e');
    }
  }
}
