import 'package:flutter/material.dart';
import 'package:logistics_toolkit/features/mydrivers/mydriver.dart';
import 'package:logistics_toolkit/services/shipment_service.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../mytruck/mytrucks.dart';

class AllLoadsPage extends StatefulWidget {
  const AllLoadsPage({Key? key}) : super(key: key);

  @override
  State<AllLoadsPage> createState() => _AllLoadsPageState();
}

class _AllLoadsPageState extends State<AllLoadsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allShipments = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchShipments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchShipments() async {
    setState(() => _loading = true);
    try {
      final shipments = await ShipmentService.getAllMyShipments();
      if (mounted) {
        setState(() {
          _allShipments = shipments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('error_fetching_shipments $e'.tr())));
      }
    }
  }

  Future<void> assignDriverToShipment(
      String shipmentId,
      String driverUserId,
      ) async {
    try {
      await ShipmentService.assignDriver(
        shipmentId: shipmentId,
        driverUserId: driverUserId,
      );
      await _fetchShipments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('driver_assigned_success'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('error_assigning_driver $e'.tr())));
      }
    }
  }

  // New: Logic to handle truck assignment
  Future<void> assignTruckToShipment(
      String shipmentId,
      String truckNumber,
      ) async {
    try {
      await ShipmentService.assignTruck(
        shipmentId: shipmentId,
        truckNumber: truckNumber,
      );
      await _fetchShipments(); // Refresh the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('truck_assigned_success'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('error_assigning_truck: $e'.tr())));
      }
    }
  }

  void navigateToDriverSelection(String shipmentId) async {
    final selectedDriverId = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MyDriverPage(isSelectionMode: true, shipmentId: shipmentId),
      ),
    );

    if (selectedDriverId != null) {
      await assignDriverToShipment(shipmentId, selectedDriverId);
    }
  }

  void navigateToTruckSelection(String shipmentId) async {
    final selectedTruck = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const Mytrucks(selectable: true),
      ),
    );

    if (selectedTruck != null) {
      final truckNumber = selectedTruck['truck_number'];
      if (truckNumber != null) {
        await assignTruckToShipment(shipmentId, truckNumber);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'my_shipments'.tr(),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'search_hint'.tr(),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: Colors.tealAccent,
                //unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
                tabs: [
                  Tab(text: 'pending'.tr()),
                  Tab(text: 'assigned'.tr()),
                ],
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
          controller: _tabController,
          children: [
            RefreshIndicator(
              onRefresh: _fetchShipments,
              child: _buildShipmentList('pending'),
            ),
            _buildShipmentList('assigned'),
          ],
        ),
      ),
    );
  }

  Widget _buildShipmentList(String status) {
    List<Map<String, dynamic>> shipments = [];

    if (status == 'pending') {
      shipments = _allShipments
          .where((s) => s['assigned_driver'] == null && s['booking_status'] != 'Completed')
          .toList();
    } else if (status == 'assigned') {
      shipments = _allShipments
          .where((s) => s['assigned_driver'] != null && s['booking_status'] != 'Completed')
          .toList();
    } else {
      shipments = [];
    }


    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      shipments = shipments.where((s) {
        final id = (s['shipment_id'] ?? '').toString().toLowerCase();
        final pickup = (s['pickup'] ?? '').toString().toLowerCase();
        final drop = (s['drop'] ?? '').toString().toLowerCase();
        return id.contains(q) || pickup.contains(q) || drop.contains(q);
      }).toList();
    }

    if (shipments.isEmpty) {
      return Center(child: Text("No $status shipments found."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: shipments.length,
      itemBuilder: (context, index) {
        return _buildTripCard(shipments[index], status);
      },
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip, String status) {
    Color headerColor;
    String? headerText;

    final shipperName = trip['shipper_id'] ?? 'Unknown Shipper';

    switch (status) {
      case 'pending':
        headerColor = Colors.orange.withValues(alpha: 0.15);
        headerText = 'pending Assignment';
        break;
      case 'assigned':
        headerColor = Colors.blue.withValues(alpha: 0.15);
        headerText = 'Driver assigned';
        break;
      default:
        headerColor = Colors.grey.withValues(alpha: 0.15);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip['shipment_id'] ?? 'No ID',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,

                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Shipper: $shipperName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      if (trip['assigned_driver'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Driver: ${trip['assigned_driver']}',
                          style:  TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).textTheme.titleLarge?.color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (headerText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      headerText,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildLocationRow(
                  Icons.radio_button_checked,
                  'pickup'.tr(),
                  trip['pickup'],
                  Colors.green,
                ),
                const SizedBox(height: 8),
                _buildLocationRow(
                  Icons.location_on,
                  'drop'.tr(),
                  trip['drop'],
                  Colors.red,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        Icons.inventory_2_outlined,
                        '${trip['shipping_item']} • ${trip['weight']?.toString().trim().isNotEmpty == true ? '${trip['weight']} kg' : (trip['unit']?.toString().trim().isNotEmpty == true ? '${trip['unit']} Unit' : 'N/A')}',
                      ),
                    ),

                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoChip(
                        Icons.schedule,
                        '${trip['delivery_date']} • ${trip['pickup_time']}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        Icons.local_offer,
                        trip['material_inside'] ?? '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoChip(
                        Icons.fire_truck,
                        trip['truck_type'] ?? 'N/A',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildActionButtons(trip, status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> trip, String status) {
    final shipmentId = trip['shipment_id'];
    final bool isTruckAssigned = trip['assigned_truck'] != null;

    if (!isTruckAssigned) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => navigateToTruckSelection(shipmentId),
          icon: const Icon(Icons.add_road),
          label:Text('Assign Truck'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            //foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => navigateToDriverSelection(shipmentId),
            icon: Icon(
              trip['assigned_driver'] == null
                  ? Icons.person_add
                  : Icons.swap_horiz,
            ),
            label: Text(
                trip['assigned_driver'] == null
                    ? 'assign_driver'.tr()
                    : 'change_driver'.tr()
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: trip['assigned_driver'] == null
                  ? Colors.orange
                  : Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationRow(
      IconData icon,
      String label,
      String location,
      Color color,
      ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                location,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  //color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}