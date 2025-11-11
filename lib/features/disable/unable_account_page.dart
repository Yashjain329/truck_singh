import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../config/theme.dart';
import 'otp_activation_service.dart';
import 'otp_verification_page.dart';
import 'account_reactivation_service.dart';

class UnableAccountPage extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const UnableAccountPage({super.key, required this.userProfile});

  @override
  State<UnableAccountPage> createState() => _UnableAccountPageState();
}

class _UnableAccountPageState extends State<UnableAccountPage> {
  final supabase = Supabase.instance.client;
  bool _isSendingOtp = false;
  bool _isRequestingAccess = false;
  bool _isCheckingRelation = true;

  // Variables for disable/enable logic
  Map<String, dynamic>? _disableInfo;
  bool _hasPendingRequest = false;

  @override
  void initState() {
    super.initState();
    // Debug: print('UnableAccountPage initialized with user profile: ${widget.userProfile}');
    _checkAccountDisableInfo();
  }

  String get userName => widget.userProfile['name'] ?? 'Unknown User';
  String get customUserId => widget.userProfile['custom_user_id'] ?? '';
  String get phoneNumber =>
      widget.userProfile['mobile_number'] ?? 'Not provided';
  String get email => widget.userProfile['email'] ?? 'Not provided';
  String get role => widget.userProfile['role'] ?? '';
  String? get profilePicture => widget.userProfile['profile_picture'];

  // Helper method to check if user is agent or truck owner
  bool _isAgentOrTruckOwner() {
    return role == 'agent' || role == 'truckowner';
  }

  // Helper method to determine if request activation should be used
  bool _shouldUseRequestActivation() {
    // Check if account was disabled by an admin/agent (not self-disabled)
    if (_disableInfo != null && _disableInfo!['is_self_disabled'] == false) {
      return true; // Use request access flow
    }
    // Otherwise use OTP flow (self-disabled or no disable info)
    return false;
  }

  String get formattedRole {
    switch (role) {
      case 'driver_individual':
        return 'Individual Driver';
      case 'driver_company':
        return 'Company Driver';
      case 'truckowner':
        return 'Truck Owner';
      case 'agent':
        return 'Agent';
      case 'shipper':
        return 'Shipper';
      case 'fleet_manager':
        return 'Fleet Manager';
      default:
        return role.toUpperCase();
    }
  }

  /// Check who disabled the account and determine the appropriate reactivation method
  Future<void> _checkAccountDisableInfo() async {
    try {
      if (customUserId.isEmpty) {
        if (mounted) {
          setState(() {
            _isCheckingRelation = false;
          });
        }
        return;
      }

      // Get disable info from the new service
      final disableInfo =
      await AccountReactivationService.getAccountDisableInfo(
        customUserId: customUserId,
      );

      // Check for pending reactivation request
      final hasPending =
      await AccountReactivationService.hasPendingReactivationRequest(
        customUserId: customUserId,
      );

      if (mounted) {
        setState(() {
          _disableInfo = disableInfo;
          _hasPendingRequest = hasPending;
          _isCheckingRelation = false;

          // Debug logging
          print('🔍 Disable Info: $_disableInfo');
          print(
            '🔍 Should use request activation: ${_shouldUseRequestActivation()}',
          );
        });
      }
    } catch (e) {
      print('Error checking account disable info: $e');
      if (mounted) {
        setState(() {
          _isCheckingRelation = false;
        });
      }
    }
  }

