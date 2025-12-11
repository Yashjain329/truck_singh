import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'package:logistics_toolkit/features/admin/support_ticket_detail_page.dart';
import 'package:logistics_toolkit/features/truck_documents/truck_documents_page.dart';
import '../../../trips/shipment_details.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({Key? key}) : super(key: key);

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final supabase = Supabase.instance.client;
  final ptr.RefreshController _refreshController = ptr.RefreshController(
    initialRefresh: false,
  );

  bool isLoading = false;
  List<Map<String, dynamic>> notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  /// Fetches notifications from Supabase for the current user.
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
          .select('*')
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

  /// Marks all unread notifications as read.
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
      // Optimistic UI update
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
      // Revert or reload on error
      _loadNotifications();
    }
  }

  /// Formats the time difference into a user-friendly string (e.g., "5 minutes ago").
  /// Handles singular/plural logic and removes {0} placeholders.
  String _formatTimeAgo(String timeString) {
    try {
      final createdAt = DateTime.parse(timeString).toLocal();
      final diff = DateTime.now().difference(createdAt);

      if (diff.inSeconds < 60) return 'just_now'.tr();

      // Helper to format string and remove '(s)' for singular values
      String format(String key, int value) {
        return key
            .tr(args: [value.toString()])
            .replaceAll('{0}', value.toString())
            .replaceAll('(s)', value == 1 ? '' : 's');
      }

      if (diff.inMinutes < 60) return format('minutes_ago', diff.inMinutes);
      if (diff.inHours < 24) return format('hours_ago', diff.inHours);
      if (diff.inDays < 30) return format('days_ago', diff.inDays);

      if (diff.inDays < 365) {
        final m = (diff.inDays / 30).floor();
        return format('months_ago', m);
      }

      final y = (diff.inDays / 365).floor();
      return format('years_ago', y);
    } catch (_) {
      return timeString;
    }
  }

  /// Handles tap events on a notification card.
  /// Identifies the notification type and navigates to the appropriate screen.
  void _handleNotificationTap(Map<String, dynamic> notification) async {
    // 1. Mark notification as read immediately
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

    // 2. Extract Data & Type
    String type = (notification['type'] ?? '').toString().toLowerCase();
    final dynamic data = notification['data'];

    // Fallback: Check inside 'data' if top-level type is missing
    if ((type.isEmpty || type == 'null') && data is Map) {
      type = (data['type'] ?? '').toString().toLowerCase();
    }

    // 3. Extract Source ID (Robust Strategy)
    String? sourceId = notification['source_id']?.toString();

    // Helper to check if an ID is valid
    bool isInvalidId(String? id) => id == null || id.isEmpty || id.toLowerCase() == 'null';

    if (isInvalidId(sourceId)) {
      // Strategy A: Check 'data' object
      if (data is Map) {
        sourceId = data['shipment_id']?.toString() ??
            data['id']?.toString() ??
            data['source_id']?.toString();
      }

      // Strategy B: Check 'shipment_details' map
      if (isInvalidId(sourceId) && notification['shipment_details'] is Map) {
        final details = notification['shipment_details'];
        sourceId = details['shipment_id']?.toString() ??
            details['id']?.toString();
      }

      // Strategy C: Regex fallback on message text
      if (isInvalidId(sourceId)) {
        final message = (notification['message'] ?? '').toString();
        final regex = RegExp(r'(SHP-[\w\d-]+)');
        final match = regex.firstMatch(message);
        if (match != null) {
          sourceId = match.group(0);
        }
      }
    }

    // Auto-correct type if we successfully found a Shipment ID
    if (sourceId != null && sourceId.startsWith('SHP-')) {
      type = 'shipment';
    }

    // 4. Navigate based on Type

    // --- Case: Support Ticket ---
    if (type == 'support_ticket' && data is Map && data['ticket_id'] != null) {
      _navigateToSupportTicket(data['ticket_id']);
      return;
    }

    // --- Case: Truck Documents ---
    if (type.contains('truck_document')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TruckDocumentsPage()),
      );
      return;
    }

    // --- Case: Shipment Details ---
    if (type.contains('shipment') && !isInvalidId(sourceId)) {
      _navigateToShipment(sourceId!);
      return;
    }

    // Default: Show simple details dialog if no navigation rule matched
    _showNotificationDetails(notification);
  }

  Future<void> _navigateToSupportTicket(String ticketId) async {
    try {
      final ticket = await supabase
          .from('support_tickets')
          .select()
          .eq('id', ticketId)
          .single();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EnhancedSupportTicketDetailPage(ticket: ticket),
        ),
      );
    } catch (e) {
      debugPrint("❌ Error opening ticket: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_opening_ticket'.tr())),
        );
      }
    }
  }

  Future<void> _navigateToShipment(String shipmentId) async {
    try {
      final shipmentData = await supabase
          .from('shipment')
          .select()
          .eq('shipment_id', shipmentId)
          .maybeSingle();

      if (!mounted) return;

      if (shipmentData != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ShipmentDetailsPage(shipment: shipmentData),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('shipment_not_found'.tr())),
        );
      }
    } catch (e) {
      debugPrint("❌ Error opening shipment: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_opening_shipment'.tr())),
        );
      }
    }
  }

  /// Displays a simple dialog with notification details when no specific action exists.
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
              backgroundColor: isRead ? Colors.grey.shade200 : Colors.grey.shade200,
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
                  color: isRead ? Colors.black : Colors.white
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
                    color:Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTimeAgo(n['created_at']),
                  style: TextStyle(
                    fontSize: 12,
                    color: isRead ? Colors.black : Colors.blueGrey,
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
}