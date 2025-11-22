import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final SupabaseClient _client = Supabase.instance.client;
  static String? _currentUserCustomId;
  static Future<String?> getCurrentCustomUserId() async {
    if (_currentUserCustomId != null) {
      return _currentUserCustomId;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      if (kDebugMode) {
        print('NotificationService: No authenticated user found.');
      }
      return null;
    }

    try {
      final response = await _client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', user.id)
          .single();

      _currentUserCustomId = response['custom_user_id'] as String?;
      return _currentUserCustomId;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching current user custom_user_id: $e');
      }
      return null;
    }
  }

  static Stream<int> getUnreadCountStream() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(0);

    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((data) => data.where((n) => n['read'] == false).length);
  }
  static Future<void> sendNotification({
    required String recipientUserId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    if (recipientUserId.isEmpty) return;
    try {
      await _client.from('notifications').insert({
        'user_id': recipientUserId,
        'title': title,
        'message': message,
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
        'data': data ?? {},
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error creating in-app notification: $e');
      }
    }
    String pushRecipientId = recipientUserId;
    try {
      final profile = await _client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', recipientUserId)
          .maybeSingle();

      if (profile != null && profile['custom_user_id'] != null) {
        pushRecipientId = profile['custom_user_id'];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error resolving custom_user_id for push: $e');
      }
    }
    await sendPushNotificationToUser(
      recipientId: pushRecipientId,
      title: title,
      message: message,
      data: data,
    );
  }

  static Future<void> sendPushNotificationToUser({
    required String recipientId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    if (recipientId.isEmpty) {
      if (kDebugMode) print('Skipping push: recipientId is empty.');
      return;
    }

    try {
      await _client.functions.invoke(
        'send-user-notification',
        body: {
          'recipient_id': recipientId,
          'title': title,
          'message': message,
          'data': data ?? {},
        },
      );
      if (kDebugMode) {
        print('Push notification sent successfully to $recipientId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to send push notification to $recipientId: $e');
      }
    }
  }

  static Future<void> notifyAdmins({
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      final admins = await _client
          .from('user_profiles')
          .select('user_id')
          .eq('role', 'Admin');

      if (admins.isEmpty) return;
      for (var admin in admins) {
        final adminId = admin['user_id'] as String;
        await sendNotification(
          recipientUserId: adminId,
          title: title,
          message: message,
          data: data,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error notifying admins: $e');
      }
    }
  }
}