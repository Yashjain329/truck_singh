import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import '../../../admin/support_ticket_detail_page.dart';
import 'package:logistics_toolkit/features/admin/manage_users_page.dart';
import '../../../truck_documents/truck_documents_page.dart';


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
        _refreshController.refreshFailed();
      }
      return;
    }

    try {
      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          notifications = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
        _refreshController.refreshCompleted();
      }
    } catch (e) {
      debugPrint("❌ Error loading notifications: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('all_caught_up'.tr())),
      );
      return;
    }

    try {
      // Optimistic update: Update UI immediately
      setState(() {
        for (var notification in notifications) {
          notification['read'] = true;
        }
      });

      await supabase
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .inFilter('id', unreadIds);

    } catch (e) {
      debugPrint("❌ Error marking all as read: $e");
      // Revert on error (optional, but good practice)
      _loadNotifications();
    }
  }

  String _formatTimeAgo(String timeString) {
    try {
      final createdAt = DateTime.parse(timeString);
      final localCreatedAt = createdAt.toLocal();
      final difference = DateTime.now().difference(localCreatedAt);

      if (difference.inSeconds < 60) {
        return 'just_now'.tr();
      }
      if (difference.inMinutes < 60) {
        final minutes = difference.inMinutes;
        return "$minutes ${'minutes_ago'.tr().replaceAll('{0}', '').trim()}";
      }
      if (difference.inHours < 24) {
        final hours = difference.inHours;
        return "$hours ${'hours_ago'.tr().replaceAll('{0}', '').trim()}";
      }
      if (difference.inDays < 30) {
        final days = difference.inDays;
        return "$days ${'days_ago'.tr().replaceAll('{0}', '').trim()}";
      }
      if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return "$months ${'months_ago'.tr().replaceAll('{0}', '').trim()}";
      }
      final years = (difference.inDays / 365).floor();
      return "$years ${'years_ago'.tr().replaceAll('{0}', '').trim()}";

    } catch (e) {
      debugPrint("❌ Error formatting time: $e");
      return timeString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('notifications'.tr()),
        actions: [
          // Only one button now: Mark all as read
          if (notifications.any((n) => n['read'] != true))
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'mark_all_as_read'.tr(),
              onPressed: markAllAsRead,
            ),
        ],
      ),
      body: ptr.SmartRefresher(
        controller: _refreshController,
        onRefresh: _loadNotifications,
        enablePullDown: true,
        enablePullUp: false,
        header: const ptr.WaterDropHeader(),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : notifications.isEmpty
            ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_none,
                size: 70,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'no_notifications_found'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        )
            : ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            final bool isRead = notification['read'] == true;
            final timeAgo = _formatTimeAgo(notification['created_at']);

            return Card(
              elevation: isRead ? 1 : 3,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              // Style changes based on read status
              color: isRead
                  ? Colors.white
                  : Colors.blue.shade200,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isRead
                    ? BorderSide(color: Colors.grey.shade200)
                    : BorderSide.none,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: isRead
                      ? Colors.white
                      :  Colors.grey.shade200,
                  child: Icon(
                    Icons.notifications,
                    color: isRead ? Colors.grey : Colors.green,
                    size: 20,
                  ),
                ),
                title: Text(
                  notification['title'] ?? '',
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      notification['message'] ?? '',
                      style: TextStyle(
                        color: isRead ? Colors.grey.shade600 : Colors.black87,
                        fontSize: 14,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: isRead ? Colors.grey.shade400 : Colors.blueGrey,
                        fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                onTap: () => _handleNotificationTap(notification),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notification) async {
    // Mark as read locally immediately
    if (notification['read'] != true) {
      setState(() {
        notification['read'] = true;
      });
      try {
        await supabase
            .from('notifications')
            .update({'read': true})
            .eq('id', notification['id']);
      } catch (e) {
        debugPrint("❌ Error marking as read on tap: $e");
      }
    }

    final data = notification['data'] ?? notification['shipment_details'] ?? {};
    final String type = data['type'] ?? '';

    if (type == 'support_ticket' && data['ticket_id'] != null) {
      try {
        final ticketId = data['ticket_id'];
        final ticketResponse = await supabase
            .from('support_tickets')
            .select()
            .eq('id', ticketId)
            .single();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EnhancedSupportTicketDetailPage(ticket: ticketResponse),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error fetching ticket for navigation: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open ticket details: $e')),
          );
        }
      }
      return;
    }


    if (type == 'truck_document_upload' || type == 'truck_document_update') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const TruckDocumentsPage()));
      return;
    }
    if (type == 'account_status' || type == 'admin_log') {
      _showNotificationDetails(notification);
      return;
    }
    _showNotificationDetails(notification);
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (context) {
        final shipmentDetails = notification['shipment_details'] ?? {};
        return AlertDialog(
          title: Text(notification['title'] ?? 'details'.tr()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification['message'] ?? ''),
                const SizedBox(height: 8),
                if (shipmentDetails.isNotEmpty && shipmentDetails['type'] != 'support_ticket') ...[
                  const Divider(),
                  Text('Status: ${shipmentDetails['status']}'.tr()),
                  Text('ID: ${shipmentDetails['id']}'.tr()),
                  Text('From: ${shipmentDetails['from']}'.tr()),
                  Text('To: ${shipmentDetails['to']}'.tr()),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('close'.tr()),
            ),
          ],
        );
      },
    );
  }
}