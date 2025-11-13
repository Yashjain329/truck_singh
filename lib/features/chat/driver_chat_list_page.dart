import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/chat_service.dart';
import '../../services/driver/driver_chat_service.dart';
import 'chat_page.dart';
import 'package:easy_localization/easy_localization.dart';

class DriverChatListPage extends StatefulWidget {
  const DriverChatListPage({super.key});

  @override
  State<DriverChatListPage> createState() => _DriverChatListPageState();
}

class _DriverChatListPageState extends State<DriverChatListPage> {
  final DriverService _driverService = DriverService();
  final ChatService _chatService = ChatService();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadAllData();
  }

  Future<Map<String, dynamic>> _loadAllData() async {
    // 1. Get the driver's ID first (the reliable way)
    final driverId = await _chatService.getCurrentCustomUserId();

    // 2. Fetch data using that ID
    final results = await Future.wait([
      _driverService.getActiveShipmentsForDriver(driverId), // <-- Pass ID here
      _driverService.getAssociatedOwners(driverId), // <-- Pass ID here
    ]);

    return {
      'shipments': results[0] as List<Map<String, dynamic>>,
      'owners': results[1] as List<Map<String, dynamic>>,
      'driverId': driverId, // <-- Pass the ID to the UI
    };
  }

  Future<void> _refreshData() async {
    setState(() {
      _dataFuture = _loadAllData();
    });
  }

  // Generic navigation logic
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
        ).showSnackBar(SnackBar(content: Text('failed_open_chat $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                icon: Icon(Icons.local_shipping),
                text: 'shipment_chats'.tr(),
              ),
              Tab(icon: Icon(Icons.person), text: 'direct_chat'.tr()),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return RefreshIndicator(
                  onRefresh: _refreshData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(child: Text('no_messages'.tr())),
                    ),
                  ),
                );
              }

              final shipments =
                  snapshot.data!['shipments'] as List<Map<String, dynamic>>;
              // final owner = snapshot.data!['owner'] as Map<String, dynamic>?;
              final owners =
                  snapshot.data!['owners']
                      as List<Map<String, dynamic>>; // <-- CHANGED
              final driverId =
                  snapshot.data!['driverId'] as String?; // <-- Get the driverId
              return TabBarView(
                children: [
                  _buildShipmentList(shipments),
                  _buildDirectChatView(
                    owners,
                    driverId,
                  ), // <-- Call the function directly
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildShipmentList(List<Map<String, dynamic>> shipments) {
    if (shipments.isEmpty) {
      return Center(child: Text('no_active_shipments'.tr()));
    }
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
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
      ),
    );
  }

  Widget _buildDirectChatView(
    List<Map<String, dynamic>> owners,
    String? driverId,
  ) {
    if (owners.isEmpty) {
      return Center(child: Text('not_assigned_owner'.tr()));
    }

    if (driverId == null) {
      return Center(child: Text('could_not_identify_user'.tr()));
    }
    return ListView.builder(
      itemCount: owners.length,
      itemBuilder: (context, index) {
        final owner = owners[index];
        final ownerName = owner['name'] ?? 'Unknown';
        final ownerId = owner['custom_user_id'];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(
              ownerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Direct chat with $ownerName'),
            onTap: () => _navigateToChat(
              chatTitle: 'Chat with $ownerName',
              getRoomId: () =>
                  _chatService.getDriverOwnerChatRoom(driverId, ownerId),
            ),
          ),
        );
      },
    );
  }
}