  Future<void> _requestAccessFromOwner() async {
    if (_isRequestingAccess) return;

    final disablerId = _disableInfo?['disabled_by'] as String?;
    if (disablerId == null) return;

    // Show dialog to get the request message
    final messageController = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.message, color: AppColors.teal),
              const SizedBox(width: 12),
              const Text('Request Access'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send a message to ${_disableInfo?['disabler_name'] ?? 'the admin'} explaining why you want to reactivate your account:',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: messageController,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Type your message here...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (messageController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a message'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(messageController.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Send Request'),
            ),
          ],
        );
      },
    );

    // If user cancelled, return
    if (message == null) return;

    setState(() {
      _isRequestingAccess = true;
    });

    try {
      // Use the new service to send reactivation request
      final result = await AccountReactivationService.sendReactivationRequest(
        requesterId: customUserId,
        requesterName: userName,
        disablerId: disablerId,
        requestMessage: message,
      );

      if (!mounted) return;

      if (result['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request sent to ${result['disabler_name']} successfully',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Refresh to show pending status
        setState(() {
          _hasPendingRequest = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to send request'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending request: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingAccess = false;
        });
      }
    }
  }

  Future<void> _sendOtpForSelfActivation() async {
    if (_isSendingOtp) return;

    setState(() {
      _isSendingOtp = true;
    });

    try {
      // Use email for OTP (simplified approach)
      if (email == 'Not provided' || !email.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No valid email found in your profile. Please contact support.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      print('Sending OTP to email from user_profiles: $email');

      // Send OTP using our service
      final result = await OtpActivationService.sendActivationOtp(email: email);

      if (!mounted) return;

      if (result['ok'] == true) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Activation OTP sent to $email'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate to OTP verification page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OtpVerificationPage(
              email: email,
              phoneNumber: phoneNumber,
              customUserId: customUserId,
              isEmail: true,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send OTP: ${result['error']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending OTP: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingOtp = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await OtpActivationService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error signing out: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Account Disabled'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Status Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.block, size: 60, color: Colors.red.shade700),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Account Disabled',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                'Your account has been disabled. Please contact your administrator or request activation below.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Profile Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Profile Picture
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: AppColors.teal.withOpacity(0.1),
                        backgroundImage:
                        profilePicture != null && profilePicture!.isNotEmpty
                            ? NetworkImage(profilePicture!)
                            : null,
                        child: profilePicture == null || profilePicture!.isEmpty
                            ? const Icon(
                          Icons.person,
                          size: 50,
                          color: AppColors.teal,
                        )
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // User Details
                      _buildDetailRow('Name', userName),
                      _buildDetailRow('User ID', customUserId),
                      _buildDetailRow('Phone', phoneNumber),
                      _buildDetailRow('Email', email),
                      _buildDetailRow('Role', formattedRole),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Conditional Activation Section
              if (_isCheckingRelation)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Checking account status...'),
                    ],
                  ),
                )
              else if (_shouldUseRequestActivation())
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _hasPendingRequest
                        ? Colors.blue.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hasPendingRequest
                          ? Colors.blue.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _hasPendingRequest
                            ? Icons.hourglass_empty
                            : Icons.supervisor_account,
                        color: _hasPendingRequest
                            ? Colors.blue.shade600
                            : Colors.orange.shade600,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _hasPendingRequest
                            ? 'Request Pending'
                            : 'Request Account Activation',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _hasPendingRequest
                              ? Colors.blue.shade800
                              : Colors.orange.shade800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hasPendingRequest
                            ? 'Your reactivation request has been sent to ${_disableInfo?['disabler_name'] ?? 'the admin'}. Please wait for their approval.'
                            : 'Your account was disabled by ${_disableInfo?['disabler_name'] ?? 'an admin'}. Send them a request to reactivate your account.',
                        style: TextStyle(
                          color: _hasPendingRequest
                              ? Colors.blue.shade700
                              : Colors.orange.shade700,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_disableInfo != null && !_hasPendingRequest) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Disabled by: ${_disableInfo!['disabler_name']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Role: ${_disableInfo!['disabler_role']?.toString().toUpperCase()}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              if (_disableInfo!['reason'] != null)
                                Text(
                                  'Reason: ${_disableInfo!['reason']}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.security,
                        color: Colors.blue.shade600,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Activate Your Account',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isAgentOrTruckOwner()
                            ? 'Verify your email address to reactivate your account.'
                            : 'Verify your email address to activate your account and start using the app.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Conditional Action Button
              if (!_isCheckingRelation)
                SizedBox(
                  width: double.infinity,
                  child: _shouldUseRequestActivation()
                      ? ElevatedButton.icon(
                    onPressed: (_isRequestingAccess || _hasPendingRequest)
                        ? null
                        : _requestAccessFromOwner,
                    icon: _isRequestingAccess
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                        : Icon(
                      _hasPendingRequest
                          ? Icons.check_circle
                          : Icons.send,
                    ),
                    label: Text(
                      _isRequestingAccess
                          ? 'Sending Request...'
                          : _hasPendingRequest
                          ? 'Request Sent - Waiting for Approval'
                          : 'Request Access',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasPendingRequest
                          ? Colors.blue.shade600
                          : Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                      : ElevatedButton.icon(
                    onPressed: _isSendingOtp
                        ? null
                        : _sendOtpForSelfActivation,
                    icon: _isSendingOtp
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                        : const Icon(Icons.verified_user),
                    label: Text(
                      _isSendingOtp
                          ? 'Sending OTP...'
                          : _isAgentOrTruckOwner()
                          ? 'Send OTP & Reactivate'
                          : 'Send OTP & Activate',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Sign Out Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Help Text
              Text(
                'Need immediate assistance? Contact support at:\nsupport@logisticapp.com',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }
}