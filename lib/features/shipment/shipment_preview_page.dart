import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShipmentPreviewPage extends StatefulWidget {
  final String shipmentId;

  const ShipmentPreviewPage({Key? key, required this.shipmentId})
    : super(key: key);

  @override
  State<ShipmentPreviewPage> createState() => _ShipmentPreviewPageState();
}

class _ShipmentPreviewPageState extends State<ShipmentPreviewPage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? shipmentData;
  bool _loading = true;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _fetchShipmentDetails();
  }

  void _initAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchShipmentDetails() async {
    try {
      final res = await Supabase.instance.client
          .from('shipment')
          .select()
          .eq('shipment_id', widget.shipmentId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          shipmentData = res;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching shipment: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _iconForTitle(String title) {
    switch (title) {
      case 'Shipment Overview':
        return Icons.local_shipping;
      case 'Item Details':
        return Icons.inventory;
      case 'Schedule':
        return Icons.schedule;
      case 'Status':
        return Icons.info_outline;
      default:
        return Icons.info;
    }
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: highlight ? Colors.blue.shade800 : null,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 10,
                spreadRadius: 2,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade200,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _iconForTitle(title),
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: children),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShipmentInfo() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    if (shipmentData == null) {
      return Center(
        child: Text(
          "noDataAvailable".tr(),
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    final status = shipmentData!['booking_status'] ?? 'Unknown';
    final statusColor = status == 'Confirmed' ? Colors.green : Colors.orange;

    return Column(
      children: [
        FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 50),
                const SizedBox(height: 12),
                Text(
                  "shipmentCreatedSuccess".tr(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "ID: ${shipmentData!['shipment_id']}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Overview Card
        _buildInfoCard("shipmentOverview".tr(), [
          _buildInfoRow(
            Icons.tag,
            "shipmentId".tr(),
            shipmentData!['shipment_id'],
            highlight: true,
          ),
          _buildInfoRow(
            Icons.person,
            "shipperId".tr(),
            shipmentData!['shipper_id'],
          ),
          _buildInfoRow(
            Icons.my_location,
            "pickup".tr(),
            shipmentData!['pickup'],
          ),
          _buildInfoRow(
            Icons.location_on,
            "destination".tr(),
            shipmentData!['drop'],
          ),
        ]),

        // Item Details
        _buildInfoCard("itemDetails".tr(), [
          _buildInfoRow(
            Icons.category,
            "item".tr(),
            shipmentData!['shipping_item'],
          ),
          if (shipmentData!['weight'] != null &&
              shipmentData!['weight'].toString().trim().isNotEmpty)
            _buildInfoRow(
              Icons.monitor_weight,
              "weight".tr(),
              "${shipmentData!['weight']} Ton",
            ),
          if (shipmentData!['unit'] != null &&
              shipmentData!['unit'].toString().trim().isNotEmpty)
            _buildInfoRow(
              Icons.format_list_numbered,
              "quantity".tr(),
              shipmentData!['unit'].toString(),
            ),
          _buildInfoRow(
            Icons.precision_manufacturing,
            "material".tr(),
            shipmentData!['material_inside'],
          ),
          _buildInfoRow(
            Icons.local_shipping,
            "truckType".tr(),
            shipmentData!['truck_type'],
          ),
        ]),

        // Schedule
        _buildInfoCard("schedule".tr(), [
          _buildInfoRow(
            Icons.access_time,
            "pickupTime".tr(),
            shipmentData!['pickup_time'],
          ),
          _buildInfoRow(
            Icons.calendar_today,
            "deliveryDate".tr(),
            DateFormat(
              'MMM dd, yyyy',
            ).format(DateTime.parse(shipmentData!['delivery_date'])),
          ),
          if ((shipmentData!['notes'] ?? '').toString().isNotEmpty)
            _buildInfoRow(Icons.note_alt, "notes".tr(), shipmentData!['notes']),
        ]),

        // Status
        _buildInfoCard("Status", [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Text(
                  "status:".tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      status == 'Confirmed'
                          ? Icons.check_circle
                          : Icons.pending,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("shipmentPreview".tr())),
      body: _loading
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  "loadingShipmentDetails".tr(),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildShipmentInfo(),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        },
                        icon: const Icon(Icons.home),
                        label: Text("backToHome".tr()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade600,
                          side: BorderSide(color: Colors.orange.shade600),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
