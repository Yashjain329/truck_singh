import 'dart:async';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'encryption_service.dart';
import 'package:flutter/foundation.dart';

class ChatService {
  final SupabaseClient _client = Supabase.instance.client;
  final _unreadCountController = StreamController<int>.broadcast();
  RealtimeChannel? _messagesChannel;
  Map<String, String?>? _currentUserProfile;
  ChatService() {
    _initializeMessagesSubscription();
  }

  void dispose() {
    _unreadCountController.close();
    if (_messagesChannel != null) {
      _client.removeChannel(_messagesChannel!);
    }
  }

  Future<String?> getCurrentCustomUserId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final response = await _client.rpc('get_my_custom_id');
      return response as String?;
    } catch (e) {
      print('Could not fetch custom_user_id via RPC: $e');
      return null;
    }
  }

  Future<Map<String, String?>> _getCurrentUserProfile() async {
    if (_currentUserProfile != null) return _currentUserProfile!;

    try {
      final response = await _client
          .from('user_profiles')
          .select('custom_user_id, name')
          .eq('user_id', _client.auth.currentUser!.id)
          .maybeSingle();

      _currentUserProfile = {
        'custom_user_id': response?['custom_user_id'] as String?,
        'name': response?['name'] as String?,
      };

      return _currentUserProfile!;
    } catch (e) {
      print('Error fetching user profile: $e');
      return {'custom_user_id': null, 'name': 'Unknown User'};
    }
  }

  Future<void> _fetchAndBroadcastUnreadCount() async {
    try {
      final count = await _client.rpc('get_unread_chat_rooms_count');
      if (!_unreadCountController.isClosed) {
        _unreadCountController.add((count ?? 0) as int);
      }
    } catch (e) {
      if (!_unreadCountController.isClosed) {
        _unreadCountController.add(0);
      }
    }
  }

  void _initializeMessagesSubscription() {
    _messagesChannel = _client.channel('public:chat_messages');
    _messagesChannel!
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'chat_messages',
      callback: (payload) {
        _fetchAndBroadcastUnreadCount();
      },
    )
        .subscribe();
    _fetchAndBroadcastUnreadCount();
  }

  Stream<int> getUnreadCountStream() {
    return _unreadCountController.stream;
  }

  Future<void> sendMessage({
    required String roomId,
    required String content,
  }) async {
    final userProfile = await _getCurrentUserProfile();
    final senderId = userProfile['custom_user_id'];
    final senderName = userProfile['name'];

    if (senderId == null) throw Exception("User is not logged in");

    final encryptedContent = EncryptionService.encryptMessage(content, roomId);

    await _client.from('chat_messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': encryptedContent,
      'message_type': 'text',
    });

    // Send notification
    try {
      await _client.rpc('notify_chat_room_participants', params: {
        'p_room_id': roomId,
        'p_sender_id': senderId,
        'p_sender_name': senderName ?? 'Unknown User',
        'p_message_content': content,
      });
      print("hi");
    } catch (e) {
      if (kDebugMode) print('Failed to send chat notification: $e');
    }
  }

  Future<void> sendAttachment({
    required String roomId,
    required File file,
    required String fileName,
    String? caption,
  }) async {
    final userProfile = await _getCurrentUserProfile();
    final senderId = userProfile['custom_user_id'];
    final senderName = userProfile['name'];

    if (senderId == null) throw Exception("User is not logged in");

    try {
      await _client.rpc('authorize_attachment_upload', params: {
        'p_room_id': roomId,
      });

      final extension = p.extension(fileName);
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}$extension';
      final filePath = '$roomId/$senderId/$uniqueName';

      final fileBytes = await file.readAsBytes();

      await _client.storage.from('chat_attachments').uploadBinary(
        filePath,
        fileBytes,
        fileOptions: FileOptions(
          contentType: lookupMimeType(fileName) ?? 'application/octet-stream',
          upsert: false,
        ),
      );

      final publicUrl =
      _client.storage.from('chat_attachments').getPublicUrl(filePath);

      final String messageContent =
      (caption != null && caption.isNotEmpty) ? caption : 'Attachment: $fileName';

      final encryptedContent =
      EncryptionService.encryptMessage(messageContent, roomId);

      await _client.from('chat_messages').insert({
        'room_id': roomId,
        'sender_id': senderId,
        'content': encryptedContent,
        'message_type': 'attachment',
        'attachment_url': publicUrl,
      });
      try {
        await _client.rpc('notify_chat_room_participants', params: {
          'room_id': roomId,
          'sender_id': senderId,
          'sender_name': senderName ?? 'Unknown User',
          'message_content': messageContent,
        });
      } catch (e) {
        if (kDebugMode) print('Failed to send chat notification: $e');
      }
    } catch (e) {
      print('Error sending attachment: $e');
      rethrow;
    }
  }

  Future<String> getShipmentChatRoom(String shipmentId) async {
    final response = await _client.rpc(
      'get_or_create_shipment_chat_room',
      params: {'p_shipment_id': shipmentId},
    );
    return response as String;
  }

  Future<String> getDriverOwnerChatRoom(String driverId, String ownerId) async {
    final response = await _client.rpc(
      'get_or_create_driver_owner_chat_room',
      params: {
        'p_driver_id': driverId,
        'p_owner_id': ownerId,
      },
    );
    return response as String;
  }

  Future<String> getComplaintChatRoom(String complaintId) async {
    final response = await _client.rpc(
      'get_or_create_complaint_chat_room',
      params: {'p_complaint_id': complaintId},
    );
    return response as String;
  }

  Future<void> markRoomAsRead(String roomId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.rpc(
        'upsert_chat_read_status',
        params: {
          'p_room_id': roomId,
          'p_user_id': userId,
        },
      );
      _fetchAndBroadcastUnreadCount();
    } catch (e) {
      print('Failed to mark room as read: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getMessagesStream(String roomId) {
    final profileCache = <String, Map<String, dynamic>>{};

    Future<Map<String, dynamic>> getProfile(String customUserId) async {
      if (profileCache.containsKey(customUserId)) {
        return profileCache[customUserId]!;
      }
      try {
        final response = await _client
            .from('user_profiles')
            .select('name, role, custom_user_id')
            .eq('custom_user_id', customUserId)
            .maybeSingle();

        if (response != null) {
          profileCache[customUserId] = response;
          return response;
        } else {
          return {'name': 'Unknown User', 'role': ''};
        }
      } catch (_) {
        return {'name': 'Unknown User', 'role': ''};
      }
    }

    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at')
        .asyncMap((messages) async {
      final enriched = <Map<String, dynamic>>[];
      for (final msg in messages) {
        final decrypted =
        EncryptionService.decryptMessage(msg['content'], roomId);
        enriched.add({
          ...msg,
          'content': decrypted,
          'sender': await getProfile(msg['sender_id']),
        });
      }
      return enriched;
    });
  }
}