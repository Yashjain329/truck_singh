import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({Key? key}) : super(key: key);

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final supabase = Supabase.instance.client;
  bool showReadNotifications = false;
  bool isLoading = false;
  List<Map<String, dynamic>> notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => isLoading = true);

    final response = await supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        notifications = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    }
  }

  void toggleShowReadNotifications() {
    setState(() {
      showReadNotifications = !showReadNotifications;
    });
  }

  Future<void> markAllAsRead() async {
    await supabase.from('notifications').update({'is_read': true}).neq('is_read', true);
    await _loadNotifications();
  }

  String _formatTimeAgo(DateTime time) {
    final difference = DateTime.now().difference(time);

    if (difference.inMinutes < 1) return 'just_now'.tr();
    if (difference.inHours < 1) {
      return tr("minutes_ago", args: ['${difference.inMinutes}']);
    }
    if (difference.inHours < 24) {
      return tr("hours_ago", args: ['${difference.inHours}']);
    }
    if (difference.inDays < 30) {
      return tr("days_ago", args: ['${difference.inDays}']);
    }
    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return tr("months_ago", args: ['${months}']);
    }
    final years = (difference.inDays / 365).floor();
    return tr("years_ago", args: ['${years}']);
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotifications = showReadNotifications
        ? notifications
        : notifications.where((n) => n['is_read'] == false).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('notifications'.tr()),
        actions: [
          IconButton(
            icon: Icon(showReadNotifications ? Icons.visibility_off : Icons.visibility),
            tooltip: showReadNotifications ? 'hide_read'.tr() : 'show_all'.tr(),
            onPressed: toggleShowReadNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'mark_all_as_read'.tr(),
            onPressed: markAllAsRead,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'refresh'.tr(),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredNotifications.isEmpty
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_off, size: 70, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              showReadNotifications
                  ? 'no_notifications_found'.tr()
                  : 'all_caught_up'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: toggleShowReadNotifications,
              child: Text('show_read_notifications'.tr()),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: filteredNotifications.length,
        itemBuilder: (context, index) {
          final notification = filteredNotifications[index];
          final isRead = notification['is_read'] ?? false;
          final timestamp = DateTime.parse(notification['created_at']);
          final timeAgo = _formatTimeAgo(timestamp);

          return Card(
            color: isRead
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.notifications),
              title: Text(notification['title'] ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification['message'] ?? ''),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              trailing: isRead
                  ? null
                  : IconButton(
                icon: const Icon(Icons.mark_email_read),
                onPressed: () async {
                  await supabase
                      .from('notifications')
                      .update({'is_read': true})
                      .eq('id', notification['id']);
                  _loadNotifications();
                },
              ),
              onTap: () => _showNotificationDetails(notification),
            ),
          );
        },
      ),
    );
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (context) {
        final shipmentDetails = notification['shipment_details'] ?? {};
        return AlertDialog(
          title: Text(notification['title'] ?? 'details'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notification['message'] ?? ''),
              const SizedBox(height: 8),
              if (shipmentDetails.isNotEmpty) ...[
                const Divider(),
                Text('Status: ${shipmentDetails['status']}'.tr()),
                Text('ID: ${shipmentDetails['id']}'.tr()),
                Text('From: ${shipmentDetails['from']}'.tr()),
                Text('To: ${shipmentDetails['to']}'.tr()),
              ],
            ],
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