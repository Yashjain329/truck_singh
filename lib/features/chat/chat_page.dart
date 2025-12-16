import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../services/chat_service.dart';

class ChatPage extends StatefulWidget {
  final String roomId, chatTitle;

  const ChatPage({super.key, required this.roomId, required this.chatTitle});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chat = ChatService();
  final _controller = TextEditingController();
  late Stream<List<Map<String, dynamic>>> _messages;
  String? _userId;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _messages = _chat.getMessagesStream(widget.roomId);
    _init();
    _chat.markRoomAsRead(widget.roomId);
  }

  Future<void> _init() async {
    _userId = await _chat.getCurrentCustomUserId();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (_controller.text.trim().isNotEmpty) {
      _chat.sendMessage(
        roomId: widget.roomId,
        content: _controller.text.trim(),
      );
      _controller.clear();
    }
  }

  // ---------------- Attachments ----------------
  void _pickAttachment() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _option(Icons.camera_alt, 'take_photo_pod'.tr(), _pickCamera),
            _option(Icons.photo_library, 'choose_gallery'.tr(), _pickGallery),
          ],
        ),
      ),
    );
  }

  ListTile _option(IconData icon, String text, Function action) => ListTile(
    leading: Icon(icon),
    title: Text(text),
    onTap: () {
      Navigator.pop(context);
      action();
    },
  );

  Future<void> _pickCamera() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
    );
    if (img != null)
      _upload(File(img.path), img.name, caption: "proof_of_delivery".tr());
  }

  Future<void> _pickGallery() async {
    final result = await FilePicker.platform.pickFiles();
    if (result?.files.single.path case final path?) {
      _upload(File(path), result!.files.single.name);
    }
  }

  Future<void> _upload(File file, String name, {String? caption}) async {
    setState(() => uploading = true);
    try {
      await _chat.sendAttachment(
        roomId: widget.roomId,
        file: file,
        fileName: name,
        caption: caption,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${'error_uploading_file'.tr()} $e")),
      );
    }
    setState(() => uploading = false);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: theme.surface, // 🔥 FIX DARK MODE BACKGROUND
      appBar: AppBar(
        title: Text(widget.chatTitle),
        backgroundColor: theme.surface, // 🔥 FIX APPBAR FOR DARK MODE
        foregroundColor: theme.onSurface,
      ),
      body: Column(
        children: [
          Expanded(child: _userId == null ? _loading() : _stream()),
          if (uploading) const LinearProgressIndicator(),
          _inputField(theme),
        ],
      ),
    );
  }

  Widget _loading() => const Center(child: CircularProgressIndicator());

  Widget _stream() => StreamBuilder(
    stream: _messages,
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) return _loading();
      if (!snap.hasData || snap.data!.isEmpty) {
        return Center(child: Text("no_messages".tr()));
      }

      final msgs = snap.data!;
      return ListView.builder(
        reverse: true,
        padding: const EdgeInsets.all(12),
        itemCount: msgs.length,
        itemBuilder: (_, i) => _message(msgs[i]),
      );
    },
  );

  Widget _message(Map msg) {
    final mine = msg['sender_id'] == _userId;
    final name = mine ? "You" : msg['sender']?['name'] ?? "Unknown";
    final time = _formatTime(msg['created_at']);
    final isFile = msg['message_type'] == "attachment";

    return Column(
      crossAxisAlignment:
      mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(name, style: _meta()),
          ),
        _bubble(
          mine,
          child: isFile
              ? _attachment(msg['attachment_url'], msg['content'])
              : Text(msg['content'] ?? "", style: _text(mine)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(time, style: _meta()),
        ),
      ],
    );
  }

  Widget _bubble(bool mine, {required Widget child}) {
    final theme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: mine ? theme.primary : theme.surfaceContainerHighest, // 🔥 FIXED
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _attachment(String url, String? caption) {
    final isImage = url.toLowerCase().contains(RegExp(r"(png|jpg|jpeg|gif)$"));

    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isImage
              ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(url),
          )
              : Row(
            children: [
              const Icon(Icons.file_present),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  url.split('/').last,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if ((caption ?? "").isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(caption!),
            ),
        ],
      ),
    );
  }

  Widget _inputField(ColorScheme theme) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: uploading ? null : _pickAttachment,
            color: theme.onSurface, // 🔥 FIX FOR DARK MODE
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "type_message".tr(),
                filled: true,
                fillColor: theme.surface, // 🔥 FIX INPUT FIELD
                hintStyle:
                TextStyle(color: theme.onSurface.withValues(alpha: 0.6)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                      color: theme.outline.withValues(alpha: 0.4)), // visible in dark mode
                ),
              ),
              style: TextStyle(color: theme.onSurface),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _send,
            color: theme.primary, // 🔥 SEND BUTTON DARK MODE COMPATIBLE
          ),
        ],
      ),
    ),
  );

  // ---------------- Helpers ----------------
  String _formatTime(String? t) =>
      t == null ? "" : DateFormat('h:mm a').format(DateTime.parse(t).toLocal());

  TextStyle _meta() {
    final theme = Theme.of(context).colorScheme;
    return TextStyle(fontSize: 10, color: theme.onSurface.withValues(alpha: 0.5));
  }

  TextStyle _text(bool mine) {
    final theme = Theme.of(context).colorScheme;
    return TextStyle(color: mine ? theme.onPrimary : theme.onSurface);
  }
}