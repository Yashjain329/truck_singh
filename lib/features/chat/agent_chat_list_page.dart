import 'package:flutter/material.dart';
import '../../services/agent_chat_service.dart';
import '../../services/chat_service.dart';
import 'chat_page.dart';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';

class AgentChatListPage extends StatefulWidget {
  const AgentChatListPage({super.key});

  @override
  State<AgentChatListPage> createState() => _AgentChatListPageState();
}

class _AgentChatListPageState extends State<AgentChatListPage> {
  final AgentService _agentService = AgentService();
  final ChatService _chatService = ChatService();
  late Future<Map<String, List<Map<String, dynamic>>>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadAllData();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadAllData() async {
    final results = await Future.wait([
      _agentService.getActiveShipmentsForAgent(),
      _agentService.getRelatedDrivers(),
    ]);
    return {'shipments': results[0], 'drivers': results[1]};
  }

  Future<void> _refreshData() async {
    setState(() {
      _dataFuture = _loadAllData();
    });
  }

  // Updated: Generic navigation logic
  void _navigateToChat({
    required String chatTitle,
    required Future<String> Function() getRoomId,
  }) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('opening_chat'.tr())));

      final roomId = await getRoomId();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ChatPage(roomId: roomId, chatTitle: chatTitle),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('failed_open_chat $e'.tr())));
      }
    }
  }

  // New: Confirmation dialog before creating a room
  Future<void> _confirmAndNavigateToDriverChat(
    String driverId,
    String driverName,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('start_chat'.tr()),
        content: Text('confirm_start_chat $driverName?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('start'.tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final agentId = await _chatService.getCurrentCustomUserId();
      if (agentId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('user_not_identified'.tr())));
        return;
      }
      _navigateToChat(
        chatTitle: 'Chat with $driverName',
        getRoomId: () => _chatService.getDriverOwnerChatRoom(driverId, agentId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Two tabs: Shipments and Direct
      child: Scaffold(
        appBar: AppBar(
          title: Text('my_chats'.tr()),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          bottom: TabBar(
            indicatorColor: Theme.of(
              context,
            ).colorScheme.secondary, // Indicator color for selected tab
            labelColor: Theme.of(
              context,
            ).colorScheme.onPrimary, // Text color for selected tab
            unselectedLabelColor:
                Colors.white70, // Text color for unselected tab
            tabs: [
              Tab(
                icon: Icon(Icons.local_shipping),
                text: 'shipment_chats'.tr(),
              ),
              Tab(icon: Icon(Icons.person), text: 'direct_chats'.tr()),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _refreshData,
              child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  //  This error shows when you have network problem 
                  if (snapshot.hasError) {
                    return Center(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Check Internet conection\n',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: '${snapshot.error}'),
                          ],
                        ),
                      ),
                    );
                  }
                  // if (snapshot.hasError) {
                  // return Center(child: Text(' Check Internet conection \n${snapshot.error}'));
                  // }
                  if (!snapshot.hasData) {
                    return Center(child: Text('no_data_found'.tr()));
                  }

                  final shipments = snapshot.data!['shipments'] ?? [];
                  final drivers = snapshot.data!['drivers'] ?? [];

                  return TabBarView(
                    children: [
                      _buildShipmentList(shipments),
                      _buildDriverList(drivers),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget for the list of shipment chats
  Widget _buildShipmentList(List<Map<String, dynamic>> shipments) {
    if (shipments.isEmpty) {
      return Center(child: Text('no_active_shipments'.tr()));
    }
    return ListView.builder(
      itemCount: shipments.length,
      itemBuilder: (context, index) {
        final shipment = shipments[index];
        final shipmentId = shipment['shipment_id'] ?? 'N/A';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.group)),
            title: Text(
              shipmentId,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('group_chat_shipment'.tr()),
            onTap: () => _navigateToChat(
              chatTitle: '#$shipmentId',
              getRoomId: () => _chatService.getShipmentChatRoom(shipmentId),
            ),
          ),
        );
      },
    );
  }

  // Widget for the list of direct driver chats
  Widget _buildDriverList(List<Map<String, dynamic>> drivers) {
    if (drivers.isEmpty) {
      return Center(child: Text('no_drivers_added'.tr()));
    }
    return ListView.builder(
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        final driver = drivers[index];
        final driverName = driver['name'] ?? 'Unknown Driver';
        final driverId = driver['custom_user_id'];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(driverName.isNotEmpty ? driverName[0] : '?'),
            ),
            title: Text(
              driverName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('ID: $driverId'),
            onTap: () => _confirmAndNavigateToDriverChat(driverId, driverName),
          ),
        );
      },
    );
  }
}
