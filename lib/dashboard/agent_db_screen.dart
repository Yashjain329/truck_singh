import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:logistics_toolkit/features/Report%20Analysis/report_chart.dart';
import 'package:logistics_toolkit/features/bilty/shipment_selection_page.dart';
import 'package:logistics_toolkit/features/tracking/shared_shipments_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard/widgets/feature_card.dart';
import '../features/shipment/shipper_form_page.dart';
import '../features/trips/myTrips_history.dart';
import '../widgets/common/app_bar.dart';
import '../features/auth/services/supabase_service.dart';
import '../services/onesignal_notification_service.dart';
import '../features/settings/presentation/screen/settings_page.dart';
import '../features/laod_assignment/presentation/cubits/shipment_cubit.dart';
import '../features/laod_assignment/presentation/screen/load_assignment_screen.dart';
import '../features/laod_assignment/presentation/screen/allLoads.dart';
import '../features/trips/myTrips.dart';
import '../features/mytruck/mytrucks.dart';
import '../features/mydrivers/mydriver.dart';
import '../features/ratings/presentation/screen/trip_ratings.dart';
import '../features/complains/mycomplain.dart';
import '../features/invoice/services/invoice_pdf_service.dart';
import '../features/bilty/transport_bilty_form.dart';
import '../features/driver_documents/driver_documents_page.dart';
import '../features/truck_documents/truck_documents_page.dart';
import '../features/chat/agent_chat_list_page.dart'; // Import for Agent Chat
import 'package:easy_localization/easy_localization.dart';

// A simple model to hold all the data and state for the dashboard
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
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userProfile: userProfile ?? this.userProfile,
      activeShipment: activeShipment,
      shipmentStats: shipmentStats ?? this.shipmentStats,
    );
  }
}

