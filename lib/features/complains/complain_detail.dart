import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'complain_screen.dart';

class ComplaintDetailsPage extends StatefulWidget {
  final Map<String, dynamic> complaint;
  const ComplaintDetailsPage({super.key, required this.complaint});

  @override
  State<ComplaintDetailsPage> createState() => _ComplaintDetailsPageState();
}

class _ComplaintDetailsPageState extends State<ComplaintDetailsPage> {
  late Map<String, dynamic> _currentComplaint;
  String? _currentUserRole;
  bool _isActionLoading = false;
  bool _isLoading = true;
  RealtimeChannel? _complaintChannel;

  @override
  void initState() {
    super.initState();
    _currentComplaint = widget.complaint;
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
    await _fetchCurrentUserRole();
    setupRealtimeSubscription();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCurrentUserRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('role')
          .eq('user_id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _currentUserRole = profile['role'];
        });
      }
    } catch (e) {
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
        if (mounted) {
          if (payload.eventType == 'UPDATE') {
            setState(() {
              _currentComplaint = payload.newRecord;
            });
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
            Navigator.of(context).pop();
          }
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
        setState(() {
          _currentComplaint = freshData;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to refresh: ${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _isAgent(String? role) => role == 'company' || role == 'truckowner';

  Future<void> _performAction(Future<void> Function() action) async {
    setState(() => _isActionLoading = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
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
        'delete_complaint'.tr(), 'delete_warning'.tr(),
        isDestructive: true);
    if (confirmed != true) return;

    _performAction(() async {
      try {
        await Supabase.instance.client
            .from('complaints')
            .delete()
            .eq('id', _currentComplaint['id']);

        final attachmentUrl = _currentComplaint['attachment_url'];
        if (attachmentUrl != null) {
          final pathMatch =
          RegExp(r'/storage/v1/object/public/complaint-attachments/(.+)')
              .firstMatch(attachmentUrl);
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('complaint_deleted_success'.tr()),
              backgroundColor: Colors.green));
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('error_deleting: ${e.toString()}'),
              backgroundColor: Colors.red));
        }
      }
    });
  }

  Future<void> _handleAgentAction(
      String action, String title, String eventType, String eventTitle) async {
    final justificationController = TextEditingController();
    final confirmed =
    await _showJustificationDialog(title, action, justificationController);

    if (confirmed == true) {
      _performAction(() async {
        final actionTime = DateTime.now().toIso8601String();
        final historyEvent = {
          'type': eventType,
          'title': eventTitle,
          'description': justificationController.text.trim(),
          'timestamp': actionTime,
          'user_id': Supabase.instance.client.auth.currentUser?.id,
        };

        final existingHistory =
            _currentComplaint['history'] as Map<String, dynamic>? ?? {};
        final events =
        List<dynamic>.from(existingHistory['events'] as List? ?? []);
        events.add(historyEvent);

        try {
          await Supabase.instance.client.from('complaints').update({
            'status': eventTitle,
            'agent_justification': justificationController.text.trim(),
            'history': {'events': events},
          }).eq('id', _currentComplaint['id']);

          await _refreshComplaint();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red));
          }
        }
      });
    }
  }

  Future<void> _appealComplaint() async {
    final confirmed = await _showConfirmationDialog('appeal_decision'.tr(),
        'appeal_warning'.tr());
    if (confirmed != true) return;

    _performAction(() async {
      final appealTime = DateTime.now().toIso8601String();
      final historyEvent = {
        'type': 'appealed',
        'title': 'Decision Appealed',
        'description': 'Status reverted to "Open"',
        'timestamp': appealTime,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
      };

      final existingHistory =
          _currentComplaint['history'] as Map<String, dynamic>? ?? {};
      final events =
      List<dynamic>.from(existingHistory['events'] as List? ?? []);
      events.add(historyEvent);

      try {
        await Supabase.instance.client.from('complaints').update({
          'status': 'Open',
          'agent_justification': null,
          'history': {'events': events},
        }).eq('id', _currentComplaint['id']);

        await _refreshComplaint();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error appealing: ${e.toString()}'),
              backgroundColor: Colors.red));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:Text('complaint_details_section'.tr()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _refreshComplaint,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusHeader(),
              const SizedBox(height: 16),
              _buildBasicInfo(),
              const SizedBox(height: 16),
              _buildTimeline(),
              const SizedBox(height: 16),
              _buildComplaintDetails(),
              const SizedBox(height: 16),
              if (_currentComplaint['attachment_url'] != null)
                _buildAttachment(),
              const SizedBox(height: 16),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  // --- BUILD WIDGETS ---

  Widget _buildStatusHeader() {
    final status = _currentComplaint['status'] ?? 'Unknown';
    final statusConfig = _getStatusConfig(status);
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(statusConfig['icon'], color: statusConfig['color'], size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: $status',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: statusConfig['color'])),
                  const SizedBox(height: 4),
                  Text('ID: ${_currentComplaint['id'] ?? 'N/A'}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('basic_information'.tr(),
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            _buildInfoRow('subject'.tr(), _currentComplaint['subject'] ?? 'N/A'),
            _buildInfoRow('complainer'.tr(),
                _currentComplaint['complainer_user_name'] ?? 'N/A'),
            _buildInfoRow(
                'target'.tr(), _currentComplaint['target_user_name'] ?? 'N/A'),
            if (_currentComplaint['shipment_id'] != null)
              _buildInfoRow('shipment_id'.tr(), _currentComplaint['shipment_id']),
            _buildInfoRow(
                'created'.tr(),
                DateFormat('MMM dd, yyyy - hh:mm a')
                    .format(DateTime.parse(_currentComplaint['created_at']))),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade600)),
          ),
          Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final history = _currentComplaint['history'] as Map<String, dynamic>?;
    final events =
    List<Map<String, dynamic>>.from(history?['events'] as List? ?? []);

    if (events.isEmpty) {
      events.add({
        'type': 'created',
        'title': 'Complaint Filed',
        'description': 'Complaint was submitted',
        'timestamp': _currentComplaint['created_at']
      });
    }

    events.sort((a, b) => DateTime.parse(b['timestamp'])
        .compareTo(DateTime.parse(a['timestamp'])));

    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('timeline'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            ...List.generate(
                events.length,
                    (index) => _buildTimelineItem(events[index],
                    isLast: index == events.length - 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> event, {bool isLast = false}) {
    final eventType = event['type'] as String? ?? 'info';
    final color = _getColorForEvent(eventType);
    final icon = _getIconForEvent(eventType);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withAlpha((255 * 0.15).round()),
              child: Icon(icon, color: color, size: 18),
            ),
            if (!isLast)
              Container(width: 2, height: 60, color: Colors.grey.shade300),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title'] ?? 'Event',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(event['description'.tr()] ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                Text(
                    DateFormat('MMM dd, yyyy - hh:mm a')
                        .format(DateTime.parse(event['timestamp'])),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComplaintDetails() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('complaint_details_section'.tr(),
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            Text(
              _currentComplaint['complaint'] ?? 'No details provided',
              style:
              Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachment() {
    final attachmentUrl = _currentComplaint['attachment_url'];
    if (attachmentUrl == null) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('attachment'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            GestureDetector(
              onTap: () => _showImageDialog(attachmentUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  attachmentUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (context, error, stack) => const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.grey, size: 50)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final isAgent = _isAgent(_currentUserRole);
    final isComplaintOwner = _currentComplaint['user_id'] ==
        Supabase.instance.client.auth.currentUser?.id;
    final status = _currentComplaint['status'] as String?;

    final canEdit = isComplaintOwner && status == 'Open';
    final canAppeal =
        isComplaintOwner && (status == 'Resolved' || status == 'Rejected');

    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('actions'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            if (_isActionLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator()))
            else if (isAgent && status == 'Open')
              Row(
                children: [
                  Expanded(
                      child: ElevatedButton.icon(
                          onPressed: () => _handleAgentAction('Resolve',
                              'Resolve Complaint', 'resolved', 'Resolved'),
                          icon: const Icon(Icons.check),
                          label: const Text('Resolve'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: ElevatedButton.icon(
                          onPressed: () => _handleAgentAction('Reject',
                              'Reject Complaint', 'rejected', 'Rejected'),
                          icon: const Icon(Icons.cancel),
                          label: const Text('Reject'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white))),
                ],
              )
            else if (canEdit)
                ElevatedButton.icon(
                    onPressed: _editComplaint,
                    icon: const Icon(Icons.edit),
                    label: Text('edit_complaint'.tr()))
              else if (canAppeal)
                  ElevatedButton.icon(
                      onPressed: _appealComplaint,
                      icon: const Icon(Icons.undo),
                      label: Text('appeal_decision_btn'.tr()),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white))
                else
                  Text('no_actions'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)),
            if (isComplaintOwner) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: _deleteComplaint,
                  icon: const Icon(Icons.delete_forever),
                  label: Text('delete_complaint'.tr()),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700)),
            ]
          ],
        ),
      ),
    );
  }

  // --- DIALOGS AND HELPERS ---

  void _showImageDialog(String imageUrl) {
    showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Image.network(imageUrl),
              IconButton(
                icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ));
  }

  Future<bool?> _showConfirmationDialog(String title, String content,
      {bool isDestructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showJustificationDialog(
      String title, String actionText, TextEditingController controller) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration:InputDecoration(
              hintText: 'provide_justification'.tr(),
              border: OutlineInputBorder()),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr())),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar( SnackBar(
                    content: Text('justification_empty'.tr()),
                    backgroundColor: Colors.orange));
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    switch (status) {
      case 'Open':
        return {
          'color': Colors.orange,
          'icon': Icons.schedule,
          'label': 'open'.tr(), // ✅ localized
        };
      case 'In Progress':
        return {
          'color': Colors.blue,
          'icon': Icons.work,
          'label': 'in_progress'.tr(), // ✅ localized
        };
      case 'Resolved':
        return {
          'color': Colors.green,
          'icon': Icons.check_circle,
          'label': 'resolved'.tr(), // ✅ localized
        };
      case 'Rejected':
        return {
          'color': Colors.red,
          'icon': Icons.cancel,
          'label': 'rejected'.tr(), // ✅ localized
        };
      case 'Appealed':
        return {
          'color': Colors.orange,
          'icon': Icons.undo,
          'label': 'appealed'.tr(), // ✅ localized
        };
      default:
        return {
          'color': Colors.grey,
          'icon': Icons.info,
          'label': 'unknown'.tr(), // ✅ localized
        };
    }
  }

  IconData _getIconForEvent(String type) {
    switch (type) {
      case 'created':
        return Icons.report_problem;
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
      case 'created':
        return Colors.orange;
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