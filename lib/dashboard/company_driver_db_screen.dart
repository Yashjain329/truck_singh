import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:logistics_toolkit/features/blank.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/settings_page.dart';
import 'package:logistics_toolkit/widgets/common/app_bar.dart';
import 'package:permission_handler/permission_handler.dart' as handler;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../features/chat/driver_chat_list_page.dart';
import '../features/complains/mycomplain.dart';
import '../features/driver_status/driver_status_changer.dart';
import '../features/driver_documents/driver_documents_page.dart';
import '../features/truck_documents/truck_documents_page.dart';
import '../features/notifications/real_time_notification_service.dart';
import '../features/sos/company_driver_sos.dart';
import '../features/trips/myTrips_history.dart';
import '../services/driver/background_location_service.dart';
import '../services/onesignal_notification_service.dart';
import '../features/auth/services/supabase_service.dart';
import 'package:easy_localization/easy_localization.dart';

class CompanyDriverDb extends StatefulWidget {
  const CompanyDriverDb({Key? key}) : super(key: key);

  @override
  State<CompanyDriverDb> createState() => _CompanyDriverDbState();
}

class _CompanyDriverDbState extends State<CompanyDriverDb> {
  final SupabaseClient supabase = Supabase.instance.client;
  // State for User Profile
  Map<String, dynamic>? userProfile;
  bool isLoading = true;
  // State for Live Tracking
  bool _isTrackingEnabled = false;

  // State for Current Shipment
  Map<String, dynamic>? _activeShipment;
  bool _isShipmentLoading = true;
  RealtimeChannel? _shipmentChannel;

