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

  // Cache structure to hold IDs for specific roles
  final Map<String, String?> _cachedAssignedUsers = {
    'driver': null,
    'agent_accepted': null, // The agent/truckowner who accepted the load
    'agent_creator': null,  // The agent/truckowner who posted the load
    'shipper': null,        // The pure shipper (if applicable)
  };

  String? _shipmentCreatorRole;
  String? _selectedRecipientRole; // This holds the Label string (e.g., "Agent (Accepted)")

  // Pre-built subjects
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
  bool _isFetchingShipment = false;

  @override
  void initState() {
    super.initState();
    _fetchSenderProfile();

    // Initialize shipment data based on how the page was opened
    if (widget.complaintData.isNotEmpty) {
      _shipmentDetails = widget.complaintData;
      _processShipmentData(); // Logic extracted for cleaner code
    } else {
      _fetchShipmentDetails();
    }

    // Debounce for manual ID entry
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

  // --- Logic Section ---

  Future<void> _processShipmentData() async {
    await _determineShipmentCreator();
    _cacheAssignedUsers();
    if (mounted) setState(() {});
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchShipmentDetails() async {
    if (widget.preFilledShipmentId == null) return;

    setState(() => _isFetchingShipment = true);
    try {
      final data = await Supabase.instance.client
          .from('shipment')
          .select('assigned_driver, assigned_agent, shipper_id, assigned_truckowner')
          .eq('shipment_id', widget.preFilledShipmentId!)
          .single()
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        _shipmentDetails = data;
        await _processShipmentData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('shipment_fetch_error'.tr()),
            action: SnackBarAction(label: 'retry'.tr(), onPressed: _fetchShipmentDetails),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingShipment = false);
    }
  }

  Future<void> _determineShipmentCreator() async {
    if (_shipmentDetails == null) return;

    final shipperId = _shipmentDetails!['shipper_id']?.toString();
    if (shipperId == null || shipperId.isEmpty) return;

    try {
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('role, custom_user_id')
          .eq('custom_user_id', shipperId)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          _shipmentCreatorRole = (profile['role'] as String?)?.toLowerCase().trim();
        });
      }
    } catch (e) {
      debugPrint('Error determining creator: $e');
    }
  }

  void _cacheAssignedUsers() {
    if (_shipmentDetails == null) return;

    // 1. Identify Accepted Agent (either 'assigned_agent' or 'assigned_truckowner')
    String? assignedAgent = (_shipmentDetails!['assigned_agent']?.toString() ?? '').trim();
    String? assignedTruckOwner = (_shipmentDetails!['assigned_truckowner']?.toString() ?? '').trim();

    final agentAccepted = (assignedAgent.isNotEmpty)
        ? assignedAgent
        : (assignedTruckOwner.isNotEmpty ? assignedTruckOwner : null);

    // 2. Identify Creator (Agent vs Shipper)
    final creatorId = _shipmentDetails!['shipper_id']?.toString();
    String? agentCreator;
    String? shipper;

    if (creatorId != null && creatorId.isNotEmpty) {
      if (_shipmentCreatorRole != null &&
          (_shipmentCreatorRole!.contains('agent') || _shipmentCreatorRole!.contains('truckowner'))) {
        agentCreator = creatorId;
      } else {
        shipper = creatorId;
      }
    }

    // 3. Identify Driver
    String? driver = _shipmentDetails!['assigned_driver']?.toString();

    // 4. Update Cache
    _cachedAssignedUsers['driver'] = (driver != null && driver.isNotEmpty) ? driver : null;
    _cachedAssignedUsers['agent_accepted'] = agentAccepted;
    _cachedAssignedUsers['agent_creator'] = agentCreator;
    _cachedAssignedUsers['shipper'] = (shipper != null && shipper.isNotEmpty) ? shipper : null;
  }

  // CORE LOGIC: Determines which options appear in the dropdown
  List<String> _computeAvailableRoles() {
    final labels = <String>[];

    final driverId = _cachedAssignedUsers['driver'];
    final agentAcceptedId = _cachedAssignedUsers['agent_accepted'];
    final agentCreatorId = _cachedAssignedUsers['agent_creator'];
    final shipperId = _cachedAssignedUsers['shipper'];

    final senderId = _senderProfile?['custom_user_id'] as String?;

    // Helper: Validates if ID exists and is NOT the current user
    bool isValidTarget(String? id) {
      if (id == null || id.isEmpty) return false;
      if (senderId != null && id == senderId) return false;
      return true;
    }

    final creatorRole = _shipmentCreatorRole ?? '';
    final creatorIsAgent = creatorRole.contains('agent') || creatorRole.contains('truckowner');

    // Case 1: Shipper Created -> Standard flow
    if (!creatorIsAgent) {
      if (isValidTarget(driverId)) labels.add('Driver');
      if (isValidTarget(agentAcceptedId)) labels.add('Agent (Accepted)');
      if (isValidTarget(shipperId)) labels.add('Shipper');
      return labels;
    }

    // Case 2 & 3: Agent Created (Sub-contracting or Direct)

    // Always allow complaining against driver if valid
    if (isValidTarget(driverId)) labels.add('Driver');

    // Handle Agent vs Agent scenarios
    if (agentCreatorId != null && agentAcceptedId != null && agentCreatorId != agentAcceptedId) {
      // Different agents involved (Sub-contracting)
      if (isValidTarget(agentCreatorId)) labels.add('Agent (Creator)');
      if (isValidTarget(agentAcceptedId)) labels.add('Agent (Accepted)');
    } else {
      // Single agent involved (or creator/acceptor are same)
      final effectiveAgentId = agentCreatorId ?? agentAcceptedId;
      if (isValidTarget(effectiveAgentId)) {
        // Label based on context: if I am the driver, I complain against "Agent (Creator)" usually
        labels.add('Agent (Creator)');
      }
    }

    if (isValidTarget(shipperId)) labels.add('Shipper');

    return labels;
  }

  Future<void> _autofillRecipientId(String roleLabel) async {
    String? cachedId;

    // Map dropdown label to cache key
    switch (roleLabel) {
      case 'Driver': cachedId = _cachedAssignedUsers['driver']; break;
      case 'Agent (Accepted)': cachedId = _cachedAssignedUsers['agent_accepted']; break;
      case 'Agent (Creator)': cachedId = _cachedAssignedUsers['agent_creator']; break;
      case 'Shipper': cachedId = _cachedAssignedUsers['shipper']; break;
    }

    // Fallback logic specific to Agent/Shipper confusion
    if (roleLabel == 'Agent (Creator)' && cachedId == null) {
      cachedId = _shipmentDetails?['shipper_id']?.toString();
    }

    if (cachedId != null && cachedId.isNotEmpty) {
      try {
        final response = await Supabase.instance.client
            .from('user_profiles')
            .select('custom_user_id, name, role')
            .eq('custom_user_id', cachedId)
            .maybeSingle();

        if (mounted && response != null) {
          setState(() {
            _recipientIdController.text = cachedId!;
            _recipientProfile = response;
          });
        }
      } catch (e) {
        _clearRecipient();
      }
    } else {
      _clearRecipient();
    }
  }

  void _clearRecipient() {
    if (mounted) {
      setState(() {
        _recipientIdController.clear();
        _recipientProfile = null;
      });
    }
  }

  Future<void> _fetchSenderProfile() async {
    if (!await _checkConnectivity()) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id, name, role')
          .eq('user_id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _senderProfile = profile;
          _isFetchingSender = false;
        });
        // Refresh options once we know who the sender is (to exclude self)
        setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingSender = false);
    }
  }

  Future<void> _verifyRecipientId(String id) async {
    if (id.isEmpty || _selectedRecipientRole == null) return;

    // Self check
    if (_senderProfile != null && id == _senderProfile!['custom_user_id']) {
      _showError('cannot_file_self'.tr());
      _clearRecipient();
      return;
    }

    setState(() => _isVerifyingRecipient = true);

    try {
      // Map display label to DB roles
      List<String> dbRoles = [];
      if (_selectedRecipientRole == 'Driver') dbRoles = ['driver'];
      else if (_selectedRecipientRole == 'Shipper') dbRoles = ['shipper'];
      else dbRoles = ['agent', 'truckowner'];

      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id, name, role')
          .eq('custom_user_id', id)
          .inFilter('role', dbRoles)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _recipientProfile = profile;
          _isVerifyingRecipient = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _clearRecipient();
        setState(() => _isVerifyingRecipient = false);
      }
    }
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;
    if (_recipientProfile == null) {
      _showError('verify_recipient'.tr());
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser!;

      // Upload Attachment
      String? attachmentUrl;
      if (_pickedFile != null) {
        final fileBytes = await _pickedFile!.readAsBytes();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_pickedFile!.name}';
        final filePath = 'user_${user.id}/$fileName';
        await Supabase.instance.client.storage
            .from('complaint-attachments')
            .uploadBinary(filePath, fileBytes);
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
        'subject': _selectedSubject == 'Other' ? _subjectController.text.trim() : _selectedSubject,
        'complaint': _complaintController.text.trim(),
        'status': 'Open',
        'attachment_url': attachmentUrl,
        'shipment_id': widget.preFilledShipmentId,
      };

      await Supabase.instance.client.from('complaints').insert(complaintData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('complaint_submitted'.tr()), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _showError('Error submitting complaint: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (picked != null) setState(() => _pickedFile = picked);
  }

  // --- UI Section ---

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
              Text('could_not_load_profile_info'.tr(), style: const TextStyle(color: Colors.red))
            else ...[
              Text(profile['name'] ?? 'N/A', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('ID: ${profile['custom_user_id'] ?? 'N/A'}', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('recipient_complain_against'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selectedRecipientRole, // Use value instead of initialValue for dynamic updates
              decoration: InputDecoration(
                labelText: 'select_recipient_role'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: _computeAvailableRoles().map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedRecipientRole = value;
                  _recipientProfile = null;
                  _recipientIdController.clear();
                });
                _autofillRecipientId(value);
              },
              validator: (value) => value == null ? 'Please select a role' : null,
            ),
            if (_selectedRecipientRole != null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _recipientIdController,
                decoration: InputDecoration(
                  labelText: 'enter_recipient_id'.tr(),
                  border: const OutlineInputBorder(),
                  suffixIcon: _isVerifyingRecipient
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                      : (_recipientProfile != null
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : (_recipientIdController.text.isNotEmpty ? const Icon(Icons.error, color: Colors.red) : null)),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Recipient ID is required' : null,
              ),
              if (_recipientProfile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Name: ${_recipientProfile!['name']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComplaintForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('complaint_details_section'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selectedSubject,
              decoration: InputDecoration(labelText: 'subject_label'.tr(), border: const OutlineInputBorder()),
              items: _preBuiltSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) => setState(() {
                _selectedSubject = value;
                _showCustomSubject = value == 'Other';
              }),
              validator: (v) => v == null ? 'Please select a subject' : null,
            ),
            if (_showCustomSubject) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectController,
                decoration: InputDecoration(labelText: 'custom_subject'.tr(), border: const OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _complaintController,
              decoration: InputDecoration(labelText: 'complaint_label'.tr(), border: const OutlineInputBorder(), alignLabelWithHint: true),
              maxLines: 5,
              maxLength: 1000,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 20) return 'Too short (min 20 chars)';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_pickedFile == null ? 'Choose File' : 'Change File'),
                ),
                if (_pickedFile != null) ...[
                  const SizedBox(width: 16),
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_pickedFile!.path), height: 40, width: 40, fit: BoxFit.cover)),
                ]
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
      icon: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Icon(Icons.send),
      label: Text('submit_complaint'.tr()),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}