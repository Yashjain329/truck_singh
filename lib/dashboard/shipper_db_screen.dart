import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/features/trips/myTrips_history.dart';
import '../dashboard/widgets/feature_card.dart';
import '../features/complains/mycomplain.dart';
import '../features/shipment/shipper_form_page.dart';
import '../features/tracking/shared_shipments_page.dart';
import '../services/onesignal_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/chat_screen.dart';
import '../widgets/common/app_bar.dart';
import '../features/settings/presentation/screen/settings_page.dart';
import '../widgets/floating_chat_control.dart';

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();
      return response == null ? null : Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<Map<String, int>> getShipmentStats(String customUserId) async {
    try {
      final response = await _supabase
          .from('shipment')
          .select('booking_status')
          .eq('shipper_id', customUserId);
      int active = 0;
      int completed = 0;
      for (final row in response) {
        final status = row['booking_status'].toString().toLowerCase();
        if (status == 'completed' || status == 'cancelled') {
          completed++;
        } else {
          active++;
        }
      }
      return {'activeLoads': active, 'completedLoads': completed};
    } catch (e) {
      debugPrint('Error fetching shipment stats: $e');
      return {'activeLoads': 0, 'completedLoads': 0};
    }
  }
}

class ShipperDashboard extends StatefulWidget {
  const ShipperDashboard({super.key});

  @override
  State<ShipperDashboard> createState() => _ShipperDashboardState();
}

class _ShipperDashboardState extends State<ShipperDashboard> {
  final UserService _userService = UserService();

  Map<String, dynamic>? userProfile;
  Map<String, int> shipmentStats = const {'activeLoads': 0, 'completedLoads': 0};
  bool isLoading = true;
  bool isLoadingStats = true;
  final Map<String, dynamic> staticData = const {
    'totalCustomers': 48,
    'monthlyCommission': 45750.00,
    'pendingPayments': 12350.00,
    'networkPartners': 35,
    'marketRating': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    initializeOneSignalAndStorePlayerId();
  }

  Future<void> _loadUserProfile() async {
    final profile = await _userService.getUserProfile();
    if (!mounted) return;
    setState(() {
      userProfile = profile;
      isLoading = false;
    });
    if (profile != null && profile['custom_user_id'] != null) {
      await _loadShipmentStats(profile['custom_user_id']);
    }
  }

  Future<void> _loadShipmentStats(String customUserId) async {
    final stats = await _userService.getShipmentStats(customUserId);
    if (!mounted) return;
    setState(() {
      shipmentStats = stats;
      isLoadingStats = false;
    });
  }

  Future<void> _handleRefresh() async {
    await _loadUserProfile();
    if (userProfile != null && userProfile!['custom_user_id'] != null) {
      await _loadShipmentStats(userProfile!['custom_user_id']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
        RefreshIndicator(
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildPerformanceOverviewCard(),
              const SizedBox(height: 20),
              _buildFeatureGrid(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
          Positioned(
            bottom: 10,
            right: 12,
            child: FloatingChatControl(
              onOpenChat: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      onNavigate: (s) {
                        // openScreen(s, context, {});
                        Navigator.of(context).pushNamed('/$s');
                      },
                    ),
                  ),
                );
              },
              listening: false,
            ),
          ),
      ]
      )
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return CustomAppBar(
      showProfile: true,
      showNotifications: true,
      showMessages: false,
      userProfile: userProfile,
      isLoading: isLoading,
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
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
          colors: [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'performanceOverview'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${staticData['marketRating']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: isLoadingStats
                    ? _buildLoadingOverviewItem(
                  'activeLoads'.tr(),
                  Icons.local_shipping,
                )
                    : _buildOverviewItem(
                  'activeLoads'.tr(),
                  '${shipmentStats['activeLoads']}',
                  Icons.local_shipping,
                ),
              ),
              Expanded(
                child: isLoadingStats
                    ? _buildLoadingOverviewItem(
                  'completed'.tr(),
                  Icons.check_circle,
                )
                    : _buildOverviewItem(
                  'completed'.tr(),
                  '${shipmentStats['completedLoads']}',
                  Icons.check_circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverviewItem(String label, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
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
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
          title: 'create_shipment'.tr(),
          subtitle: 'post_new_load_request'.tr(),
          icon: Icons.add_box_rounded,
          color: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ShipperFormPage()),
          ),
        ),
        FeatureCard(
          title: 'sharedtrips'.tr(),
          subtitle: 'sharedtracking'.tr(),
          icon: Icons.share_location,
          color: Colors.orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SharedShipmentsPage()),
          ),
        ),
        FeatureCard(
          title: 'complaints'.tr(),
          subtitle: 'my_complaints'.tr(),
          icon: Icons.feedback_outlined,
          color: Colors.deepOrange,
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ComplaintHistoryPage())),
        ),
        FeatureCard(
          title: 'invoice'.tr(),
          subtitle: 'request_invoice'.tr(),
          icon: Icons.receipt_long,
          color: Colors.blue,
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => MyTripsHistory())),
        ),
      ],
    );
  }
}