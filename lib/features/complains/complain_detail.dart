import 'package:flutter/material.dart';
import 'package:logistics_toolkit/services/user_data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/services/chat_service.dart';
import 'package:logistics_toolkit/features/chat/chat_page.dart';
import 'package:logistics_toolkit/features/notifications/notification_service.dart';
import 'complain_screen.dart';

class ComplaintDetailsPage extends StatefulWidget {
  final Map<String, dynamic> complaint;
  const ComplaintDetailsPage({super.key, required this.complaint});

  @override
  State<ComplaintDetailsPage> createState() => _ComplaintDetailsPageState();
}

class _ComplaintDetailsPageState extends State<ComplaintDetailsPage> {
  late Map<String, dynamic> _currentComplaint;
  bool _isActionLoading = false;
  bool _isLoading = true;
  RealtimeChannel? _complaintChannel;
  late Future<String?> _userIdFuture;
  final _chat = ChatService();

  @override
  void initState() {
    super.initState();
    _currentComplaint = widget.complaint;
    _userIdFuture = UserDataService.getCustomUserId();
    _initializePage();
  }

  @override
  void dispose() {
    if (_complaintChannel != null) {
      Supabase.instance.client.removeChannel(_complaintChannel!);
    }
    super.dispose();
  }

  Future<void> _initializePage() async {
    setupRealtimeSubscription();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void setupRealtimeSubscription() {
    final complaintId = _currentComplaint['id'];
    if (complaintId == null) return;

    final channelName = 'complaint-details:$complaintId';
    _complaintChannel = Supabase.instance.client.channel(channelName);

    _complaintChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'complaints',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: complaintId,
          ),
          callback: (payload) {
            if (!mounted) return;

            if (payload.eventType == 'UPDATE') {
              setState(() => _currentComplaint = payload.newRecord);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('complaint_updated'.tr()),
                  backgroundColor: Colors.blue,
                ),
              );
            } else if (payload.eventType == 'DELETE') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('complaint_deleted'.tr()),
                  backgroundColor: Colors.orange,
                ),
              );
              Navigator.pop(context);
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshComplaint() async {
    try {
      final freshData = await Supabase.instance.client
          .from('complaints')
          .select()
          .eq('id', _currentComplaint['id'])
          .single();

      if (mounted) {
        setState(() => _currentComplaint = freshData);
      }
    } catch (_) {}
  }

  Future<void> _performAction(Future<void> Function() action) async {
    setState(() => _isActionLoading = true);
    try {
      await action();
      await _refreshComplaint();
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _editComplaint() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComplaintPage(
          editMode: true,
          complaintData: _currentComplaint,
          preFilledShipmentId: _currentComplaint['shipment_id'],
        ),
      ),
    );
  }

  Future<void> _deleteComplaint() async {
    final confirmed = await _showConfirmationDialog(
      'delete_complaint'.tr(),
      'delete_warning'.tr(),
      isDestructive: true,
    );

    if (confirmed != true) return;

    _performAction(() async {
      await Supabase.instance.client
          .from('complaints')
          .delete()
          .eq('id', _currentComplaint['id']);

      final attachmentUrl = _currentComplaint['attachment_url'];
      if (attachmentUrl != null) {
        final pathMatch = RegExp(
          r'/storage/v1/object/public/complaint-attachments/(.+)',
        ).firstMatch(attachmentUrl);

        if (pathMatch != null) {
          final filePath = pathMatch.group(1);
          if (filePath != null) {
            await Supabase.instance.client.storage
                .from('complaint-attachments')
                .remove([filePath]);
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('complaint_deleted_success'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  Future<void> _appealComplaint() async {
    final confirmed = await _showConfirmationDialog(
      'appeal_decision'.tr(),
      'appeal_warning'.tr(),
    );

    if (confirmed != true) return;

    _performAction(() async {
      final time = DateTime.now().toIso8601String();

      final historyEvent = {
        'type': 'appealed',
        'title': 'Decision Appealed',
        'description': 'Status reverted to "Open"',
        'timestamp': time,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
      };

      final existing = _currentComplaint['history'] as Map? ?? {};
      final events = List.from(existing['events'] ?? []);
      events.add(historyEvent);

      await Supabase.instance.client
          .from('complaints')
          .update({
            'status': 'Open',
            'agent_justification': null,
            'history': {'events': events},
          })
          .eq('id', _currentComplaint['id']);
    });
  }

  Future<void> _showSendNotificationDialog() async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final messageController = TextEditingController();

    // These correspond to the parties involved in the complaint
    final recipientOptions = {
      'complainer'.tr(): _currentComplaint['user_id'],
      'target'.tr(): _currentComplaint['target_user_id'],
    };

    // Default to notifying the complainer
    String? selectedRecipientId = recipientOptions['Complainer'];

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        // Use a StatefulWidget to manage the state of the dropdown inside the dialog
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('send_notification'.tr()),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Recipient Role Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: selectedRecipientId,
                        decoration: InputDecoration(
                          labelText: 'select_recipient_role'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        items: recipientOptions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.value,
                            child: Text(entry.key),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() {
                            selectedRecipientId = newValue;
                          });
                        },
                        validator: (value) => value == null || value.isEmpty
                            ? 'recipient_required'.tr()
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Title Field
                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'notification_title'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'required_field'.tr()
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Message Field
                      TextFormField(
                        controller: messageController,
                        decoration: InputDecoration(
                          labelText: 'type_message'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 4,
                        validator: (value) => value == null || value.isEmpty
                            ? 'required_field'.tr()
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('cancel'.tr()),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                FilledButton(
                  child: Text('send'.tr()),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      // Perform the send action
                      await NotificationService.sendNotification(
                        recipientUserId: selectedRecipientId!,
                        title: titleController.text,
                        message: messageController.text,
                        data: {'complaint_id': _currentComplaint['id']},
                      );

                      if (!mounted) return;
                      Navigator.of(context).pop(); // Close the dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('notification_sent_successfully'.tr()),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmComplaintChat(String complaintId, name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("start_chat".tr()),
        content: Text("confirm_start_chat $name?".tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("cancel".tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("start".tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final agentId = await _chat.getCurrentCustomUserId();
      if (agentId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("user_not_identified".tr())));
        return;
      }

      _openChat(
        "Chat with $name",
        () => _chat.getComplaintChatRoom(complaintId),
      );
    }
  }

  Future<void> _openChat(String title, Future<String> Function() room) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("opening_chat".tr())));

      final roomId = await room();

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(roomId: roomId, chatTitle: title),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("failed_open_chat $e".tr())));
      }
    }
  }

  Future<void> _manageComplaint() async {
    final managerId = await UserDataService.getCustomUserId();
    if (managerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("user_not_identified".tr())));
      }
      return;
    }
    _performAction(() async {
      if (_currentComplaint['managed_by'] != null &&
          _currentComplaint['managed_by'] != managerId) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("already_managed".tr())));
        return;
      }
      if (_currentComplaint['managed_by'] == managerId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("already_managing_complaint".tr())),
        );
        return;
      }

      final time = DateTime.now().toIso8601String();

      final historyEvent = {
        'type': 'managed',
        'title': 'Complaint Managed',
        'description': 'Complaint is now being managed.',
        'timestamp': time,
        'user_id': managerId,
      };

      final existing = _currentComplaint['history'] as Map? ?? {};
      final events = List.from(existing['events'] ?? []);
      events.add(historyEvent);

      await Supabase.instance.client
          .from('complaints')
          .update({
            'managed_by': managerId,
            'history': {'events': events},
          })
          .eq('id', _currentComplaint['id']);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("success".tr())));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('complaint_details_section'.tr()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refreshComplaint,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildStatusHeader(),
                      const SizedBox(height: 8),
                      _buildBasicInfo(),
                      const SizedBox(height: 8),
                      _buildTimeline(),
                      const SizedBox(height: 8),
                      _buildComplaintDetails(),
                      if (_currentComplaint['attachment_url'] != null) ...[
                        const SizedBox(height: 8),
                        _buildAttachment(),
                      ],
                      const SizedBox(height: 8),
                      _buildActions(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildActions() {
    final isComplaintOwner =
        _currentComplaint['user_id'] ==
        Supabase.instance.client.auth.currentUser?.id;
    final status = _currentComplaint['status'];
    final canAppeal =
        isComplaintOwner && (status == 'Rejected' || status == 'Resolved');
    final canEdit = isComplaintOwner && status != 'Resolved';

    return FutureBuilder<String?>(
      future: _userIdFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final customUserId = snapshot.data;
        final bool isAdmin = customUserId?.startsWith('ADM') ?? false;
        final List<Widget> actions = [];

        if (_isActionLoading) {
          actions.add(const Center(child: CircularProgressIndicator()));
        } else {
          if (isAdmin) {
            if (_currentComplaint['managed_by'] != customUserId) {
              actions.add(
                TextButton.icon(
                  onPressed: _manageComplaint,
                  icon: const Icon(Icons.control_point_outlined),
                  label: Text('manage_complaint'.tr()),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                ),
              );
            }
            if (_currentComplaint['managed_by'] == customUserId) {
              actions.add(
                TextButton.icon(
                  onPressed: _showSendNotificationDialog,
                  icon: const Icon(Icons.send_to_mobile),
                  label: Text('send_notification'.tr()),
                  style: TextButton.styleFrom(foregroundColor: Colors.purple),
                ),
              );
            }
          } else {
            actions.add(
              ElevatedButton.icon(
                onPressed: () => _confirmComplaintChat(
                  _currentComplaint['id'],
                  _currentComplaint['complainer_user_name'],
                ),
                icon: const Icon(Icons.chat),
                label: Text('chat'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            );
          }
          if (canEdit) {
            actions.add(
              ElevatedButton.icon(
                onPressed: _editComplaint,
                icon: const Icon(Icons.edit),
                label: Text('edit_complaint'.tr()),
              ),
            );
          } else if (canAppeal) {
            actions.add(
              ElevatedButton.icon(
                onPressed: _appealComplaint,
                icon: const Icon(Icons.undo),
                label: Text('appeal_decision_btn'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            );
          }
        }

        if (isComplaintOwner) {
          actions.add(
            TextButton.icon(
              onPressed: _deleteComplaint,
              icon: const Icon(Icons.delete_forever),
              label: Text('delete_complaint'.tr()),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          );
        }

        if (actions.isEmpty) {
          return Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'no_actions'.tr(),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(actions.length, (index) {
                return Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 8.0),
                  child: actions[index],
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusHeader() {
    final status = _currentComplaint['status'] ?? 'Unknown';
    final statusConfig = _getStatusConfig(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusConfig['icon'], color: statusConfig['color'], size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${"status".tr()}: ${status.toString().toLowerCase().tr()}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusConfig['color'],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${_currentComplaint['id'] ?? 'N/A'}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow('subject'.tr(), _currentComplaint['subject']),
            _buildInfoRow('managed_by'.tr(), _currentComplaint['managed_by']),
            _buildInfoRow(
              'complainer'.tr(),
              _currentComplaint['complainer_user_name'],
            ),
            _buildInfoRow('target'.tr(), _currentComplaint['target_user_name']),
            if (_currentComplaint['shipment_id'] != null)
              _buildInfoRow(
                'shipment_id'.tr(),
                _currentComplaint['shipment_id'],
              ),
            _buildInfoRow(
              'created'.tr(),
              DateFormat("MMM dd, yyyy - hh:mm a").format(
                DateTime.parse(_currentComplaint['created_at']).toLocal(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(child: Text(value?.toString() ?? "N/A")),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final history = _currentComplaint['history'] as Map?;
    final events = List<Map<String, dynamic>>.from((history?['events'] ?? []));

    if (events.isEmpty) {
      events.add({
        'type': 'created',
        'title': 'Complaint Filed',
        'description': 'Complaint submitted',
        'timestamp': _currentComplaint['created_at'],
      });
    }

    events.sort(
      (a, b) => DateTime.parse(
        b['timestamp'],
      ).compareTo(DateTime.parse(a['timestamp'])),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [...events.map((e) => _buildTimelineItem(e))]),
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> event) {
    final color = _getColorForEvent(event['type']);
    final icon = _getIconForEvent(event['type']);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.2),
              child: Icon(icon, color: color),
            ),
            Container(height: 50, width: 2, color: Colors.grey.shade300),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event['title'] ?? ''),
              Text(
                event['description'] ?? '',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              Text(
                DateFormat(
                  "MMM dd, yyyy - hh:mm a",
                ).format(DateTime.parse(event['timestamp'])),
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComplaintDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _currentComplaint['complaint'] ?? 'No details provided',
          style: TextStyle(height: 1.5),
        ),
      ),
    );
  }

  Widget _buildAttachment() {
    final url = _currentComplaint['attachment_url'];
    if (url == null) return SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => _showImageDialog(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 200,
              width: double.infinity, // Ensure it fills width
              fit: BoxFit.cover,
              // Add this error builder
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.grey),
                        Text("Image failed to load"),
                      ],
                    ),
                  ),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Image.network(imageUrl),
            IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showConfirmationDialog(
    String title,
    String content, {
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            child: Text("cancel".tr()),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.green,
            ),
            child: Text("confirm".tr()),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    switch (status) {
      case 'Open':
        return {'color': Colors.orange, 'icon': Icons.schedule};
      case 'Resolved':
        return {'color': Colors.green, 'icon': Icons.check_circle};
      case 'Rejected':
        return {'color': Colors.red, 'icon': Icons.cancel};
      default:
        return {'color': Colors.grey, 'icon': Icons.info};
    }
  }

  IconData _getIconForEvent(String type) {
    switch (type) {
      case 'resolved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'appealed':
        return Icons.undo;
      default:
        return Icons.info;
    }
  }

  Color _getColorForEvent(String type) {
    switch (type) {
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'appealed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
