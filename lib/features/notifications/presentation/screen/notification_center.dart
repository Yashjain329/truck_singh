import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'package:logistics_toolkit/features/admin/support_ticket_detail_page.dart';
import 'package:logistics_toolkit/features/truck_documents/truck_documents_page.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({Key? key}) : super(key: key);

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = false;
  List<Map<String, dynamic>> notifications = [];
  final ptr.RefreshController _refreshController = ptr.RefreshController(
    initialRefresh: false,
  );

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      if (mounted) {
        setState(() {
          isLoading = false;
          notifications = [];
        });
      }
      _refreshController.refreshFailed();
      return;
    }

    try {
      final response = await supabase
          .from('notifications')
          .select('*') // FIXED
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          notifications = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      }

      _refreshController.refreshCompleted();
    } catch (e) {
      debugPrint("❌ Error loading notifications: $e");

      if (mounted) setState(() => isLoading = false);
      _refreshController.refreshFailed();
    }
  }

  Future<void> markAllAsRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final unreadIds = notifications
        .where((n) => n['read'] != true)
        .map((n) => n['id'] as String)
        .toList();

    if (unreadIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('all_caught_up'.tr())));
      return;
    }

    try {
      setState(() {
        for (var n in notifications) {
          n['read'] = true;
        }
      });

      await supabase
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .inFilter('id', unreadIds);
    } catch (e) {
      debugPrint("❌ Error marking all as read: $e");
      _loadNotifications();
    }
  }

  String _formatTimeAgo(String timeString) {
    try {
      final createdAt = DateTime.parse(timeString).toLocal();
      final diff = DateTime.now().difference(createdAt);

      if (diff.inSeconds < 60) return 'just_now'.tr();
      if (diff.inMinutes < 60) return '${diff.inMinutes} ${'minutes_ago'.tr()}';
      if (diff.inHours < 24) return '${diff.inHours} ${'hours_ago'.tr()}';
      if (diff.inDays < 30) return '${diff.inDays} ${'days_ago'.tr()}';

      if (diff.inDays < 365) {
        final m = (diff.inDays / 30).floor();
        return '$m ${'months_ago'.tr()}';
      }

      final y = (diff.inDays / 365).floor();
      return '$y ${'years_ago'.tr()}';
    } catch (_) {
      return timeString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('notifications'.tr()),
        actions: [
          if (notifications.any((n) => n['read'] != true))
            IconButton(
              tooltip: 'mark_all_as_read'.tr(),
              icon: const Icon(Icons.done_all),
              onPressed: markAllAsRead,
            ),
        ],
      ),
      body: ptr.SmartRefresher(
        controller: _refreshController,
        onRefresh: _loadNotifications,
        enablePullDown: true,
        header: const ptr.WaterDropHeader(),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none, size: 70, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'no_notifications_found'.tr(),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final n = notifications[index];
        final isRead = n['read'] == true;

        return Card(
          elevation: isRead ? 1 : 3,
          color: isRead ? Colors.white : Colors.blue.shade200,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isRead
                ? BorderSide(color: Colors.grey.shade300)
                : BorderSide.none,
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isRead ? Colors.white : Colors.grey.shade200,
              child: Icon(
                Icons.notifications,
                color: isRead ? Colors.grey : Colors.green,
              ),
            ),
            title: Text(
              n['title'] ?? '',
              style: TextStyle(
                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  n['message'] ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isRead ? Colors.grey.shade600 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTimeAgo(n['created_at']),
                  style: TextStyle(
                    fontSize: 12,
                    color: isRead ? Colors.grey.shade400 : Colors.blueGrey,
                  ),
                ),
              ],
            ),
            onTap: () => _handleNotificationTap(n),
          ),
        );
      },
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notification) async {
    if (notification['read'] != true) {
      setState(() => notification['read'] = true);

      try {
        await supabase
            .from('notifications')
            .update({'read': true})
            .eq('id', notification['id']);
      } catch (e) {
        debugPrint("❌ Error marking read: $e");
      }
    }

    final dynamic data =
        notification['data'] ?? notification['shipment_details'] ?? {};
    final String type = data is Map ? (data['type'] ?? '') : '';

    if (type == 'support_ticket' && data is Map && data['ticket_id'] != null) {
      try {
        final ticket = await supabase
            .from('support_tickets')
            .select() // FIXED
            .eq('id', data['ticket_id'])
            .single();

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                EnhancedSupportTicketDetailPage(ticket: ticket),
          ),
        );
      } catch (e) {
        debugPrint("❌ Error opening ticket: $e");

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('error_opening_ticket'.tr())));
        }
      }
      return;
    }

    if (type == 'truck_document_upload' || type == 'truck_document_update') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TruckDocumentsPage()),
      );
      return;
    }

    _showNotificationDetails(notification);
  }

  void _showNotificationDetails(Map<String, dynamic> n) {
    final shipmentDetails = (n['shipment_details'] is Map)
        ? n['shipment_details']
        : {};

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(n['title'] ?? 'details'.tr()),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n['message'] ?? ''),
                const SizedBox(height: 12),
                if (shipmentDetails.isNotEmpty) ...[
                  const Divider(),
                  Text("Status: ${shipmentDetails['status']}"),
                  Text("ID: ${shipmentDetails['id']}"),
                  Text("From: ${shipmentDetails['from']}"),
                  Text("To: ${shipmentDetails['to']}"),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('close'.tr()),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }
}
