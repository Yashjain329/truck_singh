import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class EnhancedSupportTicketDetailPage extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const EnhancedSupportTicketDetailPage({super.key, required this.ticket});

  @override
  State<EnhancedSupportTicketDetailPage> createState() =>
      _EnhancedSupportTicketDetailPageState();
}

class _EnhancedSupportTicketDetailPageState
    extends State<EnhancedSupportTicketDetailPage> {
  late String _currentStatus;
  bool _isUpdating = false;
  bool _isSubmittingResponse = false;
  bool _isLoadingResponses = true;
  bool _canChangeStatus = false;

  final _responseController = TextEditingController();
  String _currentUserRole = '';
  List<Map<String, dynamic>> _responses = [];

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.ticket['status'];
    _loadResponses();
    _checkUserRole();
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _checkUserRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final data = await Supabase.instance.client
            .from('user_profiles')
            .select('role')
            .eq('user_id', user.id)
            .single();

        setState(() {
          _currentUserRole = data['role'] ?? '';
          _canChangeStatus = _currentUserRole == 'Admin';
        });
      }
    } catch (_) {}
  }

  Future<void> _loadResponses() async {
    try {
      final ticket = await Supabase.instance.client
          .from('support_tickets')
          .select('chat_messages')
          .eq('id', widget.ticket['id'])
          .single();

      final msgs = ticket['chat_messages'] as List<dynamic>? ?? [];
      setState(() {
        _responses = msgs.map((e) => Map<String, dynamic>.from(e)).toList();
        _isLoadingResponses = false;
      });
    } catch (_) {
      setState(() => _isLoadingResponses = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      await Supabase.instance.client
          .from('support_tickets')
          .update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', widget.ticket['id']);

      setState(() => _currentStatus = newStatus);
      _showSnack('Status updated successfully!', Colors.green);
    } catch (e) {
      _showSnack('Failed to update status: $e', Colors.red);
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  Future<void> _submitResponse() async {
    final text = _responseController.text.trim();
    if (text.isEmpty) {
      _showSnack("Please enter a response", Colors.orange);
      return;
    }

    setState(() => _isSubmittingResponse = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('name')
          .eq('user_id', user.id)
          .single();

      await Supabase.instance.client.rpc(
        'add_chat_message',
        params: {
          'ticket_id_param': widget.ticket['id'],
          'responder_id_param': user.id,
          'responder_name_param': profile['name'] ?? 'Admin',
          'responder_type_param': 'admin',
          'message_text': text,
        },
      );

      if (_currentStatus == 'Pending') {
        await _updateStatus('In Progress');
      }

      _responseController.clear();
      _loadResponses();
    } catch (e) {
      _showSnack("Error: $e", Colors.red);
    }

    setState(() => _isSubmittingResponse = false);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Support Ticket #${widget.ticket['id']}"),
        leading: BackButton(onPressed: () => Navigator.pop(context, true)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadResponses)],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ticketInfoCard(),
                  const SizedBox(height: 16),
                  _originalMessageCard(),
                  if (widget.ticket['screenshot_url'] != null) ...[
                    const SizedBox(height: 16),
                    _screenshotCard(),
                  ],
                  const SizedBox(height: 16),
                  _responsesSection(),
                ],
              ),
            ),
          ),
          _responseInput(),
        ],
      ),
    );
  }

  Widget _ticketInfoCard() {
    final createdAt = DateFormat('dd MMM yyyy, hh:mm a')
        .format(DateTime.parse(widget.ticket['created_at']));

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow(),
          const Divider(height: 24),
          _info(Icons.person, "user".tr(), widget.ticket['user_name']),
          _info(Icons.badge, "user_id".tr(), widget.ticket['user_custom_id']),
          _info(Icons.email, "email".tr(), widget.ticket['user_email']),
          _info(Icons.work, "role".tr(), widget.ticket['user_role']),
          _info(Icons.access_time, "created".tr(), createdAt),
          const SizedBox(height: 16),
          _statusRow(),
        ],
      ),
    );
  }

  Widget _titleRow() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.ticket['subject'] ?? '',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("${"Category".tr()}: ${widget.ticket['category'].toString().tr()}"),
              Text("${"Priority".tr()}: ${widget.ticket['priority'].toString().tr()}",
                  style: TextStyle(color: _priorityColor(widget.ticket['priority']))),
            ],
          ),
        ),
        _statusBadge(),
      ],
    );
  }

  Widget _statusBadge() {
    final color = _statusColor(_currentStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
      BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(16)),
      child: Text(_currentStatus.toString().tr(), style: TextStyle(color: color)),
    );
  }

  Widget _statusRow() {
    return Row(
      children: [
        Text("${"status".tr()}:", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 16),
        Expanded(
          child: _isUpdating
              ? const LinearProgressIndicator()
              : !_canChangeStatus
              ? _readonlyStatus()
              : DropdownButton<String>(
            value: _currentStatus,
            isExpanded: true,
            items: ['Pending', 'In Progress', 'Resolved']
                .map((e) => DropdownMenuItem(value: e, child: Text(e.tr())))
                .toList(),
            onChanged: (val) => val == null ? null : _updateStatus(val),
          ),
        )
      ],
    );
  }

  Widget _readonlyStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange)),
      child: Text(_currentStatus),
    );
  }

  Widget _originalMessageCard() =>
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _iconTitle(Icons.message, "original_message".tr()),
        const SizedBox(height: 12),
        SelectableText(widget.ticket['message']),
      ]));

  Widget _screenshotCard() {
    final url = widget.ticket['screenshot_url'];
    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _iconTitle(Icons.image, "attached_screenshot".tr()),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            if (await canLaunchUrl(Uri.parse(url))) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (c, child, p) =>
                p == null ? child : const Center(child: CircularProgressIndicator())),
          ),
        ),
      ]),
    );
  }

  Widget _responsesSection() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconTitle(Icons.chat, "conversation".tr()),
          const SizedBox(height: 16),
          if (_isLoadingResponses)
            const Center(child: CircularProgressIndicator())
          else if (_responses.isEmpty)
            Center(child: Text("no_responses".tr()))
          else
            ..._responses.map(_responseBubble),
        ],
      ),
    );
  }

  Widget _responseBubble(Map<String, dynamic> msg) {
    final isAdmin = msg['responder_type'] == 'admin';
    final time =
    DateFormat('dd MMM, hh:mm a').format(DateTime.parse(msg['timestamp']));

    final bg = isAdmin ? Colors.blue : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
              radius: 16, backgroundColor: bg, child: Icon(Icons.person, size: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: bg.withValues(alpha: 0.1),
                  border: Border.all(color: bg.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(msg['responder_name'],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Spacer(),
                    Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 4),
                  SelectableText(msg['message']),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _responseInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          Expanded(
              child: TextField(
                controller: _responseController,
                maxLines: 3,
                decoration: InputDecoration(
                    hintText: "type_response_hint".tr(),
                    border: OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12)),
              )),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSubmittingResponse ? null : _submitResponse,
            label: Text('send'.tr()),
            icon: _isSubmittingResponse
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator())
                : const Icon(Icons.send),
          )
        ],
      ),
    );
  }

  Widget _card(Widget child) =>
      Card(color: Theme.of(context).cardColor, child: Padding(padding: const EdgeInsets.all(16), child: child));

  Widget _iconTitle(IconData icon, String text) => Row(
    children: [Icon(icon, color: Colors.blue), const SizedBox(width: 8), Text(text, style: const TextStyle(fontWeight: FontWeight.bold))],
  );

  Widget _info(IconData icon, String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 16),
      const SizedBox(width: 8),
      Text("$label: "),
      Expanded(child: Text(value ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500))),
    ]),
  );

  Color _statusColor(String s) =>
      {'Pending': Colors.orange, 'In Progress': Colors.blue, 'Resolved': Colors.green}[s] ?? Colors.grey;

  Color _priorityColor(String p) =>
      {'Low': Colors.green, 'Medium': Colors.orange, 'High': Colors.red, 'Urgent': Colors.purple}[p] ??
          Colors.grey;
}