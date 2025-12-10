import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../services/chat_service.dart';
import '../../services/driver/driver_chat_service.dart';
import 'chat_page.dart';

class DriverChatListPage extends StatefulWidget {
  const DriverChatListPage({super.key});

  @override
  State<DriverChatListPage> createState() => _DriverChatListPageState();
}

class _DriverChatListPageState extends State<DriverChatListPage> {
  final _driverService = DriverService();
  final _chat = ChatService();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final driverId = await _chat.getCurrentCustomUserId();
    final results = await Future.wait([
      _driverService.getActiveShipmentsForDriver(driverId),
      _driverService.getAssociatedOwners(driverId),
    ]);

    return {
      "shipments": results[0],
      "owners": results[1],
      "driverId": driverId,
    };
  }

  Future<void> _refresh() async =>
      setState(() => _future = _loadData());

  Future<void> _openChat(String title, Future<String> Function() room) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("opening_chat".tr())),
      );

      final id = await room();

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(roomId: id, chatTitle: title),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("failed_open_chat $e".tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('my_chats'.tr()),
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 1,

          // -------- Flutter 3.38 Material 3 TabBar Update --------
          bottom: TabBar(
            indicatorColor: scheme.primary,
            dividerHeight: 0,
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,

            tabs: [
              Tab(
                icon: Icon(Icons.local_shipping, color: scheme.primary),
                text: "shipment_chats".tr(),
              ),
              Tab(
                icon: Icon(Icons.person, color: scheme.primary),
                text: "direct_chat".tr(),
              ),
            ],
          ),
        ),

        body: RefreshIndicator(
          onRefresh: _refresh,
          color: scheme.primary,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text("Error: ${snap.error}"),
                );
              }
              if (!snap.hasData) {
                return Center(child: Text("no_messages".tr()));
              }

              final data = snap.data!;

              return TabBarView(
                children: [
                  _shipmentList(data["shipments"]),
                  _ownerList(data["owners"], data["driverId"]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------- SHIPMENT CHAT LIST ----------------
  Widget _shipmentList(List<Map<String, dynamic>> shipments) {
    if (shipments.isEmpty) {
      return Center(child: Text("no_active_shipments".tr()));
    }

    return ListView.builder(
      itemCount: shipments.length,
      itemBuilder: (_, i) {
        final id = shipments[i]["shipment_id"] ?? "N/A";

        return _card(
          title: id,
          subtitle: "group_chat_shipment".tr(),
          icon: Icons.group,
          action: () => _openChat(
            "#$id",
                () => _chat.getShipmentChatRoom(id),
          ),
        );
      },
    );
  }

  // ---------------- DIRECT OWNER CHAT LIST ----------------
  Widget _ownerList(List<Map<String, dynamic>> owners, String? driverId) {
    if (owners.isEmpty || driverId == null) {
      return Center(child: Text("not_assigned_owner".tr()));
    }

    return ListView.builder(
      itemCount: owners.length,
      itemBuilder: (_, i) {
        final owner = owners[i];
        final name = owner["name"] ?? "Unknown";
        final id = owner["custom_user_id"];

        return _card(
          title: name,
          subtitle: "Direct chat with $name",
          icon: Icons.person,
          action: () => _openChat(
            "Chat with $name",
                () => _chat.getDriverOwnerChatRoom(driverId, id),
          ),
        );
      },
    );
  }

  // ---------------- CARD UI ----------------
  Widget _card({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback action,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      surfaceTintColor: scheme.surface,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.primary),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        onTap: action,
      ),
    );
  }
}
