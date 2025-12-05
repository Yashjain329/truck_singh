import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard/widgets/feature_card.dart';
import '../widgets/chat_screen.dart';
import '../widgets/common/app_bar.dart';
import '../services/onesignal_notification_service.dart';
import '../features/Report Analysis/report_chart.dart';
import '../features/bilty/shipment_selection_page.dart';
import '../features/tracking/shared_shipments_page.dart';
import '../features/shipment/shipper_form_page.dart';
import '../features/laod_assignment/presentation/cubits/shipment_cubit.dart';
import '../features/laod_assignment/presentation/screen/load_assignment_screen.dart';
import '../features/laod_assignment/presentation/screen/allLoads.dart';
import '../features/trips/myTrips.dart';
import '../features/trips/myTrips_history.dart';
import '../features/mytruck/mytrucks.dart';
import '../features/mydrivers/mydriver.dart';
import '../features/ratings/presentation/screen/trip_ratings.dart';
import '../features/chat/agent_chat_list_page.dart';
import '../features/complains/mycomplain.dart';
import '../features/settings/presentation/screen/settings_page.dart';
import '../features/driver_documents/driver_documents_page.dart';
import '../features/truck_documents/truck_documents_page.dart';
import '../widgets/floating_chat_control.dart';

class DashboardState {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? userProfile;
  final Map<String, dynamic>? activeShipment;
  final Map<String, int> shipmentStats;

  DashboardState({
    this.isLoading = true,
    this.error,
    this.userProfile,
    this.activeShipment,
    this.shipmentStats = const {'activeLoads': 0, 'completedLoads': 0},
  });

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    Map<String, dynamic>? userProfile,
    Map<String, dynamic>? activeShipment,
    Map<String, int>? shipmentStats,
  }) =>
      DashboardState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        userProfile: userProfile ?? this.userProfile,
        activeShipment: activeShipment ?? this.activeShipment,
        shipmentStats: shipmentStats ?? this.shipmentStats,
      );
}

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    return await _supabase.from('user_profiles').select('*').eq('user_id', user.id).single();
  }

  Future<Map<String, int>> getShipmentStats(String id) async {
    final active = await _supabase.from('shipment').count(CountOption.exact).eq('assigned_agent', id).neq('booking_status', 'Completed');
    final completed = await _supabase.from('shipment').count(CountOption.exact).eq('assigned_agent', id).eq('booking_status', 'Completed');

    return {'activeLoads': active, 'completedLoads': completed};
  }

  Future<Map<String, dynamic>?> getActiveShipment(String id) async {
    return await _supabase
        .from('shipment')
        .select('shipment_id, assigned_driver')
        .eq('assigned_agent', id)
        .filter('booking_status', 'in', ['Accepted', 'En Route to Pickup', 'Arrived at Pickup', 'In Transit'])
        .order('created_at')
        .limit(1)
        .maybeSingle();
  }
}

class AgentDashboard extends StatefulWidget {
  const AgentDashboard({Key? key}) : super(key: key);

  @override
  State<AgentDashboard> createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard> {
  DashboardState _dashboard = DashboardState();
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    initializeOneSignalAndStorePlayerId();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _dashboard = _dashboard.copyWith(isLoading: true));
    try {
      final profile = await _userService.getUserProfile();
      final id = profile['custom_user_id'];

      final results = await Future.wait([
        _userService.getShipmentStats(id),
        _userService.getActiveShipment(id),
      ]);

      if (!mounted) return;
      setState(() {
        _dashboard = _dashboard.copyWith(
          isLoading: false,
          userProfile: profile,
          shipmentStats: results[0] as Map<String, int>,
          activeShipment: results[1],
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _dashboard = _dashboard.copyWith(isLoading: false, error: e.toString()));
      _showSnack("Failed to load dashboard: $e");
    }
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(
        showProfile: true,
        userProfile: _dashboard.userProfile,
        isLoading: _dashboard.isLoading,
        shipment: _dashboard.activeShipment,
        showMessages: true,
        onProfileTap: () => _push(const SettingsPage()),
      ),
      body: Stack(
        children: [
          _dashboard.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _dashboard.error != null
              ? Center(child: Text("Error: ${_dashboard.error}"))
              : RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _performanceCard(),
                const SizedBox(height: 20),
                _featureGrid(),
              ],
            ),
          ),
          // Floating Chat Control always visible
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingChatControl(
              onOpenChat: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      onNavigate: (s) {
                        Navigator.of(context).pushNamed('/$s');
                      },
                    ),
                  ),
                );
              },
              listening: false,
            ),
          ),
        ],
      ),

      bottomNavigationBar: BottomAppBar(
        child: ElevatedButton.icon(
          onPressed: () => _push(const ReportAnalysisPage()),
          icon: const Icon(Icons.analytics_outlined),
          label: Text('viewreport&analysis'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }

  Widget _performanceCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Colors.green.shade700, Colors.green.shade500]),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: .3), blurRadius: 8)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('performanceOverview'.tr(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _stat('activeLoads'.tr(), '${_dashboard.shipmentStats['activeLoads']}', Icons.local_shipping)),
            Expanded(child: _stat('completed'.tr(), '${_dashboard.shipmentStats['completedLoads']}', Icons.check_circle)),
          ],
        ),
      ],
    ),
  );

  Widget _stat(String label, String value, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [Icon(icon, color: Colors.white70, size: 16), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white70))]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
    ],
  );

  Widget _featureGrid() {
    final items = [
      _fc('findShipments', 'availableLoads', Icons.search_outlined, () => _push(BlocProvider(create: (_) => ShipmentCubit(), child: const LoadAssignmentScreen()))),
      _fc('createShipment', 'postNewLoad', Icons.add_box_rounded, () => _push(const ShipperFormPage())),
      _fc('myChats', 'viewConversations', Icons.chat_bubble_outline, () => _push(const AgentChatListPage())),
      _fc('loadBoard', 'browsePostLoads', Icons.view_list_outlined, () => _push(BlocProvider(create: (_) => ShipmentCubit(), child: const allLoadsPage()))),
      _fc('activeTrips', 'monitorLiveLocations', Icons.map_outlined, () => _push(const MyShipments())),
      _fc('sharedtrips', 'sharedtracking', Icons.share_location, () => _push(const SharedShipmentsPage())),
      _fc('myTrucks', 'addTrackVehicles', Icons.local_shipping_outlined, () => _push(const Mytrucks())),
      _fc('myDrivers', 'addTrackDrivers', Icons.people_outlined, () => _push(const MyDriverPage())),
      _fc('ratings', 'viewRatings', Icons.star_outline, () => _push(const TripRatingsPage())),
      _fc('complaints', 'fileOrView', Icons.feedback_outlined, () => _push(const ComplaintHistoryPage())),
      _fc('myTrips', 'historyDetails', Icons.route_outlined, () => _push(const MyTripsHistory())),
      _fc('bilty', 'createConsignmentNote', Icons.receipt_long, () => _push(const ShipmentSelectionPage())),
      _fc('driverDocuments', 'manageDriverRecords', Icons.person_outline, () => _push(const DriverDocumentsPage())),
      _fc('truckDocuments', 'documents_subtitle', Icons.local_shipping_outlined, () => _push(const TruckDocumentsPage())),
    ];

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      childAspectRatio: 1.1,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: items,
    );
  }

  FeatureCard _fc(String t, String s, IconData i, VoidCallback onTap) =>
      FeatureCard(title: t.tr(), subtitle: s.tr(), icon: i, color: Colors.teal, onTap: onTap);
}