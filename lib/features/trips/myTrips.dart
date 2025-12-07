import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'dart:convert';
import 'package:shimmer/shimmer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'shipment_details.dart';
import 'myTrips_Services.dart';

class MyShipments extends StatefulWidget {
  const MyShipments({super.key});

  @override
  State<MyShipments> createState() => _MyShipmentsPageState();
}

class _MyShipmentsPageState extends State<MyShipments> {
  List<Map<String, dynamic>> shipments = [];
  List<Map<String, dynamic>> filteredShipments = [];
  Set<String> ratedShipments = {};
  Map<String, int> ratingEditCount = {};
  bool loading = true;
  String searchQuery = '';
  String statusFilter = 'All';
  final ptr.RefreshController _refreshController = ptr.RefreshController(
    initialRefresh: false,
  );
  SharedPreferences? _prefs;
  final MyTripsServices _supabase_service = MyTripsServices();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
      loadCachedShipments();
    });
    fetchShipments();
    fetchEditCounts();
  }

  Future<void> fetchEditCounts() async {
    final response = await Supabase.instance.client
        .from('ratings')
        .select('shipment_id, edit_count');

    if (response.isNotEmpty) {
      setState(() {
        for (var row in response) {
          ratingEditCount[row['shipment_id']] = row['edit_count'];
        }
      });
    }
  }

  // Newly Added function to load cached shipments
  Future<void> loadCachedShipments() async {
    final cachedData = _prefs?.getString('shipments_cache');
    if (cachedData != null) {
      setState(() {
        shipments = List<Map<String, dynamic>>.from(jsonDecode(cachedData));
        filteredShipments = shipments;
        loading = false;
      });
    }
  }

  Future<void> saveShipmentToCache(List<Map<String, dynamic>> shipments) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(shipments);
    await prefs.setString('shipments_cache', jsonStr);
  }

  //here shipments are fetched and the custom_user_id is fetched.
  Future<void> fetchShipments() async {
    setState(() => loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    print('My current UID: $userId');

    if (userId == null) {
      setState(() {
        loading = false;
        shipments = [];
        filteredShipments = [];
      });
      return;
    }

    final res = await _supabase_service.getShipmentsForUser(userId);

    // Assign shipments only if res has data
    shipments = List<Map<String, dynamic>>.from(res);

    filteredShipments = shipments.where((s) {
      final status = s['booking_status']?.toString().toLowerCase();
      final deliveryDate = DateTime.tryParse(s['delivery_date'] ?? '');
      if (status == 'completed' && deliveryDate != null) {
        final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
        return deliveryDate.isBefore(sevenDaysAgo);
      }
      return false;
    }).toList();
    await _prefs?.setString('shipments_cache', jsonEncode(shipments));
    await fetchEditCounts();

    setState(() {
      loading = false;
      _refresh_controllerRefreshCompleted();
    });
    try {
      _refreshController.refreshCompleted();
    } catch (_) {}

    applyFilters();
  }
  void _refresh_controllerRefreshCompleted() {
  }

  void searchShipments(String query) {
    setState(() {
      searchQuery = query;
      applyFilters();
    });
  }

  void filterByStatus(String status) {
    setState(() {
      statusFilter = status;
      applyFilters();
    });
  }

  void applyFilters() {
    filteredShipments = shipments.where((s) {
      final matchQuery =
          searchQuery.isEmpty ||
              s.values.any(
                    (val) => val.toString().toLowerCase().contains(
                  searchQuery.toLowerCase(),
                ),
              );
      final matchStatus =
          statusFilter == 'All' ||
              s['booking_status'].toString().toLowerCase() ==
                  statusFilter.toLowerCase();
      return matchQuery && matchStatus;
    }).toList();

    filteredShipments.sort((a, b) {
      final aStatus = a['booking_status'].toString().toLowerCase();
      final bStatus = b['booking_status'].toString().toLowerCase();

      if (aStatus == 'completed' && bStatus != 'completed') {
        return 1;
      } else if (aStatus != 'completed' && bStatus == 'completed') {
        return -1;
      } else {
        final aDate =
            DateTime.tryParse(a['delivery_date'] ?? '') ?? DateTime.now();
        final bDate =
            DateTime.tryParse(b['delivery_date'] ?? '') ?? DateTime.now();
        return aDate.compareTo(bDate);
      }
    });
  }

  void showFilterDialog() {
    final List<String> statuses = [
      'All',
      // 'Pending',
      'Accepted',
      'En Route to Pickup',
      'Arrived at Pickup',
      'Loading',
      'Picked Up',
      'In Transit',
      'Arrived at Drop',
      'Unloading',
      'Delivered',
      'Completed',
    ];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        title: Text('filterByStatus'.tr()),
        content: SingleChildScrollView(
          // 1. Wrap the list container in a RadioGroup
          child: RadioGroup<String>(
            // 2. Manage the state (value and callback) here in the parent
            groupValue: statusFilter,
            onChanged: (val) {
              if (val != null) {
                Navigator.pop(context);
                filterByStatus(val);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: statuses.map((status) {
                // 3. The child tiles only need the 'value' and 'title'
                // 'groupValue' and 'onChanged' are removed
                return RadioListTile<String>(
                  value: status,
                  title: Text(status.tr()),
                  activeColor: Colors.teal,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  IconData getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
        return Icons.check_circle;
      case 'en route to pickup':
        return Icons.local_shipping;
      case 'arrived at pickup':
        return Icons.location_on;
      case 'loading':
        return Icons.upload;
      case 'picked up':
        return Icons.done;
      case 'in transit':
        return Icons.directions_bus;
      case 'arrived at drop':
        return Icons.place;
      case 'unloading':
        return Icons.download;
      case 'delivered':
        return Icons.done_all;
      case 'completed':
        return Icons.verified;
      default:
        return Icons.info;
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'en route to pickup':
        return Colors.purple;
      case 'arrived at pickup':
        return Colors.purple;
      case 'loading':
        return Colors.purple;
      case 'picked up':
        return Colors.purple;
      case 'in transit':
        return Colors.purple;
      case 'arrived at drop':
        return Colors.purple;
      case 'unloading':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'completed':
        return Colors.green;
      default:
        return Colors.black45;
    }
  }

  Widget? getShipmentBadge(Map<String, dynamic> shipment) {
    final deliveryDate = DateTime.tryParse(shipment['delivery_date'] ?? '');
    if (deliveryDate == null) return null;

    final now = DateTime.now();
    final adjustedDeliveryDate = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
      23,
      59,
      59,
    );
    final diff = adjustedDeliveryDate.difference(now);
    final isCompleted = shipment['booking_status'] == 'Completed';

    if (diff.isNegative && !isCompleted) {
      return buildBadgeWithDot(
        label: 'DELAYED'.tr(),
        bgColor: Colors.red,
        dotColor: Colors.red,
      );
    }

    if (diff.inHours <= 24 && diff.inHours > 0 && !isCompleted) {
      return buildBadgeWithDot(
        label: 'urgent'.tr(),
        bgColor: Colors.orange,
        dotColor: Colors.orange,
      );
    }
    return null;
  }

  Widget buildBadgeWithDot({
    required String label,
    required Color bgColor,
    required Color dotColor,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }

  Widget buildStampBadge(String label, Color bgColor) {
    return Transform.rotate(
      angle: 0.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: bgColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String getFormattedDate(String? dateStr) {
    final date = DateTime.tryParse(dateStr ?? '') ?? DateTime.now();
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;

    final formattedDate = DateFormat('dd MMM').format(date);
    if (diff == 0) {
      return '${'todayPrefix'.tr()} $formattedDate';
    } else if (diff == 1) {
      return '${'yesterdayPrefix'.tr()} $formattedDate';
    } else if (diff == 2) {
      return '${'twoDaysAgoPrefix'.tr()} $formattedDate';
    }
    return formattedDate;
  }

  String trimAddress(String address) {
    String cleaned = address
        .replaceAll(
      RegExp(
        r'\b(At Post|Post|Tal|Taluka|Dist|District|Po)\b',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    List<String> parts = cleaned.split(',');
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 3) {
      String first = parts[0];
      String city = parts[parts.length - 2];
      return "$first,$city";
    } else if (parts.length == 2) {
      return "${parts[0]}, ${parts[1]}";
    } else {
      return cleaned.length > 50 ? "${cleaned.substring(0, 50)}..." : cleaned;
    }
  }

  Widget buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Card(
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[300],
                radius: 20,
              ),
              title: Container(
                width: double.infinity,
                height: 16,
                color: Colors.grey[300],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 100, height: 12, color: Colors.grey[300]),
                  const SizedBox(height: 4),
                  Container(width: 150, height: 12, color: Colors.grey[300]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'noShipments'.tr(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'tryRefreshing'.tr(),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: fetchShipments,
            icon: const Icon(Icons.refresh),
            label: Text('refresh'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('activeTrips'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showSearch(
                context: context,
                delegate: ShipmentSearchDelegate(shipments: shipments),
              );
              if (result != null) searchShipments(result);
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchShipments,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchShipments,
          child: loading
              ? buildSkeletonLoader()
              : filteredShipments.isEmpty
              ? buildEmptyState()
              : ListView.builder(
            itemCount: filteredShipments.length > 10
                ? 10
                : filteredShipments.length,
            itemBuilder: (_, i) {
              final s = filteredShipments[i];
              return InkWell(
                onTap: () async {
                  final newEditCount = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ShipmentDetailsPage(
                        shipment: s,
                      ),
                    ),
                  );
                  if (newEditCount != null && newEditCount is int) {
                    final index = filteredShipments.indexWhere(
                          (shipment) =>
                      shipment['shipment_id'] == s['shipment_id'],
                    );
                    if (index != -1) {
                      setState(() {
                        filteredShipments[index]['edit_count'] =
                            newEditCount;
                      });
                    }
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  elevation: 0.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadiusGeometry.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pickup Address Row
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${trimAddress(s['pickup'] ?? '')}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              // Drop Address Row
                              Row(
                                children: [
                                  Icon(Icons.pin_drop, color: Colors.teal),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${trimAddress(s['drop'] ?? '')}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${s['shipment_id']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${'pickup'.tr()}: ${getFormattedDate(s['created_at'])}',
                              ),
                              Text(
                                '${'drop'.tr()}: ${getFormattedDate(s['delivery_date'])}',
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    getStatusIcon(s['booking_status']),
                                    size: 20,
                                    color: getStatusColor(
                                      s['booking_status'],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Place the status text here (localized if key exists)
                                  Text(s['booking_status'].toString().tr()),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (getShipmentBadge(s) != null) getShipmentBadge(s)!,
                            const SizedBox(height: 50),
                            if (s['booking_status'] != 'Completed')
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 80,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.teal.shade100,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.location_pin,
                                        size: 40,
                                        color: Colors.teal[700],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'track'.tr(),
                                        style: TextStyle(
                                          color: Colors.teal[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class ShipmentSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, dynamic>> shipments;
  ShipmentSearchDelegate({required this.shipments});

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => Container();

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = shipments
        .where(
          (s) => s.values.any(
            (val) => val.toString().toLowerCase().contains(query.toLowerCase()),
      ),
    )
        .toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final s = results[i];
        return ListTile(
          title: Text('${s['pickup']} → ${s['drop']}'),
          subtitle:
          Text('${'status'.tr()}: ${s['booking_status'] ?? ''}'),
          onTap: () => close(context, query),
        );
      },
    );
  }
}