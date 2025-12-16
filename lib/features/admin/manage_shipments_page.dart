import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:logistics_toolkit/features/trips/shipment_details.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class ManageShipmentsPage extends StatefulWidget {
  const ManageShipmentsPage({super.key});

  @override
  State<ManageShipmentsPage> createState() => _ManageShipmentsPageState();
}

class _ManageShipmentsPageState extends State<ManageShipmentsPage>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _shipmentsFuture;

  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Accepted',
    'En Route Pickup',
    'Arrived Pickup',
    'Loading',
    'Picked Up',
    'In Transit',
    'Arrived_drop',
    'Unloading',
    'Delivered',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _shipmentsFuture = _fetchShipments();
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      _refresh();
    }
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {}); // rebuild to update all .tr() translations when locale changes
  }

  // ---------------- Dialog box to edit the shipment pickup and drop location and delivery date.--------------------
  // ----------------- only works if the shipment status is---------------------------
  void _showEditDilog(Map<String, dynamic> shipment) {
    final pickupController = TextEditingController(text: shipment['pickup']);
    final dropController = TextEditingController(text: shipment['drop']);
    final dropdateController = TextEditingController(
      text: shipment['delivery_date'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("edit_shipment".tr()),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: pickupController,
                  decoration: InputDecoration(labelText: 'pickup_address'.tr()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dropController,
                  decoration: InputDecoration(labelText: 'drop_address'.tr()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dropdateController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'delivery_date'.tr(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),

                  onTap: () async {
                    DateTime pickupDate =
                        DateTime.tryParse(shipment['pickup_date'] ?? '') ??
                            DateTime.now();

                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate:
                      DateTime.tryParse(dropdateController.text) ??
                          pickupDate,
                      firstDate: pickupDate,
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate != null) {
                      if (pickedDate.isBefore(pickupDate)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("delivery_date_error".tr())),
                        );
                      } else {
                        String formattedDate =
                            "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
                        setState(() {
                          dropdateController.text = formattedDate;
                        });
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
              },
              child: Text("cancel".tr()),
            ),
            ElevatedButton(
              onPressed: () async {
                await _updateShipment(
                  shipment['shipment_id'],
                  pickupController.text,
                  dropController.text,
                  dropdateController.text,
                );
                Navigator.pop(context); // close dialog

                final updatedShipment = await Supabase.instance.client
                    .from('shipment')
                    .select()
                    .eq('shipment_id', shipment['shipment_id'])
                    .single();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ShipmentDetailsPage(shipment: updatedShipment),
                  ),
                );
                _refresh();
              },
              child: Text("save".tr()),
            ),
          ],
        );
      },
    );
  }

  //-------------- to update the shipment details entered in the dialog box-----------------------------
  Future<void> _updateShipment(
      String shipmentId,
      String pickup,
      String drop,
      String deliveryDate,
      ) async {
    try {
      // Perform the update
      final updatedRows = await Supabase.instance.client
          .from('shipment')
          .update({
        'pickup': pickup,
        'drop': drop,
        'delivery_date': deliveryDate,
      })
          .eq('shipment_id', shipmentId)
          .select(); // optional, to get updated rows

      if (updatedRows.isEmpty) {
        throw "Shipment not found or no changes applied";
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("shipment_updated".tr())));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error updating shipment: $e")));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchShipments() async {
    final statusKey = _statusFilters[_tabController.index];
    final response = await Supabase.instance.client.rpc(
      'get_all_shipments_for_admin',
      params: {'search_query': _searchQuery, 'status_filter': statusKey},
    );
    return response == null ? [] : List<Map<String, dynamic>>.from(response);
  }


  Future<void> _refresh() async {
    setState(() {
      _shipmentsFuture = _fetchShipments();
    });
  }

  String trimAddress(String address) {
    // Remove common redundant words
    String cleaned = address
        .replaceAll(
      RegExp(
        r'\b(At Post|Post|Tal|Taluka|Dist|District|Po)\b',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(RegExp(r'\s+'), ' ') // normalize spaces
        .trim();

    List<String> parts = cleaned.split(',');
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 3) {
      String first = parts[0]; // village/area
      String city = parts[parts.length - 2];
      //String state = parts[parts.length - 1];
      return "$first,$city";
    } else if (parts.length == 2) {
      return "${parts[0]}, ${parts[1]}";
    } else {
      // fallback: just shorten
      return cleaned.length > 50 ? "${cleaned.substring(0, 50)}..." : cleaned;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "manage_shipments".tr(),
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.orange,
          labelColor: AppColors.orange,
          unselectedLabelColor: Colors.white70,
          tabs: _statusFilters.map((key) => Tab(text: key.tr())).toList(),
        ),

        //backgroundColor: AppColors.teal,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildShipmentList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: 'search_placeholder'.tr(),
          prefixIcon: const Icon(Icons.search, color: AppColors.teal),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
              _refresh();
            },
          )
              : null,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
        onSubmitted: (_) => _refresh(),
      ),
    );
  }

  Widget _buildShipmentList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _shipmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        final shipments = snapshot.data!;
        if (shipments.isEmpty) {
          return Center(child: Text("no_shipments_found".tr()));
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.teal,
          child: ListView.builder(
            itemCount: shipments.length,
            itemBuilder: (context, index) {
              final shipment = shipments[index];
              return Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.teal,
                  ),
                  title: Text(
                    shipment['shipment_id'] ?? 'No ID',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              trimAddress(shipment['pickup'] ?? ''),
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.flag, color: Colors.red, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              trimAddress(shipment['drop'] ?? ''),
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ([
                        'Pending',
                        'Accepted',
                        'En route Pickup',
                      ].contains(shipment['booking_status'])) ...[
                        IconButton(
                          onPressed: () => _showEditDilog(shipment),
                          icon: const Icon(Icons.edit, color: Colors.blue),
                        ),
                      ],
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ShipmentDetailsPage(shipment: shipment),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShipmentDetailsPage(shipment: shipment),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}