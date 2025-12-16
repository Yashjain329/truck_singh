import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/config/theme.dart';

enum UserRole { agent, truckOwner, driver }

class DriverDocumentsPage extends StatefulWidget {
  const DriverDocumentsPage({super.key});

  @override
  State<DriverDocumentsPage> createState() => _DriverDocumentsPageState();
}

class _DriverDocumentsPageState extends State<DriverDocumentsPage>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _uploadingDriverId;
  String? _uploadingDocType;
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _filteredDrivers = [];
  String? _loggedInUserId;
  UserRole? _userRole;
  late AnimationController _animationController;
  String _selectedStatusFilter = 'all';

  final List<String> _statusFilters = [
    'all',
    'pending',
    'approved',
    'rejected',
  ];

  final Map<String, Map<String, dynamic>> _personalDocuments = {
    'Drivers License': {
      'icon': Icons.credit_card,
      'description': 'Valid driving license',
      'color': Colors.blue,
    },
    'Aadhaar Card': {
      'icon': Icons.badge,
      'description': 'Government identity card',
      'color': Colors.green,
    },
    'PAN Card': {
      'icon': Icons.credit_card_outlined,
      'description': 'PAN card for tax identification',
      'color': Colors.orange,
    },
    'Profile Photo': {
      'icon': Icons.person,
      'description': 'Driver profile photograph',
      'color': Colors.purple,
    },
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initializeData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int _compareDocsByDate(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aTime = DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime(1970);
    final bTime = DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime(1970);
    return bTime.compareTo(aTime);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'not_uploaded':
      default:
        return Colors.grey;
    }
  }

  bool get _canReview =>
      _userRole == UserRole.agent || _userRole == UserRole.truckOwner;

  Future<void> _initializeData() async {
    await _detectUserRole();
    await _loadDriverDocuments();
  }

  Future<void> _detectUserRole() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profile = await supabase
          .from('user_profiles')
          .select('custom_user_id, role')
          .eq('user_id', userId)
          .single();

      _loggedInUserId = profile['custom_user_id'];
      final userType = profile['role'];

      if (userType == 'agent') {
        _userRole = UserRole.agent;
      } else if (_loggedInUserId!.startsWith('TRUK')) {
        _userRole = UserRole.truckOwner;
      } else if (_loggedInUserId!.startsWith('DRV')) {
        _userRole = UserRole.driver;
      }
    } catch (_) {
      if (_loggedInUserId?.startsWith('TRUK') == true) {
        _userRole = UserRole.truckOwner;
      } else {
        _userRole = UserRole.driver;
      }
    }
  }

  Future<void> _loadDriverDocuments() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> relations = [];

      if (_canReview) {
        relations = await supabase
            .from('driver_relation')
            .select('driver_custom_id')
            .eq('owner_custom_id', _loggedInUserId!);
      } else if (_userRole == UserRole.driver) {
        relations = [
          {'driver_custom_id': _loggedInUserId},
        ];
      }

      if (relations.isEmpty) {
        setState(() {
          _drivers = [];
          _filteredDrivers = [];
          _isLoading = false;
        });
        return;
      }

      final driverIds = relations
          .map((r) => r['driver_custom_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      final driverProfiles = await supabase
          .from('user_profiles')
          .select('custom_user_id, name, email, mobile_number')
          .inFilter('custom_user_id', driverIds);

      final uploadedDocs = await supabase
          .from('driver_documents')
          .select(
            'driver_custom_id, document_type, updated_at, file_url, status, file_path, rejection_reason, submitted_at, reviewed_at, reviewed_by, uploaded_by_role, owner_custom_id, truck_owner_id, document_category',
          )
          .inFilter('driver_custom_id', driverIds)
          .eq('document_category', 'personal');

      final driversWithStatus = driverProfiles.map((driver) {
        final driverId = driver['custom_user_id'];
        final docs = uploadedDocs
            .where((d) => d['driver_custom_id'] == driverId)
            .toList();

        final docStatus = <String, Map<String, dynamic>>{};
        for (var docType in _personalDocuments.keys) {
          final matched = docs
              .where((d) => d['document_type'] == docType)
              .toList();
          matched.sort(_compareDocsByDate);
          final doc = matched.isNotEmpty ? matched.first : {};
          String statusKey = 'not_uploaded';
          if (doc.isNotEmpty) {
            final raw = (doc['status'] ?? '').toString().trim().toLowerCase();
            if (raw.isNotEmpty && raw != 'null') {
              if (raw.contains('pending'))
                statusKey = 'pending';
              else if (raw.contains('approved'))
                statusKey = 'approved';
              else if (raw.contains('rejected'))
                statusKey = 'rejected';
              else
                statusKey = raw;
            }
          }
          docStatus[docType] = {
            'status': statusKey,
            'file_url': doc['file_url'],
            'rejection_reason': doc['rejection_reason'],
          };
        }
        return {
          'custom_user_id': driverId,
          'name': driver['name'] ?? 'Unknown',
          'documents': docStatus,
        };
      }).toList();

      setState(() {
        _drivers = driversWithStatus;
      });
      _applyStatusFilter();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyStatusFilter() {
    if (_selectedStatusFilter.trim().toLowerCase() == 'all') {
      _filteredDrivers = List.from(_drivers);
      setState(() {});
      return;
    }

    final filter = _selectedStatusFilter.toLowerCase().trim();

    _filteredDrivers = _drivers.where((driver) {
      final docs = driver['documents'] as Map<String, Map<String, dynamic>>;
      return docs.values.any((doc) {
        final docStatus = (doc['status'] ?? '').toString().toLowerCase().trim();
        if (filter == 'not_uploaded') {
          return docStatus == 'not_uploaded' ||
              docStatus.isEmpty ||
              docStatus == 'null';
        }
        return docStatus == filter;
      });
    }).toList();

    setState(() {});
  }

  Map<String, Map<String, dynamic>> _driverPersonalDocsFilteredForDriverView() {
    final driverDocs = _drivers.isNotEmpty
        ? _drivers.first['documents'] as Map<String, Map<String, dynamic>>
        : <String, Map<String, dynamic>>{};

    if (_selectedStatusFilter.trim().toLowerCase() == 'all') {
      return driverDocs;
    }
    final filter = _selectedStatusFilter.toLowerCase().trim();
    final Map<String, Map<String, dynamic>> result = {};
    driverDocs.forEach((k, v) {
      final docStatus = (v['status'] ?? '').toString().toLowerCase().trim();
      if (filter == 'not_uploaded') {
        if (docStatus == 'not_uploaded' ||
            docStatus.isEmpty ||
            docStatus == 'null') {
          result[k] = v;
        }
      } else {
        if (docStatus == filter) {
          result[k] = v;
        }
      }
    });

    return result;
  }

  String _localizedStatusLabel(String statusKey) {
    final key = (statusKey).toString().toLowerCase().trim();
    if (key.isEmpty) return 'not_uploaded'.tr();
    return key.tr();
  }

  String _localizedDocTitle(String docType) {
    switch (docType) {
      case 'Drivers License':
        return 'drivers_license'.tr();
      case 'Aadhaar Card':
        return 'aadhaar_card'.tr();
      case 'PAN Card':
        return 'pan_card'.tr();
      case 'Profile Photo':
        return 'profile_photo'.tr();
      default:
        final translated = docType.tr();
        return translated.isEmpty ? docType : translated;
    }
  }

  String _localizedRoleText() {
    if (_userRole == null) return '';
    return _userRole.toString().split('.').last.tr();
  }

  Future<void> _uploadDocument(String driverId, String docType) async {
    if (_userRole == UserRole.driver && driverId != _loggedInUserId) {
      _showErrorSnackBar(
        'drivers_can_only_upload_own'.tr(),
      ); // Localized key assumption
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _uploadingDriverId = driverId;
        _uploadingDocType = docType;
      });
      final existingDocs = await supabase
          .from('driver_documents')
          .select('id, file_path, updated_at')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType)
          .eq('document_category', 'personal');

      if (existingDocs.isNotEmpty) {
        existingDocs.sort(_compareDocsByDate);

        final docToDelete = existingDocs.first;
        final docId = docToDelete['id'];
        final filePathToDelete = docToDelete['file_path'] as String?;

        if (filePathToDelete != null && filePathToDelete.isNotEmpty) {
          try {
            await supabase.storage.from('driver-documents').remove([
              filePathToDelete,
            ]);
          } catch (_) {}
        }
        await supabase.from('driver_documents').delete().eq('id', docId);
      }

      final file = File(result.files.single.path!);
      final ext = result.files.single.extension ?? 'jpg';
      final fileName =
          '${driverId}_${docType.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'driver_documents/$fileName';

      await supabase.storage.from('driver-documents').upload(filePath, file);
      final publicUrl = supabase.storage
          .from('driver-documents')
          .getPublicUrl(filePath);

      await supabase.from('driver_documents').upsert({
        'driver_custom_id': driverId,
        'document_type': docType,
        'file_url': publicUrl,
        'file_path': filePath,
        'status': 'pending',
        'submitted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'uploaded_by_role': _userRole == UserRole.agent
            ? 'agent'
            : (_userRole == UserRole.truckOwner ? 'truck_owner' : 'driver'),
        'document_category': 'personal',
        'user_id': supabase.auth.currentUser?.id,
        'rejection_reason': '',
      }, onConflict: 'driver_custom_id, document_type');

      _showSuccessSnackBar("document_uploaded_success".tr());
      await _loadDriverDocuments();
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
    } finally {
      setState(() {
        _uploadingDriverId = null;
        _uploadingDocType = null;
      });
      _applyStatusFilter();
    }
  }

  Future<void> _approveDocument(String driverId, String docType) async {
    if (_userRole == UserRole.driver) {
      _showErrorSnackBar('drivers_cannot_approve_documents'.tr());
      return;
    }
    try {
      final docs = await supabase
          .from('driver_documents')
          .select('id, status, updated_at')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);

      if (docs.isEmpty) {
        _showErrorSnackBar('no_document_found_to_approve'.tr());
        return;
      }
      docs.sort(_compareDocsByDate);
      final docId = docs.first['id'];
      await supabase.rpc(
        'approve_driver_document',
        params: {
          'p_document_id': docId,
          'p_reviewed_by': supabase.auth.currentUser?.id,
          'p_reviewed_at': DateTime.now().toIso8601String(),
        },
      );

      _showSuccessSnackBar('approved'.tr());
      await _loadDriverDocuments();
      _applyStatusFilter();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _rejectDocument(String driverId, String docType) async {
    if (_userRole == UserRole.driver) {
      _showErrorSnackBar('drivers_cannot_reject_documents'.tr());
      return;
    }

    final reason = await _showRejectDialog();
    if (reason == null || reason.isEmpty) return;

    try {
      final docs = await supabase
          .from('driver_documents')
          .select('id, file_path, updated_at')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);

      if (docs.isEmpty) {
        _showErrorSnackBar('no_document_found_to_reject'.tr());
        return;
      }
      docs.sort(_compareDocsByDate);
      final doc = docs.first;
      final docId = doc['id'];
      final filePath = doc['file_path'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        try {
          await supabase.storage.from('driver-documents').remove([filePath]);
        } catch (_) {}
      }

      await supabase.rpc(
        'reject_driver_document',
        params: {
          'p_document_id': docId,
          'p_reviewed_by': supabase.auth.currentUser?.id,
          'p_rejection_reason': reason,
          'p_reviewed_at': DateTime.now().toIso8601String(),
        },
      );

      _showSuccessSnackBar('rejected'.tr());
      await _loadDriverDocuments();
      _applyStatusFilter();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<String?> _showRejectDialog() async {
    String? reason;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('reject_document'.tr()),
        content: TextField(
          onChanged: (v) => reason = v,
          decoration: InputDecoration(
            hintText: 'enter_rejection_reason'.tr(),
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reason),
            child: Text('reject'.tr()),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    final roleText = _localizedRoleText();

    return Scaffold(
      appBar: AppBar(
        title: Text('driver_documents'.tr()),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_userRole != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  roleText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                backgroundColor: AppColors.teal.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userRole == UserRole.driver
          ? _buildDriverView()
          : _buildReviewerView(),
    );
  }

  Widget _buildDriverView() {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(child: _buildDriverUploadInterfaceFiltered()),
      ],
    );
  }

  Widget _buildReviewerView() {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: _filteredDrivers.isEmpty
              ? Center(child: Text('no_drivers_found'.tr()))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredDrivers.length,
                  itemBuilder: (c, i) => _buildDriverCard(_filteredDrivers[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            'filter'.tr(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusFilters.map((statusKey) {
                  final displayLabel = statusKey.tr();
                  final isSelected = _selectedStatusFilter == statusKey;
                  final labelColor = isSelected
                      ? Colors.white
                      : colorScheme.onSurface;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(displayLabel),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedStatusFilter = statusKey;
                          _applyStatusFilter();
                        });
                      },
                      backgroundColor: isSelected ? AppColors.teal : null,
                      selectedColor: AppColors.teal,
                      labelStyle: TextStyle(color: labelColor),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final driverId = driver['custom_user_id'];
    final driverName = driver['name'];
    final docs = driver['documents'] as Map<String, Map<String, dynamic>>;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.teal,
          child: Text(
            driverName[0].toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          driverName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(driverId),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _personalDocuments.entries.map((e) {
                return _buildDocumentTile(
                  driverId,
                  e.key,
                  e.value,
                  docs[e.key] ?? {},
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(
    String driverId,
    String docType,
    Map<String, dynamic> docConfig,
    Map<String, dynamic> docStatus,
  ) {
    final statusKey = (docStatus['status'] ?? 'not_uploaded').toString();
    final fileUrl = docStatus['file_url'] as String?;
    final rejectionReason = docStatus['rejection_reason'] as String?;
    final uploading =
        _uploadingDriverId == driverId && _uploadingDocType == docType;

    final bool canUpload =
        _canReview ||
        (_userRole == UserRole.driver && driverId == _loggedInUserId);
    final color = _getStatusColor(statusKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(docConfig['icon'], color: docConfig['color']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedDocTitle(docType),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _localizedStatusLabel(statusKey),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (rejectionReason != null && rejectionReason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${'rejection_reason'.tr()}: $rejectionReason',
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (uploading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _buildActionButtons(
              driverId,
              docType,
              statusKey,
              fileUrl,
              canUpload,
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    String driverId,
    String docType,
    String statusKey,
    String? fileUrl,
    bool canUpload,
  ) {
    final statusLower = statusKey.toLowerCase();
    final buttons = <Widget>[];

    if ((statusLower == 'not_uploaded' ||
            statusLower == 'rejected' ||
            statusLower == '') &&
        canUpload) {
      buttons.add(
        ElevatedButton(
          onPressed: () => _uploadDocument(driverId, docType),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          child: Text(
            statusLower == 'rejected' ? 're_upload'.tr() : 'upload'.tr(),
            style: const TextStyle(fontSize: 10),
          ),
        ),
      );
    }


    if (statusLower == 'approved') {
      buttons.add(
        IconButton(
          icon: const Icon(Icons.upload_file, color: Colors.orange, size: 18),
          onPressed: () => _uploadDocument(driverId, docType),
        ),
      );
    }

    if (statusLower != 'not_uploaded' && fileUrl != null) {
      buttons.add(
        IconButton(
          icon: Icon(
            Icons.visibility_outlined,
            color: AppColors.teal,
            size: 18,
          ),
          onPressed: () async {
            try {
              final uri = Uri.parse(fileUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                _showErrorSnackBar('cannot_open_document'.tr());
              }
            } catch (_) {
              _showErrorSnackBar('cannot_open_document'.tr());
            }
          },
        ),
      );
    }

    if (statusLower == 'pending' && _canReview) {
      buttons.addAll([
        IconButton(
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 18,
          ),
          onPressed: () => _approveDocument(driverId, docType),
        ),
        IconButton(
          icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
          onPressed: () => _rejectDocument(driverId, docType),
        ),
      ]);
    }

    return Wrap(spacing: 4, children: buttons);
  }

  Widget _buildDriverUploadInterfaceFiltered() {
    final filteredDocs = _driverPersonalDocsFilteredForDriverView();
    if (filteredDocs.isEmpty) {
      return Center(child: Text('no_documents_matching_filter'.tr()));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: filteredDocs.entries.map((e) {
          final docType = e.key;
          final docData = e.value;
          final config =
              _personalDocuments[docType] ??
              {'icon': Icons.description, 'description': ''};
          return _buildDriverCardDocument(docType, config, docData);
        }).toList(),
      ),
    );
  }

  Widget _buildDriverCardDocument(
    String docType,
    Map<String, dynamic> config,
    Map<String, dynamic> docData,
  ) {
    final statusKey = (docData['status'] ?? 'not_uploaded').toString();
    final rejectionReason = docData['rejection_reason'] as String?;
    final isUploading =
        _uploadingDriverId == _loggedInUserId && _uploadingDocType == docType;
    final color = _getStatusColor(statusKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(config['icon'], size: 24, color: AppColors.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _localizedDocTitle(docType),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusChip(_localizedStatusLabel(statusKey), color),
              ],
            ),
            const SizedBox(height: 12),
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade600,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${'rejection_reason'.tr()}: $rejectionReason',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${'status'.tr()}: ${_localizedStatusLabel(statusKey)}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                if (isUploading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (statusKey.toLowerCase() == 'not_uploaded' ||
                    statusKey.toLowerCase() == 'rejected')
                  ElevatedButton.icon(
                    onPressed: () => _uploadDocument(_loggedInUserId!, docType),
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: Text(
                      statusKey.toLowerCase() == 'rejected'
                          ? 're_upload'.tr()
                          : 'upload'.tr(),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                    ),
                  )
                else if (statusKey.toLowerCase() == 'pending')
                  Text(
                    'under_review'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else if (statusKey.toLowerCase() == 'approved')
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'approved'.tr(),
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Optimized Status Chip
  Widget _buildStatusChip(String statusLabel, Color baseColor) {
    // Generate lighter background and darker text from the base color
    final bg = baseColor == Colors.grey
        ? Colors.grey.shade200
        : baseColor.withValues(alpha: 0.1);
    final text = baseColor == Colors.grey ? Colors.grey.shade800 : baseColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusLabel,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
