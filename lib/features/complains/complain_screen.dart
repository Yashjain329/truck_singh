import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class ComplaintPage extends StatefulWidget {
  final bool editMode;
  final String? preFilledShipmentId;
  final Map<String, dynamic> complaintData;

  const ComplaintPage({
    super.key,
    required this.editMode,
    this.preFilledShipmentId,
    required this.complaintData,
  });

  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _complaintController = TextEditingController();
  final _recipientIdController = TextEditingController();

  Map<String, dynamic>? _senderProfile;
  Map<String, dynamic>? _recipientProfile;
  Map<String, dynamic>? _shipmentDetails;
  Map<String, String?> _cachedAssignedUsers = {};
  String? _shipmentCreatorRole;
  String? _shipmentCreatorId;

  String? _selectedRecipientRole;
  final List<String> _recipientRoles = [
    'Driver',
    'Shipper',
    'Agent',
    'Truck Owner',
  ];
  List<String> get _filteredRecipientRoles {
    if (_senderProfile == null) return _recipientRoles;

    final senderRole = _senderProfile!['role'] as String?;
    final senderCustomId = _senderProfile!['custom_user_id'] as String?;
    final rolesWithAssignee = _recipientRoles.where((role) {
      final id = _cachedAssignedUsers[role];
      return id != null && id.isNotEmpty;
    }).toList();

    if (rolesWithAssignee.isEmpty) {
      return _recipientRoles;
    }
    String? senderDisplayRole;
    if (senderRole != null) {
      final lower = senderRole.toLowerCase();
      if (lower.contains('driver')) {
        senderDisplayRole = 'Driver';
      } else if (lower.contains('shipper')) {
        senderDisplayRole = 'Shipper';
      } else if (lower.contains('agent')) {
        senderDisplayRole = 'Agent';
      } else if (lower.contains('truckowner')) {
        senderDisplayRole = 'Truck Owner';
      }
    }
    List<String> baseFiltered = rolesWithAssignee;
    if (senderDisplayRole != null) {
      baseFiltered =
          baseFiltered.where((role) => role != senderDisplayRole).toList();
    }
    final creatorRole = _shipmentCreatorRole;
    final creatorId = _shipmentCreatorId;

    final isCreator =
        creatorId != null && senderCustomId != null && creatorId == senderCustomId;

    final isCreatorAgent = creatorRole != null && creatorRole.contains('agent');
    final isCreatorTruckOwner =
        creatorRole != null && creatorRole.contains('truckowner');

    if (isCreator && (isCreatorAgent || isCreatorTruckOwner)) {
      return baseFiltered.where((r) => r == 'Driver').toList();
    }
    return baseFiltered;
  }

  final List<String> _preBuiltSubjects = [
    'Delivery Delay',
    'Package Damaged',
    'Driver Behavior',
    'Billing Issue',
    'Other',
  ];

  String? _selectedSubject;
  bool _showCustomSubject = false;
  XFile? _pickedFile;
  Timer? _debounce;

  bool _isLoading = false;
  bool _isFetchingSender = true;
  bool _isVerifyingRecipient = false;
  // Loading state for the shipment fetch
  bool _isFetchingShipment = false;

  @override
  void initState() {
    super.initState();
    _fetchSenderProfile();
    if (widget.complaintData.isNotEmpty) {
      _shipmentDetails = widget.complaintData;
      _cacheAssignedUsers();
      _determineShipmentCreator();
    } else {
      _fetchShipmentDetails();
    }

    _recipientIdController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 750), () {
        if (_recipientIdController.text.isNotEmpty &&
            _selectedRecipientRole != null) {
          _verifyRecipientId(_recipientIdController.text);
        }
      });
    });
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _complaintController.dispose();
    _recipientIdController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // Check network connectivity before making API calls
  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Fetches shipment data for autofill
  Future<void> _fetchShipmentDetails() async {
    if (widget.preFilledShipmentId == null) return;

    setState(() => _isFetchingShipment = true);
    try {
      print('Fetching shipment details for ID: ${widget.preFilledShipmentId}');
      final data = await Supabase.instance.client
          .from('shipment')
          .select(
        'assigned_driver, assigned_agent, shipper_id, assigned_truckowner',
      )
          .eq('shipment_id', widget.preFilledShipmentId!)
          .single()
          .timeout(const Duration(seconds: 15));

      print('Shipment details fetched: $data');

      if (mounted) {
        setState(() {
          _shipmentDetails = data;
        });
        _cacheAssignedUsers();
        _determineShipmentCreator();
      }
    } catch (e) {
      print('ERROR in _fetchShipmentDetails: $e');
      if (e is PostgrestException) {
        print(
          'Supabase error: ${e.message}, Details: ${e.details}, Code: ${e.code}',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('shipment_fetch_error'.tr()),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'retry'.tr(),
              textColor: Colors.white,
              onPressed: () => _fetchShipmentDetails(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingShipment = false);
      }
    }
  }

  // NEW: Determine who actually created the shipment based on shipper_id
  Future<void> _determineShipmentCreator() async {
    if (_shipmentDetails == null) return;

    final shipperId = _shipmentDetails!['shipper_id']?.toString();
    if (shipperId == null || shipperId.isEmpty) return;

    try {
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('role, custom_user_id')
          .eq('custom_user_id', shipperId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (profile != null && mounted) {
        setState(() {
          _shipmentCreatorRole =
              (profile['role'] as String?)?.toLowerCase().trim();
          _shipmentCreatorId = profile['custom_user_id']?.toString() ?? shipperId;
        });

        print(
          'Shipment created by role: $_shipmentCreatorRole, id: $_shipmentCreatorId',
        );
      }
    } catch (e) {
      print('Error determining shipment creator: $e');
    }
  }

  // Cache assigned user IDs from shipment details
  void _cacheAssignedUsers() {
    if (_shipmentDetails == null) return;

    print('Caching assigned users from shipment details...');

    _cachedAssignedUsers = {
      'Driver': _shipmentDetails!['assigned_driver']?.toString(),
      'Agent': _shipmentDetails!['assigned_agent']?.toString(),
      'Truck Owner': _shipmentDetails!['assigned_truckowner']?.toString(),
      'Shipper': _shipmentDetails!['shipper_id']?.toString(),
    };

    print('Cached assigned users: $_cachedAssignedUsers');
  }

  // Auto-fills the recipient ID based on the selected role using cached data
  Future<void> _autofillRecipientId(String role) async {
    try {
      print('Auto-filling recipient ID for role: $role');

      final cachedUserId = _cachedAssignedUsers[role];
      if (cachedUserId != null && cachedUserId.isNotEmpty) {
        print('Found cached user ID: $cachedUserId for role: $role');

        // Fetch user profile from user_profiles table
        final response = await Supabase.instance.client
            .from('user_profiles')
            .select('custom_user_id, name, role')
            .eq('custom_user_id', cachedUserId)
            .single()
            .timeout(const Duration(seconds: 8));

        if (mounted) {
          setState(() {
            _recipientIdController.text = cachedUserId;
            _recipientProfile = response;
            print(
              'Auto-filled recipient: ${response['name']} '
                  '(${response['custom_user_id']})',
            );
          });
        }
      } else {
        print('No cached user ID found for role: $role');
        if (mounted) {
          setState(() {
            _recipientIdController.clear();
            _recipientProfile = null;
          });
        }
      }
    } catch (e) {
      print('Error auto-filling recipient ID for role $role: $e');
      if (e is PostgrestException) {
        print('Supabase error: ${e.message}, Details: ${e.details}');
      }
      if (mounted) {
        setState(() {
          _recipientIdController.clear();
          _recipientProfile = null;
        });
      }
    }
  }

  Future<void> _fetchSenderProfile() async {
    // Check connectivity first
    final hasConnection = await _checkConnectivity();
    if (!hasConnection) {
      if (mounted) {
        setState(() => _isFetchingSender = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('no_internet'.tr()),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'retry'.tr(),
              onPressed: () => _fetchSenderProfile(),
            ),
          ),
        );
      }
      return;
    }

    try {
      print('Fetching sender profile...');
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        print('ERROR: Not authenticated');
        throw Exception('Not authenticated');
      }

      print('User ID: ${user.id}');
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id, name, role')
          .eq('user_id', user.id)
          .single()
          .timeout(const Duration(seconds: 10));

      print(
        'Sender profile fetched: ${profile['name']} (${profile['custom_user_id']})',
      );

      if (mounted) {
        setState(() {
          _senderProfile = profile;
          _isFetchingSender = false;
        });
      }
    } catch (e) {
      print('ERROR in _fetchSenderProfile: $e');
      if (e is PostgrestException) {
        print(
          'Supabase error: ${e.message}, Details: ${e.details}, Code: ${e.code}',
        );
      }

      if (mounted) {
        setState(() => _isFetchingSender = false);
        String errorMessage = 'Error fetching your profile';
        if (e.toString().contains('TimeoutException')) {
          errorMessage =
          'Network timeout. Please check your connection and try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'retry'.tr(),
              textColor: Colors.white,
              onPressed: () => _fetchSenderProfile(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _verifyRecipientId(String id) async {
    if (id.isEmpty || _selectedRecipientRole == null) return;
    setState(() => _isVerifyingRecipient = true);

    try {
      // Check if user is trying to select themselves
      if (_senderProfile != null && id == _senderProfile!['custom_user_id']) {
        if (mounted) {
          setState(() {
            _recipientProfile = null;
            _isVerifyingRecipient = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('cannot_file_self'.tr()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      List<String> dbRoles = [];
      switch (_selectedRecipientRole) {
        case 'Driver':
          dbRoles = ['driver'];
          break;
        case 'Shipper':
          dbRoles = ['shipper'];
          break;
        case 'Agent':
          dbRoles = ['agent'];
          break;
        case 'Truck Owner':
          dbRoles = ['truckowner'];
          break;
      }

      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id, name')
          .eq('custom_user_id', id)
          .inFilter('role', dbRoles)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (mounted) {
        setState(() {
          _recipientProfile = profile;
          _isVerifyingRecipient = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recipientProfile = null;
          _isVerifyingRecipient = false;
        });

        if (e.toString().contains('TimeoutException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('network_timeout'.tr()),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;
    if (_recipientProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('verify_recipient'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_senderProfile != null && _recipientProfile != null) {
      if (_senderProfile!['custom_user_id'] ==
          _recipientProfile!['custom_user_id']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('cannot_file_self'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final finalSubject = _selectedSubject == 'Other'
          ? _subjectController.text.trim()
          : _selectedSubject!;

      String? attachmentUrl;
      if (_pickedFile != null) {
        final fileBytes = await _pickedFile!.readAsBytes();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${_pickedFile!.name}';
        final filePath = 'user_${user.id}/$fileName';
        await Supabase.instance.client.storage
            .from('complaint-attachments')
            .uploadBinary(filePath, fileBytes)
            .timeout(const Duration(seconds: 30));
        attachmentUrl = Supabase.instance.client.storage
            .from('complaint-attachments')
            .getPublicUrl(filePath);
      }

      final complaintData = {
        'user_id': user.id,
        'complainer_user_id': _senderProfile!['custom_user_id'],
        'complainer_user_name': _senderProfile!['name'],
        'target_user_id': _recipientProfile!['custom_user_id'],
        'target_user_name': _recipientProfile!['name'],
        'subject': finalSubject,
        'complaint': _complaintController.text.trim(),
        'status': 'Open',
        'attachment_url': attachmentUrl,
        'shipment_id': widget.preFilledShipmentId,
      };

      await Supabase.instance.client
          .from('complaints')
          .insert(complaintData)
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('complaint_submitted'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Error submitting complaint';
        if (e.toString().contains('TimeoutException')) {
          errorMessage =
          'Network timeout. Please check your connection and try again.';
        } else if (e.toString().contains('HandshakeException')) {
          errorMessage =
          'Connection failed. Please check your internet connection.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'retry'.tr(),
              textColor: Colors.white,
              onPressed: () => _submitComplaint(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (picked != null) {
      setState(() => _pickedFile = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('file_complaint'.tr()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isFetchingSender || _isFetchingShipment
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoCard('Sender (You)', _senderProfile),
                const SizedBox(height: 16),
                _buildRecipientCard(),
                const SizedBox(height: 16),
                _buildComplaintForm(),
                const SizedBox(height: 24),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, Map<String, dynamic>? profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            if (profile == null)
              Text(
                'could_not_load_profile_info'.tr(),
                style: const TextStyle(color: Colors.red),
              )
            else ...[
              Text(
                profile['name'] ?? 'N/A',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'ID: ${profile['custom_user_id'] ?? 'N/A'}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientCard() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'recipient_complain_against'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedRecipientRole,
              decoration: InputDecoration(
                labelText: 'select_recipient_role'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: _filteredRecipientRoles
                  .map(
                    (role) =>
                    DropdownMenuItem(value: role, child: Text(role)),
              )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedRecipientRole = value;
                  _recipientProfile = null;
                  _recipientIdController.clear();
                });
                _autofillRecipientId(value);
              },
              validator: (value) {
                if (value == null) return 'Please select a role';
                if (_senderProfile != null) {
                  final senderRole = _senderProfile!['role'] as String?;
                  if (senderRole != null) {
                    String? senderDisplayRole;
                    final lower = senderRole.toLowerCase();
                    if (lower.contains('driver')) {
                      senderDisplayRole = 'Driver';
                    } else if (lower.contains('shipper')) {
                      senderDisplayRole = 'Shipper';
                    } else if (lower.contains('agent')) {
                      senderDisplayRole = 'Agent';
                    } else if (lower.contains('truckowner')) {
                      senderDisplayRole = 'Truck Owner';
                    }

                    if (senderDisplayRole != null && value == senderDisplayRole) {
                      return 'You cannot file a complaint against yourself';
                    }
                  }
                }

                return null;
              },
            ),
            if (_selectedRecipientRole != null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _recipientIdController,
                decoration: InputDecoration(
                  labelText: 'enter_recipient_id'.tr(),
                  border: const OutlineInputBorder(),
                  suffixIcon: _isVerifyingRecipient
                      ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                      : (_recipientProfile != null
                      ? const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                  )
                      : (_recipientIdController.text.isNotEmpty
                      ? const Icon(Icons.error, color: Colors.red)
                      : null)),
                ),
                validator: (value) =>
                value == null || value.isEmpty ? 'Recipient ID is required' : null,
              ),
              if (_recipientProfile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Name: ${_recipientProfile!['name']}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (_recipientIdController.text.isNotEmpty &&
                  !_isVerifyingRecipient)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'user_not_found_with_role'.tr(),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComplaintForm() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'complaint_details_section'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedSubject,
              decoration: InputDecoration(
                labelText: 'subject_label'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: _preBuiltSubjects
                  .map(
                    (subject) =>
                    DropdownMenuItem(value: subject, child: Text(subject)),
              )
                  .toList(),
              onChanged: (value) => setState(() {
                _selectedSubject = value;
                _showCustomSubject = value == 'Other';
              }),
              validator: (value) =>
              value == null ? 'Please select a subject' : null,
            ),
            if (_showCustomSubject) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectController,
                decoration: InputDecoration(
                  labelText: 'custom_subject'.tr(),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Custom subject is required'
                    : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _complaintController,
              decoration: InputDecoration(
                labelText: 'complaint_label'.tr(),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              maxLength: 1000,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Complaint details cannot be empty';
                }
                if (value.trim().length < 20) {
                  return 'Please provide more detail (min 20 characters)';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text(
              'attach_photo_optional'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _pickedFile == null ? 'Choose File' : 'Change File',
                  ),
                ),
                const SizedBox(width: 16),
                if (_pickedFile != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_pickedFile!.path),
                      height: 60,
                      width: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _submitComplaint,
      icon: _isLoading
          ? Container(
        width: 24,
        height: 24,
        padding: const EdgeInsets.all(2.0),
        child: const CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      )
          : const Icon(Icons.send),
      label: Text('submit_complaint'.tr()),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}