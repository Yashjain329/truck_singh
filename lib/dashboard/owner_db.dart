import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../dashboard/widgets/feature_card.dart';
import '../features/chat/agent_chat_list_page.dart';
import '../features/driver_documents/driver_documents_page.dart';
import '../features/trips/myTrips_history.dart';
import '../features/truck_documents/truck_documents_page.dart';
import '../widgets/chat_screen.dart';
import '../widgets/common/app_bar.dart';
import 'package:logistics_toolkit/features/bilty/shipment_selection_page.dart';
import '../services/onesignal_notification_service.dart';
import '../features/settings/presentation/screen/settings_page.dart';
import '../features/mytruck/mytrucks.dart';
import '../features/mydrivers/mydriver.dart';
import '../features/tracking/tracktruckspage.dart';
import '../features/complains/mycomplain.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/laod_assignment/presentation/cubits/shipment_cubit.dart';
import '../features/laod_assignment/presentation/screen/load_assignment_screen.dart';
import '../features/shipment/shipper_form_page.dart';
import '../features/laod_assignment/presentation/screen/allLoads.dart';
import '../features/trips/myTrips.dart';
import 'package:logistics_toolkit/features/tracking/shared_shipments_page.dart';
import '../features/ratings/presentation/screen/trip_ratings.dart';
import 'package:logistics_toolkit/features/Report%20Analysis/report_chart.dart';

import '../widgets/floating_chat_control.dart';

class DashboardState {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? userProfile;
  final Map<String, int> dashboardStats;

  DashboardState({
    this.isLoading = true,
    this.error,
    this.userProfile,
    this.dashboardStats = const {
      'total_trucks': 0,
      'active_trucks': 0,
      'total_drivers': 0,
    },
  });

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    Map<String, dynamic>? userProfile,
    Map<String, int>? dashboardStats,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userProfile: userProfile ?? this.userProfile,
      dashboardStats: dashboardStats ?? this.dashboardStats,
    );
  }
}

// Service dedicated to fetching data for the Truck Owner
class TruckOwnerService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('error_user_not_authenticated'.tr());
    return await _supabase
        .from('user_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single();
  }

  // Uses an RPC for efficient calculation of stats on the database
  Future<Map<String, int>> getDashboardStats(String ownerId) async {
    final stats = await _supabase.rpc(
      'get_owner_dashboard_stats'.tr(),
      params: {'p_owner_id': ownerId},
    );

    return {
      'total_trucks': (stats['total_trucks'] ?? 0) as int,
      'active_trucks': (stats['active_trucks'] ?? 0) as int,
      'total_drivers': (stats['total_drivers'] ?? 0) as int,
    };
  }
}

class TruckOwnerDashboard extends StatefulWidget {
  const TruckOwnerDashboard({Key? key}) : super(key: key);

  @override
  State<TruckOwnerDashboard> createState() => _TruckOwnerDashboardState();
}

class _TruckOwnerDashboardState extends State<TruckOwnerDashboard> {
  final TruckOwnerService _ownerService = TruckOwnerService();
  DashboardState _dashboardState = DashboardState();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    initializeOneSignalAndStorePlayerId();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _dashboardState = _dashboardState.copyWith(isLoading: true));

    try {
      final profile = await _ownerService.getUserProfile();
      final customUserId = profile['custom_user_id'];
      if (customUserId == null)
        throw Exception('error_custom_user_id_missing'.tr());

      final stats = await _ownerService.getDashboardStats(customUserId);

      if (mounted) {
        setState(() {
          _dashboardState = _dashboardState.copyWith(
            isLoading: false,
            userProfile: profile,
            dashboardStats: stats,
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
        _showErrorSnackBar("error_failed_dashboard_load: ${e.toString()}".tr());
      }
    }
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomAppBar(),
      body: Stack(
        children: [
          _dashboardState.isLoading
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

    );
  }

  PreferredSizeWidget _buildAppBar() {
    return CustomAppBar(
      showProfile: true,
      userProfile: _dashboardState.userProfile,
      isLoading: _dashboardState.isLoading,
      showMessages: true, // Enable the message button
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsPage()),
        );
      },
    );
  }

  Widget _buildPerformanceOverviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'fleet_overview'.tr(),
            style: const TextStyle(
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
                  'total_trucks'.tr(),
                  '${_dashboardState.dashboardStats['total_trucks']}',
                  Icons.local_shipping,
                ),
              ),
              Expanded(
                child: _buildOverviewItem(
                  'total_drivers'.tr(),
                  '${_dashboardState.dashboardStats['total_drivers']}',
                  Icons.people,
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

  // ✅ Adaptive column count
  int _getCrossAxisCount(double width) {
    if (width < 600) {
      return 2; // Phones
    } else if (width < 1024) {
      return 3; // Tablets
    } else {
      return 4; // Large screens
    }
  }

  Widget _buildFeatureGrid() {
    // Get custom user ID for navigation
    final customUserId = _dashboardState.userProfile?['custom_user_id'];

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: _getCrossAxisCount(constraints.maxWidth),
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
            ), FeatureCard(
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
              title: 'track_vehicles'.tr(),
              subtitle: 'live_fleet_tracking'.tr(),
              icon: Icons.map_outlined,
              color: Colors.orange,
              onTap: () {
                if (customUserId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TrackTrucksPage(truckOwnerId: customUserId),
                    ),
                  );
                } else {
                  _showErrorSnackBar('error_tracking_user_id'.tr());
                }
              },
            ),
            FeatureCard(
              title: 'my_trucks'.tr(),
              subtitle: 'add_manage_fleet'.tr(),
              icon: Icons.local_shipping_outlined,
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const Mytrucks()),
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
              title: 'truckDocuments'.tr(),
              subtitle: 'documents_subtitle'.tr(),
              icon: Icons.local_shipping_outlined,
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TruckDocumentsPage(),
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
              title: 'my_chats'.tr(),
              subtitle: 'chat_with_drivers'.tr(),
              icon: Icons.chat_bubble_outline,
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AgentChatListPage()),
              ),
            ),
            FeatureCard(
              title: 'bilty'.tr(),
              subtitle: 'createConsignmentNote'.tr(),
              icon: Icons.receipt_long,
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ShipmentSelectionPage(),),
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
              subtitle: 'view_history'.tr(),
              icon: Icons.feedback_outlined,
              color: Colors.red,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComplaintHistoryPage()),
              ),
            ),
          ],
        );
      },
    );
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
                builder: (_) => const ReportAnalysisPage(),
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
}