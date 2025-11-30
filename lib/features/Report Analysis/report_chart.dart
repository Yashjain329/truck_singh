import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';

class ShipmentUtils {
  static String monthName(String? iso) {
    if (iso == null) return '';
    return DateFormat('MMMM').format(DateTime.parse(iso));
  }

  static String formattedDate(String? iso) {
    if (iso == null) return '';
    return DateFormat('dd MMM yyyy').format(DateTime.parse(iso));
  }

  static String extractCity(String? address) {
    if (address == null) return '';
    List<String> parts = address.split(',');
    if (parts.length < 2) return address.trim();

    List<String> trimmed = parts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (trimmed.length < 2) return trimmed.first;
    return trimmed[trimmed.length - 2];
  }
}

class ShipmentListItem extends StatelessWidget {
  final Map<String, dynamic> shipment;
  final Color statusColor;

  const ShipmentListItem({
    super.key,
    required this.shipment,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: statusColor.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: statusColor, radius: 8),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  shipment['booking_status'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                shipment['shipment_id']?.toString() ?? '',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ),

          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver: ${shipment['assigned_driver'] ?? ""}',
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Route: ${shipment['pickup'] ?? "?"} → ${ShipmentUtils.extractCity(shipment['drop'])}',
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Date: ${ShipmentUtils.formattedDate(shipment['updated_at'])}',
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportAnalysisPage extends StatefulWidget {
  const ReportAnalysisPage({super.key});

  @override
  State<ReportAnalysisPage> createState() => _ReportAnalysisPageState();
}

class _ReportAnalysisPageState extends State<ReportAnalysisPage> {
  // Filters
  String selectedStatus = 'All';
  String selectedMonth = 'All';
  String selectedLocation = 'All';
  String activeChartFilter = '';
  String searchQuery = '';

  // UI States
  bool showBarChart = false;
  bool isLoading = true;
  bool hasError = false;

  // Pagination
  int shipmentLimit = 30;

  List<Map<String, dynamic>> shipments = [];
  final ScrollController _scrollController = ScrollController();

  final List<String> shipmentStatuses = [
    'Pending',
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
    'Returned',
  ];

  final Map<String, Color> statusColors = {
    'Pending': Colors.orange,
    'Accepted': Colors.blue,
    'En Route to Pickup': Colors.deepPurple,
    'Arrived at Pickup': Colors.indigo,
    'Loading': Colors.amber,
    'Picked Up': Colors.purple,
    'In Transit': Colors.pink,
    'Arrived at Drop': Colors.brown,
    'Unloading': Colors.grey,
    'Delivered': Colors.teal,
    'Completed': Colors.green,
    'Returned': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    fetchAgentShipment();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> fetchAgentShipment({bool loadMore = false}) async {
    setState(() {
      isLoading = true;
      hasError = false;
    });

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      setState(() {
        isLoading = false;
        hasError = true;
      });
      return;
    }

    try {
      final userProfile = await supabase
          .from('user_profiles')
          .select('custom_user_id, name, user_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (userProfile == null) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
        return;
      }

      final customUserId = userProfile['custom_user_id'];
      if (customUserId == null) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
        return;
      }

      final start = loadMore ? shipments.length : 0;
      final end = start + shipmentLimit - 1;

      final raw = await supabase
          .from('shipment')
          .select(
            'shipment_id, pickup, drop, booking_status, assigned_driver, updated_at, delivery_date',
          )
          .eq('assigned_agent', customUserId)
          .order('updated_at', ascending: false)
          .range(start, end);

      final List<Map<String, dynamic>> newItems = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        if (loadMore) {
          shipments.addAll(newItems);
        } else {
          shipments = newItems;
        }
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        hasError = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error loading shipments: $e")));
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !isLoading &&
        shipments.length >= shipmentLimit) {
      fetchAgentShipment(loadMore: true);
    }
  }

  List<String> get months {
    final set = <String>{};
    for (var s in shipments) {
      if (s['updated_at'] != null) {
        set.add(ShipmentUtils.monthName(s['updated_at']));
      }
    }
    return ['All', ...set];
  }

  List<String> get locations {
    final set = <String>{};
    for (var s in shipments) {
      final city = ShipmentUtils.extractCity(s['drop']);
      if (city.isNotEmpty) set.add(city);
    }
    return ['All', ...set];
  }

  List<Map<String, dynamic>> _filterShipments() {
    return shipments.where((shipment) {
      final byStatus =
          selectedStatus == 'All' ||
          shipment['booking_status'] == selectedStatus;

      final byMonth =
          selectedMonth == 'All' ||
          (shipment['updated_at'] != null &&
              ShipmentUtils.monthName(shipment['updated_at']) == selectedMonth);

      final byLocation =
          selectedLocation == 'All' ||
          ShipmentUtils.extractCity(shipment['drop']) == selectedLocation;

      final byChart =
          activeChartFilter.isEmpty ||
          shipment['booking_status'] == activeChartFilter;

      final bySearch =
          searchQuery.isEmpty ||
          shipment.values.any(
            (v) =>
                v != null &&
                v.toString().toLowerCase().contains(searchQuery.toLowerCase()),
          );

      return byStatus && byMonth && byLocation && byChart && bySearch;
    }).toList();
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          label: Text('Status: $selectedStatus'),
          selected: selectedStatus != 'All',
          onSelected: (_) => _selectStatus(),
        ),
        FilterChip(
          label: Text('Month: $selectedMonth'),
          selected: selectedMonth != 'All',
          onSelected: (_) => _selectMonth(),
        ),
        FilterChip(
          label: Text('Location: $selectedLocation'),
          selected: selectedLocation != 'All',
          onSelected: (_) => _selectLocation(),
        ),
        if (selectedStatus != 'All' ||
            selectedMonth != 'All' ||
            selectedLocation != 'All' ||
            searchQuery.isNotEmpty)
          ActionChip(
            avatar: const Icon(Icons.clear),
            label: Text('reset'.tr()),
            onPressed: () {
              setState(() {
                selectedStatus = 'All';
                selectedMonth = 'All';
                selectedLocation = 'All';
                searchQuery = '';
                activeChartFilter = '';
              });
            },
          ),
      ],
    );
  }

  Future<void> _selectStatus() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('select_status'.tr()),
        children: [
          for (final status in ['All', ...shipmentStatuses])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, status),
              child: Text(status),
            ),
        ],
      ),
    );

    if (result != null) setState(() => selectedStatus = result);
  }

  Future<void> _selectMonth() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('select_month'.tr()),
        children: [
          for (final m in months)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m),
              child: Text(m),
            ),
        ],
      ),
    );

    if (result != null) setState(() => selectedMonth = result);
  }

  Future<void> _selectLocation() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('select_city'.tr()),
        children: [
          for (final city in locations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, city),
              child: Text(city),
            ),
        ],
      ),
    );

    if (result != null) setState(() => selectedLocation = result);
  }

  Widget _buildPieChart(List<Map<String, dynamic>> filteredShipments) {
    final statusCounts = <String, int>{for (final s in shipmentStatuses) s: 0};

    for (var s in filteredShipments) {
      final st = s['booking_status'];
      if (statusCounts.containsKey(st)) {
        statusCounts[st] = statusCounts[st]! + 1;
      }
    }

    final total = statusCounts.values.fold(0, (p, c) => p + c);

    return Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.25,
          child: PieChart(
            PieChartData(
              sections: [
                for (final e in statusCounts.entries)
                  if (e.value > 0)
                    PieChartSectionData(
                      value: e.value.toDouble(),
                      color: statusColors[e.key],
                      title: total > 0
                          ? '${(e.value / total * 100).toStringAsFixed(1)}%'
                          : '0%',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      radius: activeChartFilter == e.key ? 80 : 65,
                    ),
              ],

              // NEW FL CHART API
              pieTouchData: PieTouchData(
                touchCallback: (event, touchResponse) {
                  if (touchResponse != null &&
                      touchResponse.touchedSection != null) {
                    final index =
                        touchResponse.touchedSection!.touchedSectionIndex;
                    final key = statusCounts.keys.elementAt(index);

                    setState(() {
                      activeChartFilter = (activeChartFilter == key) ? '' : key;
                    });
                  }
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          children: [
            for (final e in statusCounts.entries)
              if (e.value > 0)
                FilterChip(
                  label: Text('${e.key} (${e.value})'),
                  selected: activeChartFilter == e.key,
                  backgroundColor: statusColors[e.key]!.withValues(alpha: 0.18),
                  selectedColor: statusColors[e.key],
                  onSelected: (_) {
                    setState(() {
                      activeChartFilter = (activeChartFilter == e.key)
                          ? ''
                          : e.key;
                    });
                  },
                ),
          ],
        ),
      ],
    );
  }

  Widget _buildBarChart(List<Map<String, dynamic>> filteredShipments) {
    final counts = <String, int>{};

    for (var s in filteredShipments) {
      final dt = s['updated_at'] != null
          ? DateTime.parse(s['updated_at'])
          : DateTime.now();

      final month = DateFormat('MMM').format(dt);
      counts[month] = (counts[month] ?? 0) + 1;
    }

    final list = counts.keys.toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.25,
      child: BarChart(
        BarChartData(
          barGroups: [
            for (int i = 0; i < list.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (counts[list[i]] ?? 0).toDouble(),
                    color: Colors.blueAccent,
                    width: 18,
                  ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final index = v.toInt();
                  if (index < 0 || index >= list.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(list[index]);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShipmentList(List<Map<String, dynamic>> list) {
    if (hasError) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            "something_went_wrong".tr(),
            style: const TextStyle(fontSize: 16, color: Colors.red),
          ),
        ),
      );
    }

    if (list.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox, color: Colors.grey, size: 48),
          const SizedBox(height: 8),
          Text('no_shipments'.tr()),
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text('reload'.tr()),
            onPressed: fetchAgentShipment,
          ),
        ],
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final s = list[i];
        return ShipmentListItem(
          shipment: s,
          statusColor: statusColors[s['booking_status']] ?? Colors.grey,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _filterShipments();
    final width = MediaQuery.of(context).size.width;
    final bool wide = width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('report_analysis'.tr()),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchAgentShipment,
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: () => fetchAgentShipment(),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterChips(),

              const SizedBox(height: 20),

              Text(
                'shipment_summary'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: showBarChart
                        ? _buildBarChart(data)
                        : _buildPieChart(data),
                  ),
                  IconButton(
                    icon: Icon(
                      showBarChart ? Icons.pie_chart : Icons.bar_chart,
                    ),
                    onPressed: () =>
                        setState(() => showBarChart = !showBarChart),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Shipments (${data.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: wide ? 350 : width * 0.6,
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'search'.tr(),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => searchQuery = v),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildShipmentList(data),
            ],
          ),
        ),
      ),
    );
  }
}
