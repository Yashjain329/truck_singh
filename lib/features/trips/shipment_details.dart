import 'dart:async';
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/features/auth/services/supabase_service.dart';
import 'package:logistics_toolkit/features/complains/complain_screen.dart';
import '../ratings/presentation/screen/rating.dart';
import '../tracking/shipment_tracking_page.dart';
import '../notifications/notification_service.dart';

class ShipmentDetailsPage extends StatefulWidget {
  final Map<String, dynamic> shipment;

  const ShipmentDetailsPage({super.key, required this.shipment});

  @override
  State<ShipmentDetailsPage> createState() => _ShipmentDetailsPageState();
}

class _ShipmentDetailsPageState extends State<ShipmentDetailsPage>
    with TickerProviderStateMixin {
  Timer? _trackingTimer;
  LatLng? _currentLocation;
  Map<String, int> ratingEditCount = {};

  late String currentUserCustomId;
  bool isFetchingUserId = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startLiveTracking();
    _fetchCurrentUserCustomId();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Fetches the current user's custom ID to determine permissions (e.g., sharing).
  Future<void> _fetchCurrentUserCustomId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => isFetchingUserId = true);

    try {
      final userId = user.id;
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id:: text', userId)
          .maybeSingle();

      if (response != null) {
        currentUserCustomId = (response['custom_user_id'] as String?)!;
      }
    } catch (e) {
      debugPrint('Error fetching user ID: $e');
    }

    if (mounted) {
      setState(() => isFetchingUserId = false);
    }
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  /// Simulates live tracking updates for demonstration purposes.
  void _startLiveTracking() {
    _trackingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_currentLocation != null) {
        double newLat =
            _currentLocation!.latitude + (Random().nextDouble() - 0.5) * 0.001;
        double newLng =
            _currentLocation!.longitude + (Random().nextDouble() - 0.5) * 0.001;

        if (mounted) {
          setState(() {
            _currentLocation = LatLng(newLat, newLng);
          });
        }
      }
    });
  }

  /// Checks if the current user is allowed to share tracking (Shipper or Agent).
  bool get canShareTracking {
    if (isFetchingUserId) return false;
    if (widget.shipment['booking_status'] == 'Completed') return false;

    final shipperId = widget.shipment['shipper_id'] ?? '';
    final assignedAgent = widget.shipment['assigned_agent'] ?? '';

    return currentUserCustomId == shipperId ||
        currentUserCustomId == assignedAgent;
  }

  bool get canFileComplaint {
    final status = widget.shipment['booking_status'];
    if (status != 'Completed') {
      return true;
    }

    final deliveryDateStr = widget.shipment['delivery_date'];
    final deliveryDate = DateTime.tryParse(deliveryDateStr ?? '');

    if (deliveryDate == null) {
      return false;
    }

    return DateTime.now().difference(deliveryDate).inDays <= 7;
  }

  String getFormattedDate(String? dateStr) {
    final date = DateTime.tryParse(dateStr ?? '') ?? DateTime.now();
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'en route to pickup':
      case 'arrived at pickup':
      case 'loading':
      case 'picked up':
      case 'in transit':
      case 'arrived at drop':
      case 'unloading':
        return Colors.purple;
      case 'delivered':
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
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

  /// Sends in-app and push notifications to both the sender (confirmation) and the receiver.
  Future<void> _sendShareNotifications(
    String recipientInput,
    String shipmentId,
  ) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    // 1. Notify Sender (Self) - Confirmation
    await NotificationService.sendNotification(
      recipientUserId: currentUser.id,
      title: 'Tracking Shared',
      message:
          'You successfully shared tracking for shipment $shipmentId with $recipientInput.',
      data: {'type': 'tracking_share_sent', 'shipment_id': shipmentId},
    );

    // 2. Notify Receiver
    try {
      // Resolve Recipient UUID from user_profiles based on input (ID, Mobile, or Name)
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('user_id, name')
          .or(
            'custom_user_id.eq.$recipientInput,mobile_number.eq.$recipientInput,name.eq.$recipientInput',
          )
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final recipientUuid = response['user_id'] as String;

        // Get Sender Name for the message
        final senderProfile = await Supabase.instance.client
            .from('user_profiles')
            .select('name')
            .eq('user_id', currentUser.id)
            .maybeSingle();
        final senderName = senderProfile?['name'] ?? 'A user';

        await NotificationService.sendNotification(
          recipientUserId: recipientUuid,
          title: 'Shipment Tracking Shared',
          message:
              '$senderName shared tracking for shipment $shipmentId with you.',
          data: {'type': 'tracking_share_received', 'shipment_id': shipmentId},
        );
      } else {
        debugPrint(
          'Could not resolve recipient UUID for notification: $recipientInput',
        );
      }
    } catch (e) {
      debugPrint('Error sending share notification to recipient: $e');
    }
  }

  /// Displays dialog to input recipient details and shares the shipment.
  Future<void> _showShareTrackingDialog() async {
    final formKey = GlobalKey<FormState>();
    final recipientController = TextEditingController();
    bool isSharing = false;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('share_tracking'.tr()),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text("enter_sharing_detail".tr()),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: recipientController,
                        decoration: InputDecoration(
                          labelText: 'search_user'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter an identifier.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('cancel'.tr()),
                ),
                ElevatedButton.icon(
                  icon: isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share),
                  label: Text('share'.tr()),
                  onPressed: isSharing
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          final recipient = recipientController.text.trim();

                          // Constraint: Prevent sharing with Drivers (IDs starting with DRV)
                          if (recipient.toUpperCase().startsWith('DRV')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Warning: You cannot share tracking with a driver.',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          // Constraint: Prevent sharing with self
                          if (recipient == currentUserCustomId) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'You cannot share tracking with yourself',
                                ),
                              ),
                            );
                            return;
                          }

                          setStateDialog(() => isSharing = true);

                          try {
                            final String? sharerId =
                                await SupabaseService.getCustomUserId(
                                  Supabase.instance.client.auth.currentUser!.id,
                                );

                            if (sharerId == null) {
                              throw Exception(
                                "Could not get the current user's ID.",
                              );
                            }

                            // Invoke RPC to share shipment
                            final response = await Supabase.instance.client.rpc(
                              'share_shipment_track',
                              params: {
                                'p_shipment_id': widget.shipment['shipment_id'],
                                'p_sharer_user_id': sharerId,
                                'p_recipient_identifier': recipient,
                              },
                            );

                            final status = response['status'];
                            final message = response['message'];

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: status == 'success'
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              );
                              if (status == 'success') {
                                Navigator.of(context).pop();
                                // Send notifications after successful share
                                await _sendShareNotifications(
                                  recipient,
                                  widget.shipment['shipment_id'],
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'An error occurred: ${e.toString()}',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            setStateDialog(() => isSharing = false);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('shipmentDetails'.tr()),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header: Status Card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      getStatusColor(widget.shipment['booking_status']),
                      getStatusColor(
                        widget.shipment['booking_status'],
                      ).withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: getStatusColor(
                        widget.shipment['booking_status'],
                      ).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Icon(
                                getStatusIcon(
                                  widget.shipment['booking_status'],
                                ),
                                size: 32,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.shipment['booking_status'] ??
                                    'unknown'.tr(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${'shipmentID'.tr()}: ${widget.shipment['shipment_id']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Live Tracking Button
              if (widget.shipment['booking_status'] != 'Completed')
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ShipmentTrackingPage(
                          shipmentId: widget.shipment['shipment_id'],
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'liveTracking'.tr(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.touch_app,
                                color: Colors.grey[600],
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'tapToOpenLiveTracking'.tr(),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Info Section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'shipmentInformation'.tr(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildInfoRow(
                      Icons.location_on,
                      'pickupLocation'.tr(),
                      widget.shipment['pickup'] ?? 'nA'.tr(),
                    ),
                    _buildInfoRow(
                      Icons.place,
                      'dropLocation'.tr(),
                      widget.shipment['drop'] ?? 'nA'.tr(),
                    ),
                    _buildInfoRow(
                      Icons.calendar_today,
                      'pickupDate'.tr(),
                      getFormattedDate(widget.shipment['created_at']),
                    ),
                    _buildInfoRow(
                      Icons.calendar_today,
                      'deliveryDate'.tr(),
                      getFormattedDate(widget.shipment['delivery_date']),
                    ),
                    _buildInfoRow(
                      Icons.access_time,
                      'pickupTime'.tr(),
                      widget.shipment['pickup_time'] ?? 'nA'.tr(),
                    ),

                    if (!isFetchingUserId &&
                        widget.shipment['shipper_id'] != null)
                      _buildInfoRow(
                        Icons.person_add,
                        'created'.tr(),
                        (widget.shipment['shipper_id'] == currentUserCustomId)
                            ? 'You'
                            : (widget.shipment['shipper_name'] ??
                                  widget.shipment['shipper_id']),
                      ),

                    if (widget.shipment['assigned_company'] != null)
                      _buildInfoRow(
                        Icons.business,
                        'assignedCompany'.tr(),
                        widget.shipment['assigned_company'],
                      ),
                    // Display Agent OR Truck Owner as the assigned manager
                    if (widget.shipment['assigned_agent'] != null &&
                        widget.shipment['assigned_agent']
                            .toString()
                            .trim()
                            .isNotEmpty)
                      _buildInfoRow(
                        Icons.person,
                        'assignedAgent'.tr(),
                        widget.shipment['assigned_agent'],
                      )
                    else if (widget.shipment['assigned_truckowner'] != null &&
                        widget.shipment['assigned_truckowner']
                            .toString()
                            .trim()
                            .isNotEmpty)
                      _buildInfoRow(
                        Icons.person,
                        'assignedAgent'.tr(),
                        widget.shipment['assigned_truckowner'],
                      ),

                    if (widget.shipment['assigned_driver'] != null)
                      _buildInfoRow(
                        Icons.drive_eta,
                        'assignedDriver'.tr(),
                        widget.shipment['assigned_driver'],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons Section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Share Tracking Button
                    if (canShareTracking)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.share),
                          label: Text('share_tracking'.tr()),
                          onPressed: _showShareTrackingDialog,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Complaint Button
                    if (canFileComplaint) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.report_problem),
                          label: Text('fileAComplaint'.tr()),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ComplaintPage(
                                  preFilledShipmentId:
                                      widget.shipment['shipment_id'],
                                  editMode: false,
                                  complaintData: const {},
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.star),
                          label: Text(
                            'rateThisShipment'.tr(),
                            style: const TextStyle(fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => Rating(
                                  shipmentId: widget.shipment['shipment_id'],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
