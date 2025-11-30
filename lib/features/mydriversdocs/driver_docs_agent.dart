import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../notifications/notification_service.dart';

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
  String? _loggedInOwnerId;
  String? _loggedInOwnerName;
  late AnimationController _animationController;

  final Map<String, Map<String, dynamic>> _documentTypes = {
    'aadhaar_card': {
      'icon': Icons.credit_card,
      'description': 'govt_identity_card'.tr(),
      'color': Colors.blue,
    },
    'driving_license': {
      'icon': Icons.drive_eta,
      'description': 'valid_driving_license'.tr(),
      'color': Colors.orange,
    },
    'photo': {
      'icon': Icons.person,
      'description': 'profile_photo'.tr(),
      'color': Colors.green,
    },
    'college_id': {
      'icon': Icons.school,
      'description': 'college_id_card'.tr(),
      'color': Colors.purple,
    },
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _initializePage();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getDriverName(String driverId) {
    try {
      final driver = _drivers.firstWhere(
        (d) => d['custom_user_id'] == driverId,
      );
      return driver['name'] ?? 'Your Driver';
    } catch (e) {
      return 'Your Driver';
    }
  }

  Future<void> _initializePage() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        _showErrorSnackBar('auth_required'.tr());
        setState(() => _isLoading = false);
        return;
      }

      final profile = await supabase
          .from('user_profiles')
          .select('custom_user_id, name')
          .eq('user_id', userId)
          .single();

      if (!mounted) return;

      _loggedInOwnerId = profile['custom_user_id'];
      _loggedInOwnerName = profile['name'];

      if (_loggedInOwnerId == null) {
        _showErrorSnackBar('auth_required'.tr());
        setState(() => _isLoading = false);
        return;
      }

      await _fetchDriversWithDocStatus();
      _animationController.forward();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize page: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchDriversWithDocStatus() async {
    if (_loggedInOwnerId == null) return;

    try {
      final relations = await supabase
          .from('driver_relation')
          .select('driver_custom_id')
          .eq('owner_custom_id', _loggedInOwnerId!);

      if (relations.isEmpty) {
        if (mounted) setState(() => _drivers = []);
        return;
      }

      final driverIds = relations
          .map((r) => r['driver_custom_id'] as String)
          .where((id) => id.isNotEmpty)
          .toList();

      if (driverIds.isEmpty) {
        if (mounted) setState(() => _drivers = []);
        return;
      }

      final driverProfiles = await supabase
          .from('user_profiles')
          .select('custom_user_id, name, email, mobile_number')
          .inFilter('custom_user_id', driverIds);

      final uploadedDocs = await supabase
          .from('driver_documents')
          .select(
            'driver_custom_id, document_type, updated_at, file_url, status, file_path',
          )
          .eq('owner_custom_id', _loggedInOwnerId!)
          .inFilter('driver_custom_id', driverIds);

      final driversWithStatus = driverProfiles
          .map((driver) {
            final driverId = driver['custom_user_id'];
            if (driverId == null || driverId.isEmpty) return null;

            final docsForThisDriver = uploadedDocs
                .where((doc) => doc['driver_custom_id'] == driverId)
                .toList();

            final docStatus = <String, Map<String, dynamic>>{};
            for (var type in _documentTypes.keys) {
              final doc = docsForThisDriver.firstWhere(
                (d) => d['document_type'] == type,
                orElse: () => {},
              );

              docStatus[type] = {
                'uploaded': doc.isNotEmpty,
                'status': doc['status'] ?? 'Not Uploaded',
                'uploadedAt': doc['updated_at'],
                'file_path': doc['file_path'],
                'file_url': doc['file_url'],
              };
            }

            return {
              ...driver,
              'doc_status': docStatus,
              'total_docs': docStatus.values
                  .where((doc) => doc['uploaded'])
                  .length,
              'completion_percentage':
                  (docStatus.values.where((doc) => doc['uploaded']).length /
                          _documentTypes.length *
                          100)
                      .round(),
            };
          })
          .where((driver) => driver != null)
          .cast<Map<String, dynamic>>()
          .toList();

      if (mounted) {
        setState(() => _drivers = driversWithStatus);
      }
    } catch (e) {
      _showErrorSnackBar('Error loading driver data: ${e.toString()}');
    }
  }

  Future<void> _uploadDocument(String driverId, String docType) async {
    if (_loggedInOwnerId == null) {
      _showErrorSnackBar('auth_error'.tr());
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;

      final platformFile = result.files.single;
      if (platformFile.path == null) {
        _showErrorSnackBar('file_access_error'.tr());
        return;
      }

      final file = File(platformFile.path!);

      setState(() {
        _uploadingDriverId = driverId;
        _uploadingDocType = docType;
      });

      final sanitizedDocType = docType.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final folderPath = '$driverId/$sanitizedDocType';
      final existingFiles = await supabase.storage
          .from('driver-documents')
          .list(path: folderPath);
      if (existingFiles.isNotEmpty) {
        final filesToDelete = existingFiles
            .map((file) => '$folderPath/${file.name}')
            .toList();
        await supabase.storage.from('driver-documents').remove(filesToDelete);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = platformFile.extension ?? 'jpg';
      final filePath = '$folderPath/$timestamp.$fileExtension';

      await supabase.storage.from('driver-documents').upload(filePath, file);

      final fileUrl = supabase.storage
          .from('driver-documents')
          .getPublicUrl(filePath);

      await supabase.from('driver_documents').upsert({
        'owner_custom_id': _loggedInOwnerId!,
        'driver_custom_id': driverId,
        'document_type': docType,
        'file_path': filePath,
        'file_url': fileUrl,
        'status': 'uploaded',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'owner_custom_id,driver_custom_id,document_type');

      // --- ADD NOTIFICATION LOGIC ---
      final agentName = _loggedInOwnerName ?? 'Your Agent';

      // 1. Notify the driver
      NotificationService.sendPushNotificationToUser(
        recipientId: driverId,
        title: 'Document Uploaded'.tr(),
        message: '$agentName has uploaded a new document for you: $docType'
            .tr(),
        data: {'type': 'document_upload', 'doc_type': docType},
      );

      // 2. Notify self (the agent/owner)
      final driverNameForSelf = _getDriverName(driverId);
      NotificationService.sendPushNotificationToUser(
        recipientId: _loggedInOwnerId!,
        title: 'Upload Successful'.tr(),
        message:
            'You have successfully uploaded $docType for $driverNameForSelf.'
                .tr(),
        data: {'type': 'document_upload_self', 'driver_id': driverId},
      );
      // --- END NOTIFICATION LOGIC ---

      _showSuccessSnackBar('✅ $docType uploaded successfully!');
      await _fetchDriversWithDocStatus();
    } catch (e) {
      _showErrorSnackBar('Upload failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingDriverId = null;
          _uploadingDocType = null;
        });
      }
    }
  }

  Future<bool> _updateDocumentStatus(
    String driverId,
    String docType,
    String newStatus,
    String? filePath,
    String? fileUrl,
  ) async {
    try {
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (newStatus == 'rejected') {
        if (filePath != null) {
          await supabase.storage.from('driver-documents').remove([filePath]);
        }
        updateData['file_path'] = null;
        updateData['file_url'] = null;
      }

      await supabase.from('driver_documents').update(updateData).match({
        'owner_custom_id': _loggedInOwnerId!,
        'driver_custom_id': driverId,
        'document_type': docType,
      });

      _showSuccessSnackBar('Document status updated to $newStatus.');
      return true;
    } catch (e) {
      _showErrorSnackBar('Failed to update status: ${e.toString()}');
      return false;
    }
  }

  Future<void> _viewDocument(String? url) async {
    if (url == null || url.isEmpty) {
      _showErrorSnackBar("no_file_url".tr());
      return;
    }
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showErrorSnackBar("doc_open_error".tr());
    }
  }

  Future<void> _deleteDocument(
    String driverId,
    String docType,
    String? filePath,
  ) async {
    final confirmed = await _showDeleteConfirmationDialog();
    if (!confirmed) return;

    final driver = _drivers.firstWhere((d) => d['custom_user_id'] == driverId);
    final doc = driver['doc_status'][docType];
    final originalDocData = Map<String, dynamic>.from(doc);

    setState(() {
      doc['status'] = 'Not Uploaded';
      doc['uploaded'] = false;
      doc['uploadedAt'] = null;
      doc['file_path'] = null;
      doc['file_url'] = null;

      final docStatusMap = driver['doc_status'] as Map<String, dynamic>;
      driver['total_docs'] = docStatusMap.values
          .where((d) => d['uploaded'] == true)
          .length;
      driver['completion_percentage'] =
          (driver['total_docs'] / _documentTypes.length * 100).round();
    });

    try {
      if (filePath != null) {
        await supabase.storage.from('driver-documents').remove([filePath]);
      }
      await supabase.from('driver_documents').delete().match({
        'owner_custom_id': _loggedInOwnerId!,
        'driver_custom_id': driverId,
        'document_type': docType,
      });
      _showSuccessSnackBar('$docType deleted successfully.');
    } catch (e) {
      _showErrorSnackBar('Failed to delete: ${e.toString()}');
      if (mounted) {
        setState(() {
          driver['doc_status'][docType] = originalDocData;

          final docStatusMap = driver['doc_status'] as Map<String, dynamic>;
          driver['total_docs'] = docStatusMap.values
              .where((d) => d['uploaded'] == true)
              .length;
          driver['completion_percentage'] =
              (driver['total_docs'] / _documentTypes.length * 100).round();
        });
      }
    }
  }

  Future<void> _handleStatusUpdate(
    String driverId,
    String docType,
    String newStatus,
    String? filePath,
    String? fileUrl,
  ) async {
    final driver = _drivers.firstWhere((d) => d['custom_user_id'] == driverId);
    final doc = driver['doc_status'][docType];
    final originalStatus = doc['status'];

    setState(() {
      doc['status'] = newStatus;
    });

    final success = await _updateDocumentStatus(
      driverId,
      docType,
      newStatus,
      filePath,
      fileUrl,
    );

    if (success) {
      final agentName = _loggedInOwnerName ?? 'Your Agent';
      if (newStatus == 'verified') {
        NotificationService.sendPushNotificationToUser(
          recipientId: driverId,
          title: 'Document Approved'.tr(),
          message: 'Your document ($docType) has been approved by $agentName.'
              .tr(),
          data: {
            'type': 'document_status',
            'doc_type': docType,
            'status': 'approved',
          },
        );
      } else if (newStatus == 'rejected') {
        NotificationService.sendPushNotificationToUser(
          recipientId: driverId,
          title: 'Document Rejected'.tr(),
          message: 'Your document ($docType) was rejected by $agentName.'.tr(),
          data: {
            'type': 'document_status',
            'doc_type': docType,
            'status': 'rejected',
          },
        );
      }
    }

    if (!success && mounted) {
      setState(() {
        doc['status'] = originalStatus;
      });
    } else if (success) {
      await _fetchDriversWithDocStatus();
    }
  }

  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('confirm_deletion'.tr()),
              content: Text('delete_doc_warning'.tr()),
              actions: <Widget>[
                TextButton(
                  child: Text('cancel'.tr()),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: Text('delete'.tr()),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'dismiss'.tr(),
            textColor: Colors.white,
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('driver_documents'.tr())),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDriversWithDocStatus,
              child: _drivers.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _drivers.length,
                      itemBuilder: (context, index) {
                        final driver = _drivers[index];
                        return _buildDriverCard(driver);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'no_drivers_found'.tr(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'add_drivers_hint'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final driverId = driver['custom_user_id'];
    final docStatus = driver['doc_status'] as Map<String, Map<String, dynamic>>;
    final isUploading = _uploadingDriverId == driverId;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDriverHeader(driver),
            const Divider(height: 24),
            ..._documentTypes.keys.map((docType) {
              final docInfo = docStatus[docType] ?? {'uploaded': false};
              return _buildDocumentRow(driverId, docType, docInfo, isUploading);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverHeader(Map<String, dynamic> driver) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.blue.shade100,
          child: Text(
            (driver['name'] ?? 'U')[0].toUpperCase(),
            style: TextStyle(
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driver['name'] ?? 'Unnamed Driver',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'ID: ${driver['custom_user_id']}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        _buildProgressIndicator(
          driver['total_docs'] ?? 0,
          _documentTypes.length,
        ),
      ],
    );
  }

  Widget _buildProgressIndicator(int completed, int total) {
    final percentage = total > 0 ? completed / total : 0.0;
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              percentage == 1.0 ? Colors.green : Colors.blue,
            ),
            strokeWidth: 5,
          ),
          Text(
            '${(percentage * 100).round()}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentRow(
    String driverId,
    String docType,
    Map<String, dynamic> docInfo,
    bool isUploading,
  ) {
    final status = docInfo['status'] ?? 'Not Uploaded';
    final docTypeInfo = _documentTypes[docType]!;
    final isThisDocUploading = isUploading && _uploadingDocType == docType;

    Color statusColor;
    switch (status.toLowerCase()) {
      case 'verified':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      case 'uploaded':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(docTypeInfo['icon'], color: docTypeInfo['color'], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docType,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  docTypeInfo['description'],
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                if (status != 'Not Uploaded' && docInfo['uploadedAt'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Uploaded: ${_formatDate(docInfo['uploadedAt'])}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (isThisDocUploading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _buildActionButtons(driverId, docType, docInfo),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    String driverId,
    String docType,
    Map<String, dynamic> docInfo,
  ) {
    final status = docInfo['status'] ?? 'Not Uploaded';
    final filePath = docInfo['file_path'];
    final fileUrl = docInfo['file_url'];

    if (status.toLowerCase() == 'uploaded') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'verify'.tr(),
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            onPressed: () => _handleStatusUpdate(
              driverId,
              docType,
              'verified',
              filePath,
              fileUrl,
            ),
          ),
          IconButton(
            tooltip: 'reject'.tr(),
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            onPressed: () => _handleStatusUpdate(
              driverId,
              docType,
              'rejected',
              filePath,
              fileUrl,
            ),
          ),
          IconButton(
            tooltip: 'view'.tr(),
            icon: Icon(Icons.visibility_outlined, color: Colors.grey.shade600),
            onPressed: () => _viewDocument(fileUrl),
          ),
        ],
      );
    } else if (status != 'Not Uploaded') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'view'.tr(),
            icon: Icon(Icons.visibility_outlined, color: Colors.grey.shade600),
            onPressed: () => _viewDocument(fileUrl),
          ),
          IconButton(
            tooltip: 'delete'.tr(),
            icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
            onPressed: () => _deleteDocument(driverId, docType, filePath),
          ),
        ],
      );
    } else {
      return TextButton.icon(
        onPressed: () => _uploadDocument(driverId, docType),
        icon: const Icon(Icons.upload_file, size: 16),
        label: Text('upload'.tr()),
      );
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return '';
    }
  }
}
