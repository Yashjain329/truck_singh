import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../services/agent_chat_service.dart';
import '../../services/chat_service.dart';
import 'chat_page.dart';

class AgentChatListPage extends StatefulWidget {
  const AgentChatListPage({super.key});

  @override
  State<AgentChatListPage> createState() => _AgentChatListPageState();
}

class _AgentChatListPageState extends State<AgentChatListPage> {
  final _agent = AgentService();
  final _chat = ChatService();
  late Future<Map<String, List<Map<String, dynamic>>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadData() async {
    final data = await Future.wait([
      _agent.getActiveShipmentsForAgent(),
      _agent.getRelatedDrivers(),
    ]);
    return {"shipments": data[0], "drivers": data[1]};
  }

  Future<void> _refresh() async => setState(() => _future = _loadData());

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

  Future<void> _confirmDriverChat(String driverId, String name) async {
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
        () => _chat.getDriverOwnerChatRoom(driverId, agentId),
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
          title: Text("my_chats".tr()),
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
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
                text: "direct_chats".tr(),
              ),
            ],
          ),
        ),

        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text("Error: ${snap.error}"));
              }
              if (!snap.hasData) {
                return Center(child: Text("no_data_found".tr()));
              }

              final data = snap.data!;
              return TabBarView(
                children: [
                  _shipmentList(data["shipments"] ?? []),
                  _driverList(data["drivers"] ?? []),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _shipmentList(List shipments) {
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
          action: () => _openChat("#$id", () => _chat.getShipmentChatRoom(id)),
        );
      },
    );
  }

  Widget _driverList(List drivers) {
    if (drivers.isEmpty) {
      return Center(child: Text("no_drivers_added".tr()));
    }

    return ListView.builder(
      itemCount: drivers.length,
      itemBuilder: (_, i) {
        final d = drivers[i];
        final name = d["name"] ?? "Unknown";

        return _card(
          title: name,
          subtitle: "ID: ${d['custom_user_id']}",
          icon: Icons.person,
          action: () => _confirmDriverChat(d["custom_user_id"], name),
        );
      },
    );
  }

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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        onTap: action,
      ),
    );
  }
}
