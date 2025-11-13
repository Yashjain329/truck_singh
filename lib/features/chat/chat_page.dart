import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/chat_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  final String chatTitle;

  const ChatPage({super.key, required this.roomId, required this.chatTitle});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> _messagesStream;
  String? _currentCustomUserId;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _messagesStream = _chatService.getMessagesStream(widget.roomId);
    _loadCurrentUser();
    // Mark the room as read when the user enters
    _chatService.markRoomAsRead(widget.roomId);
  }

  Future<void> _loadCurrentUser() async {
    _currentCustomUserId = await _chatService.getCurrentCustomUserId();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _refreshMessages() async {
    await _chatService.markRoomAsRead(widget.roomId);
    setState(() {
      _messagesStream = _chatService.getMessagesStream(widget.roomId);
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    _chatService.sendMessage(
      roomId: widget.roomId,
      content: _messageController.text.trim(),
    );
    _messageController.clear();
  }

  // Shows a bottom sheet with upload options
  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text('take_photo_pod'.tr()),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text('choose_gallery'.tr()),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Handles taking a picture with the camera
  Future<void> _handleCamera() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
    );
    if (image != null) {
      _handleFileUpload(
        File(image.path),
        image.name,
        caption: 'proof_of_delivery'.tr(),
      );
    }
  }

  // Handles picking a file from the gallery
  Future<void> _handleGallery() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      _handleFileUpload(File(file.path!), file.name);
    }
  }

  // Generic file upload handler
  Future<void> _handleFileUpload(
    File file,
    String fileName, {
    String? caption,
  }) async {
    setState(() => _isUploading = true);
    try {
      // We pass the raw file and name to the service now
      await _chatService.sendAttachment(
        roomId: widget.roomId,
        file: file,
        fileName: fileName,
        caption: caption,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('error_uploading_file $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatTitle),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    _currentCustomUserId == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshMessages,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(child: Text('no_messages'.tr())),
                      ),
                    ),
                  );
                }

                final messages = snapshot.data!;

                return RefreshIndicator(
                  onRefresh: _refreshMessages,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMine =
                          message['sender_id'] == _currentCustomUserId;
                      final senderProfile =
                          message['sender'] as Map<String, dynamic>? ?? {};
                      final senderName =
                          senderProfile['name'] as String? ?? 'Unknown';
                      final senderRole = senderProfile['role'] as String? ?? '';
                      final timestamp = message['created_at'] as String?;
                      final messageType = message['message_type'] ?? 'text';
                      final attachmentUrl = message['attachment_url'];
                      final content = message['content'] as String? ?? '';

                      if (messageType == 'attachment' &&
                          attachmentUrl != null) {
                        return _AttachmentBubble(
                          url: attachmentUrl,
                          caption: content,
                          isMine: isMine,
                          senderName: senderName,
                          senderRole: senderRole,
                          timestamp: timestamp,
                        );
                      }

                      return _MessageBubble(
                        message: content,
                        isMine: isMine,
                        senderName: isMine ? 'You' : senderName,
                        senderRole: senderRole,
                        timestamp: timestamp,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (_isUploading) const LinearProgressIndicator(),
          _messageInputField(),
        ],
      ),
    );
  }

  Widget _messageInputField() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: _isUploading ? null : _showAttachmentOptions,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'type_message'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]
                      : Colors.grey[200],
                  hintStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
} // end of _ChatPageState

// ----------------- helper widgets below (outside of _ChatPageState) -----------------

class _MessageBubble extends StatelessWidget {
  final String message;
  final bool isMine;
  final String senderName;
  final String senderRole;
  final String? timestamp;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.senderRole,
    this.timestamp,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final displayRole = senderRole.isNotEmpty
        ? senderRole[0].toUpperCase() + senderRole.substring(1)
        : '';

    String formattedTime = '';
    if (timestamp != null) {
      try {
        final dateTime = DateTime.parse(timestamp!).toLocal();
        formattedTime = DateFormat('h:mm a').format(dateTime);
      } catch (e) {
        formattedTime = '';
      }
    }

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!isMine)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4, top: 8),
            child: Text(
              '$senderName (${displayRole})',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: isMine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? (isMine ? Colors.teal[400] : Colors.white)
                      : (isMine
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isMine
                        ? const Radius.circular(16)
                        : Radius.zero,
                    bottomRight: isMine
                        ? Radius.zero
                        : const Radius.circular(16),
                  ),
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? (isMine ? Colors.white : Colors.black)
                        : (isMine
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Text(
            formattedTime,
            style: TextStyle(color: Colors.grey[500], fontSize: 10),
          ),
        ),
      ],
    );
  }
}

class _AttachmentBubble extends StatelessWidget {
  final String url;
  final String caption;
  final bool isMine;
  final String senderName;
  final String senderRole;
  final String? timestamp;

  const _AttachmentBubble({
    required this.url,
    required this.caption,
    required this.isMine,
    required this.senderName,
    required this.senderRole,
    this.timestamp,
    Key? key,
  }) : super(key: key);

  bool get _isImage {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.gif');
  }

  @override
  Widget build(BuildContext context) {
    final displayRole = senderRole.isNotEmpty
        ? senderRole[0].toUpperCase() + senderRole.substring(1)
        : '';

    String formattedTime = '';
    if (timestamp != null) {
      try {
        final dateTime = DateTime.parse(timestamp!).toLocal();
        formattedTime = DateFormat('h:mm a').format(dateTime);
      } catch (e) {
        formattedTime = '';
      }
    }

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!isMine)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4, top: 8),
            child: Text('$senderName ($displayRole)'),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          decoration: BoxDecoration(
            color: isMine
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: _isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(url, fit: BoxFit.cover),
                      )
                    : Container(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file, size: 32),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                Uri.decodeComponent(url.split('/').last),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (caption.isNotEmpty && !caption.startsWith('Attachment:'))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Text(caption),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Text(
            formattedTime,
            style: TextStyle(color: Colors.grey[500], fontSize: 10),
          ),
        ),
      ],
    );
  }
}
