import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' hide RefreshIndicator;

enum UserRole { agent, truckOwner, driver }

class TruckDocumentsPage extends StatefulWidget {
  const TruckDocumentsPage({super.key});

  @override
  State<TruckDocumentsPage> createState() => _TruckDocumentsPageState();
}

class _TruckDocumentsPageState extends State<TruckDocumentsPage>
  with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _uploadingTruckNumber;
  String? _uploadingDocType;
  List<Map<String, dynamic>> _trucks = [];
  List<Map<String, dynamic>> _filteredTrucks = [];
  String? _loggedInUserId;
  UserRole? _userRole;
  late AnimationController _animationController;
  String _selectedStatusFilter = 'All';
  final List<String> _statusFilters = ['All', 'Uploaded', 'Verified'];

  // Refresh controller for pull-to-refresh
  final RefreshController _refreshController = RefreshController(initialRefresh: false);


  // Vehicle documents that can be uploaded for trucks
  final Map<String, Map<String, dynamic>> _vehicleDocuments = {
  'Vehicle Registration': {
    'icon': Icons.description,
    'description': 'vehicle_registration_description'.tr(),
    'color': Colors.blue,
  },
  'Vehicle Insurance': {
    'icon': Icons.shield,
    'description': 'vehicle_insurance_description'.tr(),
    'color': Colors.green,
  },
  'Vehicle Permit': {
    'icon': Icons.assignment,
    'description': 'vehicle_permit_description'.tr(),
    'color': Colors.orange,
  },
  'Pollution Certificate': {
    'icon': Icons.eco,
    'description': 'pollution_certificate_description'.tr(),
    'color': Colors.purple,
  },
  'Fitness Certificate': {
    'icon': Icons.verified,
    'description': 'fitness_certificate_description'.tr(),
    'color': Colors.red,
  },
  };

  @override
  void initState() {
  super.initState();
  _animationController = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: this,
  );
  _initializeData();
  }

  @override
  void dispose() {
  _animationController.dispose();
  super.dispose();
  }

  Future<void> _initializeData() async {
  await _detectUserRole();
  await _loadTruckDocuments();
  }

  Future<void> _detectUserRole() async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final profile = await supabase
      .from('user_profiles')
      .select('custom_user_id, role') // Changed from user_type to role
      .eq('user_id', userId)
      .single();

    _loggedInUserId = profile['custom_user_id'];
    final userType = profile['role']; // Changed from user_type to role

    print('User profile fetched: $profile');

    if (userType == 'agent') {
    _userRole = UserRole.agent;
    } else if (_loggedInUserId!.startsWith('TRUK')) {
    _userRole = UserRole.truckOwner;
    } else if (_loggedInUserId!.startsWith('DRV')) {
    _userRole = UserRole.driver;
    }

    print('Detected role for user $_loggedInUserId: $_userRole');
  } catch (e) {
    print('Error detecting user role: $e');
    // Fallback logic
    if (_loggedInUserId?.startsWith('TRUK') == true) {
    _userRole = UserRole.truckOwner;
    } else if (_loggedInUserId?.startsWith('DRV') == true) {
    _userRole = UserRole.driver;
    } else {
    _userRole = UserRole.driver;
    }
  }
  }

  Future<void> _loadTruckDocuments() async {
  if (!mounted) return;

  setState(() {
    _isLoading = true;
  });

  try {
    List<Map<String, dynamic>> trucks = [];

    // Get trucks based on user role - all users see only their own trucks
    if (_userRole == UserRole.agent || _userRole == UserRole.truckOwner) {
    // Both agents and truck owners can see only their own trucks
    trucks = await supabase
      .from('trucks')
      .select(
      'id, truck_number, truck_admin, make, model, year, vehicle_type',
    )
      .eq('truck_admin', _loggedInUserId!)
      .order('truck_number');

    // Debug: Check what data we get from database
    print('Raw trucks data from database: $trucks');
    } else if (_userRole == UserRole.driver) {
    // Drivers can only see trucks they are currently assigned to via shipments
    final activeShipments = await supabase
      .from('shipment')
      .select('assigned_truck')
      .eq('assigned_driver', _loggedInUserId!)
      .not('booking_status', 'in', '(Completed,cancelled)');

    if (activeShipments.isNotEmpty) {
      final truckNumbers = activeShipments
        .map((shipment) => shipment['assigned_truck'] as String)
        .where((truckNo) => truckNo.isNotEmpty)
        .toSet()
        .toList();

      if (truckNumbers.isNotEmpty) {
      trucks = await supabase
        .from('trucks')
        .select(
        'id, truck_number, truck_admin, make, model, year, vehicle_type',
      )
        .inFilter('truck_number', truckNumbers)
        .order('truck_number');
      }
    }
    }

    print('User role: $_userRole, User ID: $_loggedInUserId');
    print('Found trucks: ${trucks.length} - $trucks');

    if (trucks.isEmpty) {
    setState(() {
      _trucks = [];
      _filteredTrucks = [];
      _isLoading = false;
    });
    return;
    }

    // Get truck documents for all these trucks
    final truckIds = trucks.map((truck) {
    final id = truck['id'];
    return id is int ? id : int.parse(id.toString());
    }).toList();

    print('Truck IDs to fetch documents for: $truckIds');

    final uploadedDocs = await supabase
      .from('truck_documents_old')
      .select('truck_id, doc_type, uploaded_at, file_path, custom_user_id')
      .inFilter('truck_id', truckIds)
      .eq('is_active', true);

    print('Found truck documents: ${uploadedDocs.length} - $uploadedDocs');

    // Build trucks with their document status (similar to driver documents structure)
    final trucksWithDocuments = trucks
      .map((truck) {
    final truckIdValue = truck['id'];
    print(
      'Processing truck: ${truck['truck_number']}, id value: $truckIdValue',
    );
    if (truckIdValue == null) {
      print(
      'WARNING: Truck ID is null for truck: ${truck['truck_number']}',
      );
      return null;
    }

    final truckId = truckIdValue is int
      ? truckIdValue
      : int.parse(truckIdValue.toString());
    final truckNumber = truck['truck_number'];
    if (truckNumber == null || truckNumber.isEmpty) return null;

    final docsForThisTruck = uploadedDocs
      .where((doc) => doc['truck_id'] == truckId)
      .toList();

    final docStatus = <String, Map<String, dynamic>>{};
    for (var type in _vehicleDocuments.keys) {
      // Get document of this type for this truck
      final doc = docsForThisTruck.firstWhere(
        (d) => d['doc_type'] == type,
      orElse: () => <String, dynamic>{},
      );

      final statusValue = doc.isEmpty ? 'Not Uploaded' : 'uploaded';

      if (doc.isNotEmpty) {
      print('Document found for $truckNumber-$type: uploaded');
      }

      // Generate proper public URL for the file
      String? publicUrl;
      if (doc['file_path'] != null &&
        doc['file_path'].toString().isNotEmpty) {
      try {
        publicUrl = supabase.storage
          .from('truck-documents')
          .getPublicUrl(doc['file_path']);
      } catch (e) {
        print('Error generating public URL: $e');
        publicUrl = doc['file_path']; // Fallback to file path
      }
      }

      docStatus[type] = {
      'status': statusValue,
      'file_url': publicUrl,
      'file_path': doc['file_path'],
      'uploaded_at': doc['uploaded_at'],
      'verified_at': null, // Not available in current schema
      'verified_by': null, // Not available in current schema
      'uploaded_by_id': doc['custom_user_id'],
      'uploaded_by_role': null, // Not available in current schema
      };
    }

    return {
      'id': truckId, // Include the truck ID
      'truck_number': truckNumber,
      'truck_admin': truck['truck_admin'] ?? 'Unknown',
      'truck_type': truck['vehicle_type'] ?? truck['make'] ?? 'Unknown',
      'model': truck['model'] ?? 'Unknown',
      'year': truck['year']?.toString() ?? 'Unknown',
      'documents': docStatus,
    };
    })
      .where((truck) => truck != null)
      .cast<Map<String, dynamic>>()
      .toList();

    setState(() {
    _trucks = trucksWithDocuments;
    _applyStatusFilter();
    _isLoading = false;
    });
  } catch (e) {
    print('Error loading truck documents: $e');
    setState(() {
    _isLoading = false;
    });
    _showErrorSnackBar('Error loading documents: ${e.toString()}');
  }
  }

  void _applyStatusFilter() {
  if (_selectedStatusFilter == 'All') {
    _filteredTrucks = List.from(_trucks);
  } else {
    _filteredTrucks = _trucks.where((truck) {
    final docs = truck['documents'] as Map<String, Map<String, dynamic>>;
    return docs.values.any((doc) => doc['status'] == _selectedStatusFilter);
    }).toList();
  }
  }
  Future<void> _uploadDocument(String truckNumber, String docType) async {
  // Check permissions - only agents and truck owners can upload
  if (_userRole == UserRole.driver) {
    _showErrorSnackBar('drivers_cannot_upload_truck_documents'.tr());
    return;
  }

  // Find the truck and get its ID
  final truck = _trucks.firstWhere(
      (t) => t['truck_number'] == truckNumber,
    orElse: () => {},
  );

  if (truck.isEmpty) {
    _showErrorSnackBar('truck_not_found'.tr());
    return;
  }

  // Debug print to check truck data structure
  print('Truck data for upload: $truck');

  // Check if truck owner is uploading for their own truck
  if (_userRole == UserRole.truckOwner) {
    if (truck['truck_admin'] != _loggedInUserId) {
    _showErrorSnackBar('you_can_only_upload_own_trucks'.tr());
    return;
    }
  }

  // Get truck ID - if not available in truck data, query it from database
  int truckId;
  final truckIdValue = truck['id'];

  if (truckIdValue != null) {
    truckId = truckIdValue is int
      ? truckIdValue
      : int.parse(truckIdValue.toString());
  } else {
    // Fallback: Query truck ID using truck_number
    print('Truck ID not found in local data, querying from database...');
    try {
    final truckData = await supabase
      .from('trucks')
      .select('id')
      .eq('truck_number', truckNumber)
      .single();

    final fetchedId = truckData['id'];
    truckId = fetchedId is int
      ? fetchedId
      : int.parse(fetchedId.toString());
    print('Fetched truck ID from database: $truckId');
    } catch (e) {
    print('Error fetching truck ID: $e');
    _showErrorSnackBar('Could not find truck ID');
    return;
    }
  }
  try {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;

    setState(() {
    _uploadingTruckNumber = truckNumber;
    _uploadingDocType = docType;
    });

    final file = File(result.files.single.path!);
    final fileExtension = result.files.single.extension ?? 'jpg';
    final fileName =
      '${truckNumber}_${docType.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    final filePath = 'truck_documents/$fileName';

    // Delete existing document if it exists
    try {
    final existingDocs = await supabase
      .from('truck_documents_old')
      .select('file_path')
      .eq('truck_id', truckId)
      .eq('doc_type', docType)
      .eq('is_active', true);

    if (existingDocs.isNotEmpty) {
      final filesToDelete = existingDocs
        .map((doc) => doc['file_path'] as String)
        .where((path) => path.isNotEmpty)
        .toList();

      if (filesToDelete.isNotEmpty) {
      await supabase.storage
        .from('truck-documents')
        .remove(filesToDelete);
      }

      // Mark old documents as inactive
      await supabase
        .from('truck_documents_old')
        .update({'is_active': false})
        .eq('truck_id', truckId)
        .eq('doc_type', docType);
    }
    } catch (e) {
    print('Error deleting existing file: $e');
    }

    // Upload new file
    await supabase.storage.from('truck-documents').upload(filePath, file);

    // Save document record
    final insertData = {
    'truck_id': truckId,
    'user_id': supabase.auth.currentUser!.id,
    'doc_type': docType,
    'file_name': fileName,
    'file_path': filePath,
    'uploaded_at': DateTime.now().toIso8601String(),
    'is_active': true,
    'custom_user_id': _loggedInUserId,
    };

    await supabase.from('truck_documents_old').insert(insertData);

    _showSuccessSnackBar('Document uploaded successfully');
    await _loadTruckDocuments();
  } catch (e) {
    print('Error uploading document: $e');
    _showErrorSnackBar('Error uploading document: ${e.toString()}');
  } finally {
    setState(() {
    _uploadingTruckNumber = null;
    _uploadingDocType = null;
    });
  }
  }

  Future<void> _verifyDocument(String truckNumber, String docType) async {
  if (_userRole != UserRole.agent) {
    _showErrorSnackBar('only_agents_can_verify'.tr());
    return;
  }

  try {
    _showErrorSnackBar(
    'verification_not_implemented'.tr(),
    );
  } catch (e) {
    _showErrorSnackBar('Error verifying document: ${e.toString()}');
  }
  }

  void _showErrorSnackBar(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.red),
  );
  }

  void _showSuccessSnackBar(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.green),
  );
  }

  @override
  Widget build(BuildContext context) {
  String roleText = 'Unknown';
  switch (_userRole) {
    case UserRole.agent:
    roleText = 'agent'.tr();
    break;
    case UserRole.truckOwner:
    roleText = 'truck_owner'.tr();
    break;
    case UserRole.driver:
    roleText = 'driver'.tr();
    break;
    default:
    roleText = 'unknown'.tr();
  }

  return Scaffold(
    appBar: AppBar(
    title:  Text('truck_documents'.tr()),
    backgroundColor: AppColors.teal,
    foregroundColor: Colors.white,
    actions: [
      if (_userRole != null)
      Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Chip(
        label: Text(
          roleText,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        backgroundColor: AppColors.teal.withOpacity(0.8),
        ),
      ),
    ],
    ),
    body: SmartRefresher(
    controller: _refreshController,
    onRefresh: _onRefresh,
    child: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : Column(
      children: [
      // Status Filter
      Container(
        padding: const EdgeInsets.all(16),
        child: Row(
        children: [
          Text(
          'filter'.tr(),
          style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: _statusFilters.map((status) {
              final isSelected =
                _selectedStatusFilter == status;
              return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(status),
                selected: isSelected,
                onSelected: (selected) {
                setState(() {
                  _selectedStatusFilter = status;
                  _applyStatusFilter();
                });
                },
                backgroundColor: isSelected
                  ? AppColors.teal
                  : null,
                selectedColor: AppColors.teal,
                labelStyle: TextStyle(
                color: isSelected ? Colors.white : null,
                ),
              ),
              );
            }).toList(),
            ),
          ),
          ),
        ],
        ),
      ),
      // Trucks List
      Expanded(
        child: _filteredTrucks.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _userRole == UserRole.driver
              ? 'no_trucks_driver'.tr()
              : 'no_trucks_other'.tr(),
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (_userRole == UserRole.driver)
            Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'driver_hint'.tr(),
              style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            ),
          ],
        ),
        )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredTrucks.length,
        itemBuilder: (context, index) {
          final truck = _filteredTrucks[index];
          return _buildTruckCard(truck);
        },
        ),
      ),
      ],
    ),
    ),
  );
  }

  Widget _buildTruckCard(Map<String, dynamic> truck) {
  final truckNumber = truck['truck_number'] as String;
  final truckType = truck['truck_type'] as String;
  final model = truck['model'] as String;
  final year = truck['year'] as String;
  final documents = truck['documents'] as Map<String, Map<String, dynamic>>;

  return Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: ExpansionTile(
    leading: CircleAvatar(
      backgroundColor: AppColors.teal,
      child: const Icon(
      Icons.local_shipping,
      color: Colors.white,
      size: 20,
      ),
    ),
    title: Text(
      truckNumber,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    subtitle: Text(
      '$truckType${model.isNotEmpty ? ' - $model' : ''}${year.isNotEmpty ? ' ($year)' : ''}',
    ),
    children: [
      Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _vehicleDocuments.entries.map((entry) {
        final docType = entry.key;
        final docConfig = entry.value;
        final docStatus = documents[docType] ?? {};

        return _buildDocumentTile(
          truckNumber,
          docType,
          docConfig,
          docStatus,
        );
        }).toList(),
      ),
      ),
    ],
    ),
  );
  }

  Widget _buildDocumentTile(
    String truckNumber,
    String docType,
    Map<String, dynamic> docConfig,
    Map<String, dynamic> docStatus,
    ) {
  final status = docStatus['status'] ?? 'Not Uploaded';
  final fileUrl = docStatus['file_url'];
  final isUploading =
    _uploadingTruckNumber == truckNumber && _uploadingDocType == docType;

  // Check upload permission
  bool canUpload = false;
  if (_userRole == UserRole.agent) {
    canUpload = true; // Agents can upload for any truck
  } else if (_userRole == UserRole.truckOwner) {
    // Truck owners can upload for their own trucks
    final truck = _trucks.firstWhere(
      (t) => t['truck_number'] == truckNumber,
    orElse: () => {},
    );
    canUpload = truck.isNotEmpty && truck['truck_admin'] == _loggedInUserId;
  }
  // Drivers cannot upload truck documents

  Color statusColor;
  switch (status.toLowerCase()) {
    case 'verified':
    statusColor = Colors.green;
    break;
    case 'uploaded':
    statusColor = Colors.orange;
    break;
    default:
    statusColor = Colors.grey;
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
    border: Border.all(color: Colors.grey.shade300),
    borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
    children: [
      Icon(docConfig['icon'], color: docConfig['color'], size: 24),
      const SizedBox(width: 12),
      Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          docType,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          docConfig['description'],
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
          Container(
            padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
            ),
            decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor),
            ),
            child: Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            ),
          ),
          ],
        ),
        ],
      ),
      ),
      const SizedBox(width: 8),
      if (isUploading)
      const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
      else
      _buildActionButtons(
        truckNumber,
        docType,
        status,
        fileUrl,
        canUpload,
      ),
    ],
    ),
  );
  }

  Widget _buildActionButtons(
    String truckNumber,
    String docType,
    String status,
    String? fileUrl,
    bool canUpload,
    ) {
  List<Widget> actionButtons = [];

  // Upload button for not uploaded documents
  if (status == 'Not Uploaded' && canUpload) {
    actionButtons.add(
    SizedBox(
      height: 32,
      child: ElevatedButton(
      onPressed: () => _uploadDocument(truckNumber, docType),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: const TextStyle(fontSize: 10),
        minimumSize: const Size(60, 32),
      ),
      child:  Text('upload'.tr()),
      ),
    ),
    );
  }

  // View button for uploaded documents
  if (status != 'Not Uploaded' && fileUrl != null) {
    actionButtons.add(
    IconButton(
      tooltip: 'view'.tr(),
      icon: Icon(
      Icons.visibility_outlined,
      color: AppColors.teal,
      size: 18,
      ),
      onPressed: () async {
      try {
        // Generate proper public URL from file path
        String properUrl;
        if (fileUrl.startsWith('http')) {
        // Already a proper URL
        properUrl = fileUrl;
        } else {
        // Generate public URL from file path
        properUrl = supabase.storage
          .from('truck-documents')
          .getPublicUrl(fileUrl);
        }

        print('Attempting to open document URL: $properUrl');

        final uri = Uri.parse(properUrl);
        if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _showSuccessSnackBar('Opening document...');
        } else {
        print('Cannot launch URL: $properUrl');
        _showErrorSnackBar(
          'Cannot open document - URL not supported by device',
        );
        }
      } catch (e) {
        print('Error opening document: $e');
        print('File URL was: $fileUrl');
        _showErrorSnackBar('Cannot open document: ${e.toString()}');
      }
      },
    ),
    );
  }

  // Verify button for agents (uploaded documents only)
  if (status == 'uploaded' && _userRole == UserRole.agent) {
    actionButtons.add(
    IconButton(
      tooltip: 'verify'.tr(),
      icon: const Icon(
      Icons.verified_outlined,
      color: Colors.green,
      size: 18,
      ),
      onPressed: () => _verifyDocument(truckNumber, docType),
    ),
    );
  }

  // Show disabled state for users who can't upload
  if (status == 'Not Uploaded' && !canUpload) {
    String disabledText = 'Cannot Upload';
    if (_userRole == UserRole.driver) {
    disabledText = 'view_only'.tr();
    }

    actionButtons.add(
    Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
      disabledText,
      style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    ),
    );
  }

  return Wrap(spacing: 4, children: actionButtons);
  }

  Future<void> _onRefresh() async {
  try {
    await _loadTruckDocuments();
  } catch (e) {
    debugPrint("Refresh failed: $e");
  } finally {
    _refreshController.refreshCompleted();
  }
  }
} 