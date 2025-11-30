import 'package:flutter/material.dart';
import 'package:logistics_toolkit/features/mydrivers/addDriver.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;

// Driver model
class Driver {
  final String id;
  final String name;
  final String contact;
  final String status;
  final double? rating;

  Driver({
    required this.id,
    required this.name,
    required this.contact,
    required this.status,
    this.rating,
  });

  Color get statusColor {
    switch (status) {
      case 'Available':
        return Colors.green;
      case 'On Trip':
        return Colors.blue;
      case 'Leave':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'Available':
        return Icons.check_circle;
      case 'On Trip':
        return Icons.directions_car;
      case 'Leave':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  factory Driver.fromMap(Map<String, dynamic> map) {
    final bookingStatus = (map['booking_status'] ?? 'no_shipment')
        .toString()
        .toLowerCase();

    String driverStatus;

    // AVAILABLE if no shipment or last shipment completed / delivered / cancelled
    if (bookingStatus == 'no_shipment' ||
        bookingStatus == 'completed' ||
        bookingStatus == 'delivered' ||
        bookingStatus == 'cancelled') {
      driverStatus = 'Available';
    } else {
      // All other statuses -> On Trip
      driverStatus = 'On Trip';
    }

    return Driver(
      id: (map['custom_user_id'] ?? '').toString(),
      name: (map['name'] ?? 'Unknown').toString(),
      contact: (map['mobile_number'] ?? '').toString(),
      status: driverStatus,
      rating: map['avg_driver_rating'] != null
          ? double.tryParse(map['avg_driver_rating'].toString())
          : null,
    );
  }
}

class MyDriverPage extends StatefulWidget {
  final bool isSelectionMode;
  final String? shipmentId;

  const MyDriverPage({
    super.key,
    this.isSelectionMode = false,
    this.shipmentId,
  });

  @override
  State<MyDriverPage> createState() => _MyDriverPageState();
}

class _MyDriverPageState extends State<MyDriverPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final ptr.RefreshController _refreshController = ptr.RefreshController(
    initialRefresh: false,
  );

  List<Driver> drivers = [];
  bool isLoading = true;
  String loggedInOwnerCustomId = '';

  bool sortByRating = false;
  bool sortByStatus = false;

  int _totalDrivers = 0;
  int availableDrivers = 0;
  int onTripDrivers = 0;
  int onLeaveDrivers = 0;

  String selectedFilter = 'All Drivers';
  bool isFirstTime = true;

  @override
  void initState() {
    super.initState();

    // When in selection mode (assign driver), default to available only
    if (widget.isSelectionMode) {
      selectedFilter = 'available_only'.tr();
    } else {
      checkFirstTime();
    }
    fetchLoggedInOwnerId();
  }

  Future<void> checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    isFirstTime = prefs.getBool('first_time_add_driver') ?? true;
    if (isFirstTime) {
      await prefs.setBool('first_time_add_driver', false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> fetchLoggedInOwnerId() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('user_profiles')
        .select('custom_user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (response != null && response['custom_user_id'] != null) {
      loggedInOwnerCustomId = response['custom_user_id'] as String;
      await fetchDriversFromSupabase();
    }
  }

  // Fetch drivers linked to this owner + their current shipment status
  Future<void> fetchDriversFromSupabase() async {
    if (loggedInOwnerCustomId.isEmpty) return;
    setState(() => isLoading = true);

    try {
      // 1. Get all driver_custom_ids for this owner
      final relationResponse = await supabase
          .from('driver_relation')
          .select('driver_custom_id')
          .eq('owner_custom_id', loggedInOwnerCustomId);

      final driverIds = relationResponse
          .map<String>((row) => row['driver_custom_id'] as String)
          .toList();

      if (driverIds.isEmpty) {
        setState(() {
          drivers = [];
          _totalDrivers = 0;
          availableDrivers = 0;
          onTripDrivers = 0;
          onLeaveDrivers = 0;
          isLoading = false;
        });
        _refreshController.refreshCompleted();
        return;
      }

      // Active statuses list
      final activeStatuses = <String>[
        'pending',
        'accepted',
        'en route to pickup',
        'arrived at pickup',
        'loading',
        'picked up',
        'in transit',
        'arrived at drop',
        'unloading',
        'Pending',
        'Accepted',
        'En Route to Pickup',
        'Arrived at Pickup',
        'Loading',
        'Picked Up',
        'In Transit',
        'Arrived at Drop',
        'Unloading',
      ];

      final List<Map<String, dynamic>> driversWithStatus = [];

      for (final driverCustomId in driverIds) {
        // Profile
        final profileResponse = await supabase
            .from('user_profiles')
            .select('name, custom_user_id, mobile_number')
            .eq('custom_user_id', driverCustomId)
            .maybeSingle();

        if (profileResponse == null) continue;

        final shipmentResponse = await supabase
            .from('shipment')
            .select('booking_status')
            .eq('assigned_driver', driverCustomId)
            .filter('booking_status', 'in', activeStatuses)
            .limit(1);

        final driverData = Map<String, dynamic>.from(profileResponse);
        if (shipmentResponse.isNotEmpty) {
          driverData['booking_status'] =
              shipmentResponse.first['booking_status'];
        } else {
          driverData['booking_status'] = 'no_shipment';
        }

        driversWithStatus.add(driverData);
      }

      final fetchedDrivers = driversWithStatus
          .map((item) => Driver.fromMap(item))
          .toList();

      setState(() {
        drivers = fetchedDrivers;
        _totalDrivers = drivers.length;
        availableDrivers = fetchedDrivers
            .where((d) => d.status == 'Available')
            .length;
        onTripDrivers = fetchedDrivers
            .where((d) => d.status == 'On Trip')
            .length;
        onLeaveDrivers = fetchedDrivers
            .where((d) => d.status == 'Leave')
            .length;
        isLoading = false;
      });
      _refreshController.refreshCompleted();
    } catch (e) {
      setState(() => isLoading = false);
      _refreshController.refreshFailed();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching drivers: $e')));
      }
    }
  }

  List<Driver> get filteredDrivers {
    List<Driver> filtered = drivers.where((driver) {
      if (selectedFilter == 'Available Only' ||
          selectedFilter == 'available_only'.tr()) {
        return driver.status == 'Available';
      }
      if (selectedFilter == 'On Trip' || selectedFilter == 'on_trip'.tr()) {
        return driver.status == 'On Trip';
      }
      if (selectedFilter == 'On Leave' || selectedFilter == 'on_leave'.tr()) {
        return driver.status == 'Leave';
      }
      return true;
    }).toList();

    if (sortByRating) {
      filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    } else if (sortByStatus) {
      final order = {'Available': 0, 'On Trip': 1, 'Leave': 2};
      filtered.sort(
        (a, b) => (order[a.status] ?? 99).compareTo(order[b.status] ?? 99),
      );
    }

    return filtered;
  }

  void _selectDriver(Driver driver) {
    if (!widget.isSelectionMode || driver.status != 'Available') return;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('confirm_driver_assignment'.tr()),
          content: Text(
            'Assign ${driver.name} to shipment ${widget.shipmentId ?? ''}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop(driver.id);
              },
              child: Text('confirm'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, int count, Color color, String filter) {
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = filter),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: selectedFilter == filter
              ? color.withValues(alpha: 0.1)
              : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedFilter == filter ? color : Colors.grey.shade200,
            width: selectedFilter == filter ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callDriver(String contact) async {
    final uri = Uri.parse('tel:${contact.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('could_not_open_dialer'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSelectionMode
              ? 'select_driver'.tr()
              : 'driver_status_list'.tr(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch<String?>(
                context: context,
                delegate: DriverSearchDelegate(
                  drivers,
                  isSelectionMode: widget.isSelectionMode,
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) => setState(() {
              // Compare against translated values so it works with localization
              sortByRating = value == 'rating'.tr();
              sortByStatus = value == 'status'.tr();
            }),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rating'.tr(),
                child: Text('sort_by_rating'.tr()),
              ),
              PopupMenuItem(
                value: 'status'.tr(),
                child: Text('sort_by_status'.tr()),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.isSelectionMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFirstTime)
                  Text(
                    'tap_to_add_driver'.tr(),
                    style: const TextStyle(fontSize: 12),
                  ).animate().fade().slide(),
                const SizedBox(height: 4),
                Animate(
                  effects: [
                    ScaleEffect(duration: 600.ms, end: const Offset(1.1, 1.1)),
                  ],
                  onPlay: (controller) => controller.repeat(reverse: true),
                  child: FloatingActionButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AddDriverPage(),
                        ),
                      );
                      await fetchDriversFromSupabase();
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        'total'.tr(),
                        _totalDrivers,
                        Colors.cyan,
                        'all_drivers'.tr(),
                      ),
                      _buildStatCard(
                        'available'.tr(),
                        availableDrivers,
                        Colors.green,
                        'available_only'.tr(),
                      ),
                      _buildStatCard(
                        'on_trip'.tr(),
                        onTripDrivers,
                        Colors.blue,
                        'on_trip'.tr(),
                      ),
                      _buildStatCard(
                        'on_leave'.tr(),
                        onLeaveDrivers,
                        Colors.red,
                        'on_leave'.tr(),
                      ),
                    ],
                  ),
                ),
                if (widget.isSelectionMode)
                  Container(
                    width: double.infinity,
                    color: Colors.green.shade50,
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Text(
                          'please_select_driver'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Showing only available drivers (not assigned to other shipments)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ptr.SmartRefresher(
                    controller: _refreshController,
                    onRefresh: fetchDriversFromSupabase,
                    enablePullDown: true,
                    enablePullUp: false,
                    header: const ptr.WaterDropHeader(),
                    child: filteredDrivers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 200),
                              Center(
                                child: Text(
                                  'no_drivers_found'.tr(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filteredDrivers.length,
                            itemBuilder: (context, index) {
                              final driver = filteredDrivers[index];
                              final isAvailable = driver.status == 'Available';

                              return Slidable(
                                key: ValueKey(driver.id),
                                endActionPane: widget.isSelectionMode
                                    ? null
                                    : ActionPane(
                                        motion: const ScrollMotion(),
                                        children: [
                                          SlidableAction(
                                            onPressed: (_) =>
                                                _callDriver(driver.contact),
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            icon: Icons.call,
                                            label: 'Call',
                                          ),
                                        ],
                                      ),
                                child: Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 10,
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      if (widget.isSelectionMode &&
                                          isAvailable) {
                                        _selectDriver(driver);
                                      }
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: driver.statusColor
                                          .withValues(alpha: 0.2),
                                      child: Icon(
                                        driver.statusIcon,
                                        color: driver.statusColor,
                                      ),
                                    ),
                                    title: Text(
                                      '${driver.name} (${driver.id})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.phone, size: 16),
                                            const SizedBox(width: 4),
                                            Text(driver.contact),
                                          ],
                                        ),
                                        if (driver.rating != null)
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                driver.rating!.toStringAsFixed(
                                                  1,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                    trailing: widget.isSelectionMode
                                        ? (isAvailable
                                              ? ElevatedButton(
                                                  onPressed: () =>
                                                      _selectDriver(driver),
                                                  child: Text('select'.tr()),
                                                )
                                              : Text(
                                                  'unavailable'.tr(),
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ))
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                driver.statusIcon,
                                                color: driver.statusColor,
                                              ),
                                              Text(
                                                driver.status,
                                                style: TextStyle(
                                                  color: driver.statusColor,
                                                ),
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
              ],
            ),
    );
  }
}

class DriverSearchDelegate extends SearchDelegate<String?> {
  final List<Driver> allDrivers;
  final bool isSelectionMode;

  DriverSearchDelegate(this.allDrivers, {required this.isSelectionMode});

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final queryLower = query.toLowerCase();
    final results = allDrivers.where((driver) {
      final nameMatches = driver.name.toLowerCase().contains(queryLower);
      final contactMatches = driver.contact.contains(queryLower);
      return nameMatches || contactMatches;
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final driver = results[index];
        final isAvailable = driver.status == 'Available';

        return ListTile(
          title: Text(driver.name),
          subtitle: Text(driver.contact),
          trailing: Text(
            driver.status,
            style: TextStyle(color: driver.statusColor),
          ),
          enabled: isSelectionMode ? isAvailable : true,
          onTap: () {
            if (isSelectionMode) {
              if (isAvailable) {
                close(context, driver.id);
              }
            } else {
              close(context, null);
            }
          },
        );
      },
    );
  }
}