// UserService with more efficient queries
class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    return await _supabase
        .from('user_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single();
  }

  // Corrected: Uses efficient .count() method
  Future<Map<String, int>> getShipmentStats(String customUserId) async {
    final activeLoadsResponse = await _supabase
        .from('shipment')
        .count(CountOption.exact)
        .eq('assigned_agent', customUserId)
        .neq('booking_status', 'Completed');

    final completedLoadsResponse = await _supabase
        .from('shipment')
        .count(CountOption.exact)
        .eq('assigned_agent', customUserId)
        .eq('booking_status', 'Completed');

    return {
      'activeLoads': activeLoadsResponse,
      'completedLoads': completedLoadsResponse,
    };
  }

  Future<Map<String, dynamic>?> getActiveShipment(String customUserId) async {
    return await _supabase
        .from('shipment')
        .select(
          'shipment_id, assigned_driver',
        ) // Select only what's needed for the chat
        .eq('assigned_agent', customUserId)
        .filter('booking_status', 'in', [
          'Accepted',
          'En Route to Pickup',
          'Arrived at Pickup',
          'In Transit',
        ])
        .order('created_at', ascending: false)
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
  final UserService _userService = UserService();
  DashboardState _dashboardState = DashboardState();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    initializeOneSignalAndStorePlayerId();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _dashboardState = _dashboardState.copyWith(isLoading: true, error: null));

    try {
      final profile = await _userService.getUserProfile();
      final customUserId = profile['custom_user_id'];
      if (customUserId == null) throw Exception('Custom user ID is missing.');

      // Fetch stats and active shipment in parallel for better performance
      final results = await Future.wait([
        _userService.getShipmentStats(customUserId),
        _userService.getActiveShipment(customUserId),
      ]);

      // Safely cast results
      final stats = results[0] as Map<String, int>;
      final activeShipment = results[1] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _dashboardState = _dashboardState.copyWith(
            isLoading: false,
            userProfile: profile,
            shipmentStats: stats,
            activeShipment: activeShipment,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _dashboardState = _dashboardState.copyWith(
            isLoading: false,
            error: e.toString(),
          ),
        );
        _showErrorSnackBar("Failed to load dashboard: ${e.toString()}");
      }
    }
  }

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      elevation: 10.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ReportAnalysisPage(),
              ),
            );
          },
          icon: const Icon(Icons.analytics_outlined),
          label: Text('viewreport&analysis'.tr()),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;
    return Scaffold(
      //backgroundColor: const Color(0xFFF5F7FA),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: _buildAppBar(),
      body: _dashboardState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dashboardState.error != null
          ? Center(child: Text('Error: ${_dashboardState.error}'))
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildPerformanceOverviewCard(),
                    const SizedBox(height: 20),
                    _buildFeatureGrid(),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomAppBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return CustomAppBar(
      showProfile: true,
      userProfile: _dashboardState.userProfile,
      isLoading: _dashboardState.isLoading,
      shipment: _dashboardState.activeShipment,
      showMessages: true, // Enable the message button
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsPage()),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildPerformanceOverviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'performanceOverview'.tr(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildOverviewItem(
                  'activeLoads'.tr(),
                  '${_dashboardState.shipmentStats['activeLoads']}',
                  Icons.local_shipping,
                ),
              ),
              Expanded(
                child: _buildOverviewItem(
                  'completed'.tr(),
                  '${_dashboardState.shipmentStats['completedLoads']}',
                  Icons.check_circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        FeatureCard(
          title: 'findShipments'.tr(),
          subtitle: 'availableLoads'.tr(),
          icon: Icons.search_outlined,
          color: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider(
                create: (context) => ShipmentCubit(),
                child: const LoadAssignmentScreen(),
              ),
            ),
          ),
        ),
        FeatureCard(
          title: 'createShipment'.tr(),
          subtitle: 'postNewLoad'.tr(),
          icon: Icons.add_box_rounded,
          color: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ShipperFormPage()),
          ),
        ),
        FeatureCard(
          title: 'myChats'.tr(), // New Card
          subtitle: 'viewConversations'.tr(),
          icon: Icons.chat_bubble_outline,
          color: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AgentChatListPage()),
          ),
        ),
        FeatureCard(
          title: 'loadBoard'.tr(),
          subtitle: 'browsePostLoads'.tr(),
          icon: Icons.view_list_outlined,
          color: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider(
                create: (context) => ShipmentCubit(),
                child: const allLoadsPage(),
              ),
            ),
          ),
        ),
        FeatureCard(
          title: 'activeTrips'.tr(),
          subtitle: 'monitorLiveLocations'.tr(),
          icon: Icons.map_outlined,
          color: Colors.orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyShipments()),
          ),
        ),
        FeatureCard(
          title: 'sharedtrips'.tr(),
          subtitle: 'sharedtracking'.tr(),
          icon: Icons.share_location,
          color: Colors.orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SharedShipmentsPage(),
            ),
          ),
        ),
        FeatureCard(
          title: 'myTrucks'.tr(),
          subtitle: 'addTrackVehicles'.tr(),
          icon: Icons.local_shipping_outlined,
          color: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const Mytrucks()),
          ),
        ),
        FeatureCard(
          title: 'myDrivers'.tr(),
          subtitle: 'addTrackDrivers'.tr(),
          icon: Icons.people_outlined,
          color: Colors.deepPurple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyDriverPage()),
          ),
        ),
        FeatureCard(
          title: 'ratings'.tr(),
          subtitle: 'viewRatings'.tr(),
          icon: Icons.star_outline,
          color: Colors.orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TripRatingsPage()),
          ),
        ),
        FeatureCard(
          title: 'complaints'.tr(),
          subtitle: 'fileOrView'.tr(),
          icon: Icons.feedback_outlined,
          color: Colors.deepOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ComplaintHistoryPage(),
            ),
          ),
        ),
        FeatureCard(
          title: 'myTrips'.tr(),
          subtitle: 'historyDetails'.tr(),
          icon: Icons.route_outlined,
          color: Colors.blueGrey,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyTripsHistory()),
          ),
        ),
        FeatureCard(
          title: 'bilty'.tr(),
          subtitle: 'createConsignmentNote'.tr(),
          icon: Icons.receipt_long,
          color: Colors.green,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ShipmentSelectionPage(),
            ),
          ),
        ),
        FeatureCard(
          title: 'driverDocuments'.tr(),
          subtitle: 'manageDriverRecords'.tr(),
          icon: Icons.person_outline,
          color: Colors.deepPurple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DriverDocumentsPage(),
            ),
          ),
        ),
        FeatureCard(
          title: 'truckDocuments'.tr(),
          subtitle: 'documents_subtitle'.tr(),
          icon: Icons.local_shipping_outlined,
          color: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TruckDocumentsPage()),
          ),
        ),
      ],
    );
  }
}
