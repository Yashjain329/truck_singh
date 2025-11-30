import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:logistics_toolkit/features/tracking/driver_route_tracking.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;

class DriverStatusChanger extends StatefulWidget {
  final String driverId;

  const DriverStatusChanger({required this.driverId, super.key});

  @override
  State<DriverStatusChanger> createState() => _DriverStatusChangerState();
}

class _DriverStatusChangerState extends State<DriverStatusChanger> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? currentShipment;
  bool isLoading = false;

  final refreshController = ptr.RefreshController();

  late final statusFlow = [
    _status('accepted', Icons.check_circle, Colors.blue),
    _status('en_route_pickup', Icons.directions_car, Colors.purple),
    _status('arrived_pickup', Icons.location_on, Colors.cyan),
    _status('loading', Icons.upload, Colors.amber),
    _status('Picked Up', Icons.done, Colors.green),
    _status('in_transit', Icons.local_shipping, Colors.indigo),
    _status('arrived_drop', Icons.place, Colors.teal),
    _status('unloading', Icons.download, Colors.deepOrange),
    _status('delivered', Icons.done_all, Colors.green),
    _status('completed', Icons.verified, Colors.green),
  ];

  Map<String, dynamic> _status(String key, IconData icon, Color color) => {
    'status': key.tr(),
    'icon': icon,
    'color': color,
    'description': "${key}_desc".tr(),
  };

  @override
  void initState() {
    super.initState();
    loadShipment();
  }

  Future<void> loadShipment() async {
    setState(() => isLoading = true);

    try {
      currentShipment = await supabase
          .from('shipment')
          .select()
          .eq('assigned_driver', widget.driverId)
          .neq('booking_status', 'Completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } finally {
      setState(() => isLoading = false);
      refreshController.refreshCompleted();
    }
  }

  Future<void> updateStatus(String status) async {
    if (currentShipment == null) return;

    setState(() => isLoading = true);

    try {
      await supabase
          .from('shipment')
          .update({
            'booking_status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('shipment_id', currentShipment!['shipment_id']);

      if (status.toLowerCase() == 'completed') {
        currentShipment = null;
      } else {
        await loadShipment();
      }

      _toast("Status updated: $status");
    } catch (e) {
      _toast("Error: $e", error: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(error ? Icons.error : Icons.check, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int get currentStatusIndex => currentShipment == null
      ? -1
      : statusFlow.indexWhere(
          (s) => s['status'] == currentShipment!['booking_status'],
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("my_current_delivery".tr())),
      bottomNavigationBar: currentShipment == null ? null : _trackingButton(),
      body: ptr.SmartRefresher(
        controller: refreshController,
        onRefresh: loadShipment,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading && currentShipment == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (currentShipment == null) {
      return _emptyState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        _progressBar(),
        _statusCard(),
        const SizedBox(height: 15),
        _shipmentDetails(),
        _nextStatusButton(),
      ],
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Icon(Icons.assignment_turned_in, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            "no_active_shipment".tr(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "no_shipments_assigned".tr(),
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    ),
  );

  Widget _progressBar() {
    if (currentStatusIndex == -1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          LinearProgressIndicator(
            minHeight: 6,
            value: (currentStatusIndex + 1) / statusFlow.length,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation(
              statusFlow[currentStatusIndex]['color'],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "${currentStatusIndex + 1}/${statusFlow.length} steps",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final status = statusFlow[currentStatusIndex];
    return _card(
      color: status['color'],
      child: Column(
        children: [
          Icon(status['icon'], size: 50, color: Colors.white),
          const SizedBox(height: 10),
          Text(
            "current_status".tr(),
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            currentShipment!['booking_status'],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status['description'],
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _shipmentDetails() {
    final d = currentShipment!;
    final date = DateTime.parse(d['delivery_date']);
    final urgent = date.difference(DateTime.now()).inDays <= 1;

    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            if (urgent)
              Align(
                alignment: Alignment.topRight,
                child: Chip(
                  label: Text("urgent".tr()),
                  backgroundColor: Colors.red,
                ),
              ),
            ..._infoItems(d, date),
          ],
        ),
      ),
    );
  }

  List<Widget> _infoItems(Map<String, dynamic> d, DateTime date) => [
    _item(
      Icons.confirmation_number,
      'shipment_id',
      d['shipment_id'].toString(),
    ),
    _item(Icons.upload, 'pickup_location', d['pickup']),
    _item(Icons.download, 'drop_location', d['drop']),
    _item(Icons.inventory_2, 'item', d['shipping_item']),
    _item(Icons.category, 'material', d['material_inside']),
    _item(Icons.monitor_weight, 'weight', "${d['weight']} kg"),
    _item(Icons.local_shipping, 'truck_type', d['truck_type']),
    _item(
      Icons.calendar_today,
      'delivery_date',
      DateFormat('MMM dd, yyyy').format(date),
    ),
    if (d['notes'] != null && d['notes'].isNotEmpty)
      _item(Icons.note_alt, 'special_notes', d['notes']),
  ];

  Widget _item(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon),
    title: Text(label.tr()),
    subtitle: Text(value),
  );

  Widget _trackingButton() => BottomAppBar(
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: ElevatedButton.icon(
        icon: const Icon(Icons.map_outlined),
        label: Text("TRACK"),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverRouteTrackingPage(driverId: widget.driverId),
          ),
        ),
      ),
    ),
  );

  Widget _nextStatusButton() {
    if (currentStatusIndex >= statusFlow.length - 1)
      return const SizedBox.shrink();
    final next = statusFlow[currentStatusIndex + 1];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton.icon(
        icon: Icon(next['icon']),
        label: Text("Mark as ${next['status']}"),
        style: ElevatedButton.styleFrom(backgroundColor: next['color']),
        onPressed: isLoading ? null : () => updateStatus(next['status']),
      ),
    );
  }

  Widget _card({required Widget child, Color? color}) => Container(
    margin: const EdgeInsets.all(20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}