  // State for Notifications
  final RealTimeNotificationService _notificationService =
  RealTimeNotificationService();
  StreamSubscription? _notificationSubscription;
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _notificationService.dispose();
    if (_shipmentChannel != null) {
      Supabase.instance.client.removeChannel(_shipmentChannel!);
    }
    super.dispose();
  }

  Future<void> _initializeDashboard() async {
    await BackgroundLocationService.initializeService();
    // Services are initialized in main.dart, so we just load page data
    await _loadPageData();
    // NEW: Initialize OneSignal after the page data is loaded
    initializeOneSignalAndStorePlayerIddriver();
  }

  Future<void> _loadPageData() async {
    await Future.wait([_loadUserProfile(), _checkInitialTrackingStatus()]);
  }

  Future<void> _handleRefresh() async {
    // Re-fetch all the data for the dashboard
    await Future.wait([_loadUserProfile(), _fetchUnreadCount()]);
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      final response = await supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', user.id)
          .single();

      return response;
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  Future<void> _loadUserProfile() async {
    final profile = await getUserProfile();
    setState(() {
      userProfile = profile;
      isLoading = false;
    });

    await _fetchActiveShipment();
    _startNotificationListener(supabase.auth.currentUser?.id ?? '');
    _subscribeToShipmentChanges();
  }

  void _startNotificationListener(String userId) {
    _notificationService.startListening(userId);
    _notificationSubscription = _notificationService.notificationStream.listen((
        _,
        ) {
      _fetchUnreadCount();
    });
    _fetchUnreadCount();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final user = SupabaseService.getCurrentUser();
      if (user == null) return;
      final count = await SupabaseService.client
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', user.id)
          .eq('read', false);

      if (mounted) {
        setState(() => unreadCount = count);
      }
    } catch (e) {
      print("Error fetching unread notification count: $e");
    }
  }

  Future<void> _fetchActiveShipment() async {
    final userCustomId = userProfile?['custom_user_id'];
    if (userCustomId == null) {
      if (mounted) setState(() => _isShipmentLoading = false);
      return;
    }
    if (!_isShipmentLoading) setState(() => _isShipmentLoading = true);
    try {
      final response = await SupabaseService.client
          .from('shipment')
          .select()
          .eq('assigned_driver', userCustomId)
      // FIXED: Use the correct filter syntax for your package version
          .neq('booking_status','Completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _activeShipment = response;
          _isShipmentLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isShipmentLoading = false);
        _showErrorSnackBar("error_fetch_active_shipment.".tr());
      }
    }
  }

  void _subscribeToShipmentChanges() {
    final userCustomId = userProfile?['custom_user_id'];
    if (userCustomId == null) return;

    _shipmentChannel = Supabase.instance.client
        .channel('public:shipment')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'shipment',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'assigned_driver',
        value: userCustomId,
      ),
      callback: (payload) {
        print("Shipment change detected, refetching...");
        _fetchActiveShipment();
      },
    )
        .subscribe();
  }

  Future<void> _checkInitialTrackingStatus() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (mounted) {
      setState(() => _isTrackingEnabled = isRunning);
    }
  }

  Future<void> _toggleTracking(bool value) async {
    if (value) {
      final hasPermission = await _handleLocationPermission();
      if (!hasPermission) return;
      await BackgroundLocationService.startService();
      _showSnackBar("Live tracking service started.");
    } else {
      BackgroundLocationService.stopService();
      _showSnackBar("Live tracking service stopped.");
    }
    if (mounted) {
      setState(() => _isTrackingEnabled = value);
    }
  }

  Future<bool> _handleLocationPermission() async {
    // 1. Request Notification permission FIRST.
    if (await handler.Permission.notification.request().isDenied) {
      _showErrorSnackBar(
        "Notification permission is required for the tracking service.",
      );
      return false;
    }
    // 2. Check if the device's location services are enabled.
    if (await handler.Permission.location.serviceStatus.isDisabled) {
      _showErrorSnackBar(
        "Please enable location services in your device settings.",
      );
      await handler.openAppSettings();
      return false;
    }

    // 3. Request "While in Use" location permission.
    var status = await handler.Permission.location.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      _showErrorSnackBar("Location permission is required to start tracking.");
      await handler.openAppSettings();
      return false;
    }

    // 4. Request "Always" location permission for background tracking.
    if (await handler.Permission.locationAlways.isDenied) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("background_location_required_title".tr()),
            content: Text("background_location_required_message".tr()),
            actions: [
              TextButton(
                child: Text("cancel".tr()),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: Text("go_to_settings".tr()),
                onPressed: () {
                  handler.openAppSettings();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      }
      return false;
    }

    // 5. If we reach here, all permissions are granted.
    return true;
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  int _getCrossAxisCount(double width) {
    if (width < 600) {
      return 2; // Phones
    } else if (width < 1024) {
      return 3; // Tablets
    } else {
      return 4; // Large screens
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      children: [
                        _buildCurrentTripCard(),
                        const SizedBox(height: 20),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: _getCrossAxisCount(
                            constraints.maxWidth,
                          ),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.0,
                          children: [
                            _buildFeatureCard(
                              title: 'shipments_title'.tr(),
                              subtitle: 'shipments_subtitle'.tr(),
                              icon: Icons.local_shipping_outlined,
                              color: AppColors.orange,
                              onTap: () {
                                final userCustomId =
                                userProfile?['custom_user_id'];
                                if (userCustomId != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DriverStatusChanger(
                                        driverId: userCustomId,
                                      ),
                                    ),
                                  );
                                } else {
                                  _showErrorSnackBar(
                                    "driver_id_not_loaded".tr(),
                                  );
                                }
                              },
                            ),
                            _buildFeatureCard(
                              title: 'my_trips_title'.tr(),
                              subtitle: 'my_trips_subtitle'.tr(),
                              icon: Icons.route_outlined,
                              color: Colors.blue,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                    const MyTripsHistory(),
                                  ),
                                );
                              },
                            ),
                            _buildFeatureCard(
                              title: 'documents_title'.tr(),
                              subtitle: 'documents_subtitle'.tr(),
                              icon: Icons.person_outline,
                              color: Colors.green,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                    const DriverDocumentsPage(),
                                  ),
                                );
                              },
                            ),
                            _buildFeatureCard(
                              title: 'truckDocuments'.tr(),
                              subtitle: 'documents_subtitle'.tr(),
                              icon: Icons.local_shipping_outlined,
                              color: Colors.blue,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                    const TruckDocumentsPage(),
                                  ),
                                );
                              },
                            ),
                            _buildFeatureCard(
                              title: 'complaints_title'.tr(),
                              subtitle: 'complaints_subtitle'.tr(),
                              icon: Icons.report_problem_outlined,
                              color: Colors.amber,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                    const ComplaintHistoryPage(),
                                  ),
                                );
                              },
                            ),
                            _buildFeatureCard(
                              title: 'sos_title'.tr(),
                              subtitle: 'sos_subtitle'.tr(),
                              icon: Icons.sos_outlined,
                              color: Colors.red,
                              onTap: () {
                                // --- START CORRECT CODE ---
                                // Check if there's an active shipment loaded
                                if (_activeShipment == null) {
                                  _showErrorSnackBar("You are not on an active shipment."); // Correct error message
                                  return;
                                }
                                // Get the AGENT ID from the active shipment
                                final agentId = _activeShipment!['assigned_agent'];

                                if (agentId != null && agentId.isNotEmpty) {
                                  // Navigate and pass the AGENT ID
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CompanyDriverEmergencyScreen(
                                        agentId: agentId, // Pass agentId correctly
                                      ),
                                    ),
                                  );
                                } else {
                                  // Show error if no agent is assigned to the shipment
                                  _showErrorSnackBar("No agent assigned to the current shipment."); // Correct error message
                                }
                                // --- END CORRECT CODE ---
                              },
                            ),
                            _buildFeatureCard(
                              title: 'My Chats',
                              subtitle: 'View your Chats',
                              icon: Icons.chat_bubble_outline,
                              color: Colors.blue,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                    const DriverChatListPage()),
                              ),
                            ),
                            _buildFeatureCard(
                              title: 'My Ratings',
                              subtitle: 'View Ratings',
                              icon: Icons.star_border_outlined,
                              color: Colors.orange,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                    const BlankPage()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTripCard() {
    if (_isShipmentLoading) {
      return SizedBox(
        height: 150,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_activeShipment == null) {
      return Container(
        width: double.infinity,
        height: 150,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            "no_active_trip".tr(),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.teal, AppColors.teal.withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.radio_button_checked,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'live_tracking'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Switch(
                value: _isTrackingEnabled,
                onChanged: _toggleTracking,
                activeTrackColor: AppColors.orange.withOpacity(0.5),
                activeColor: Colors.white,
                inactiveThumbColor: Colors.white60,
                inactiveTrackColor: Colors.black26,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_activeShipment!['pickup'] ?? 'Origin'} → ${_activeShipment!['drop'] ?? 'Destination'}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${_activeShipment!['shipment_id'] ?? 'N/A'} • Status: ${_activeShipment!['booking_status'] ?? 'N/A'}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return CustomAppBar(
      showProfile: true,
      showNotifications: true,
      showMessages: true, // may change later
      userProfile: userProfile,
      isLoading: isLoading,
      shipment: _activeShipment,
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SettingsPage()),
        );
      },
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 14), // Reduced from 16 to 14
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2), // Reduced from 4 to 2
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}