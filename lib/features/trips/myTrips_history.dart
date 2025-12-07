import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logistics_toolkit/features/trips/shipment_details.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import '../auth/model/address_model.dart';
import '../invoice/services/invoice_pdf_service.dart';
import 'myTrips_Services.dart';
import 'shipment_card.dart' as shipment_card;
import '../notifications/notification_service.dart';

enum TaxType { withinState, outsideState }

class MyTripsHistory extends StatefulWidget {
  const MyTripsHistory({super.key});

  @override
  State<MyTripsHistory> createState() => _MyTripsHistoryPageState();
}

class _MyTripsHistoryPageState extends State<MyTripsHistory> {
  // Services
  SharedPreferences? _prefs;
  final MyTripsServices _supabaseService = MyTripsServices();
  final ptr.RefreshController _refreshController = ptr.RefreshController(
    initialRefresh: false,
  );

  // User & Auth State
  String? customUserId;
  String? authUserId;
  String? role;
  BillingAddress? _fetchedBillingAddress;
  CompanyAddress? _selectedCompanyAddress;

  // Shipment Data State
  List<Map<String, dynamic>> shipments = [];
  List<Map<String, dynamic>> filteredShipments = [];
  Map<String, List<Map<String, dynamic>>> _groupedShipments = {};
  List<String> _sortedMonths = [];
  Set<String> _invoiceRequests = {};
  Set<String> ratedShipments = {};
  Map<String, int> ratingEditCount = {};
  Map<String, PdfState> pdfStates = {};

  // UI State
  bool loading = true;
  String searchQuery = '';
  String statusFilter = 'All';
  String? selectedMonth;

  // Invoice Form Controllers
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _cMobileNumberController =
  TextEditingController();
  final TextEditingController _billToNameController = TextEditingController();
  final TextEditingController _billToMobileNumberController =
  TextEditingController();
  final TextEditingController _invoiceNumberController =
  TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController =
  TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _accountHolderController =
  TextEditingController();
  final TextEditingController _gstController = TextEditingController();
  final TextEditingController _taxPercentageController =
  TextEditingController();

  // Invoice Calculation State
  double _calculatedTax = 0.0;
  double _calculatedTotal = 0.0;
  TaxType _selectedTaxType = TaxType.withinState;

  @override
  void initState() {
    super.initState();
    _initializePreferences();
    _loadUserAndFetchShipments();
  }

  /// Initialize SharedPreferences and load cached data
  Future<void> _initializePreferences() async {
    _prefs = await SharedPreferences.getInstance();
    await loadCachedShipments();
  }

  /// Wrapper to load user profile first, then fetch shipments
  Future<void> _loadUserAndFetchShipments() async {
    await _loadUser();
    await fetchShipments();
  }

  /// Fetches current user profile (role, custom_user_id)
  Future<void> _loadUser() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final userProfile = await Supabase.instance.client
        .from('user_profiles')
        .select('custom_user_id, role')
        .eq('user_id', currentUserId)
        .maybeSingle();

    if (mounted) {
      setState(() {
        customUserId = userProfile?['custom_user_id'];
        role = userProfile?['role'];
      });
    }
  }

  /// Fetch invoice requests to determine which shipments have pending requests
  Future<void> fetchInvoiceRequests() async {
    if (customUserId == null) return;

    try {
      List<dynamic> response = [];

      // Determine query based on role
      if (role == 'shipper') {
        response = await Supabase.instance.client
            .from('invoice_requests')
            .select('shipment_id')
            .eq('requested_by', customUserId!);
      } else {
        response = await Supabase.instance.client
            .from('invoice_requests')
            .select('shipment_id')
            .eq('requested_to', customUserId!);
      }

      if (response.isNotEmpty && mounted) {
        setState(() {
          _invoiceRequests = response
              .map((r) => r['shipment_id'].toString())
              .toSet();
        });
      }
    } catch (e) {
      debugPrint("Error fetching invoice requests: $e");
    }
  }

  /// Helper to fetch shipper/customer details
  Future<Map<String, String?>> fetchCustomerNameAndMobile(
      String shipperId,
      ) async {
    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('name, mobile_number')
        .eq('custom_user_id', shipperId)
        .maybeSingle();

    if (response != null) {
      return {
        'name': response['name'] as String?,
        'mobile_number': response['mobile_number'] as String?,
      };
    }
    return {'name': null, 'mobile_number': null};
  }

  /// Fetch rating edit counts for shipments
  Future<void> fetchEditCounts() async {
    try {
      final response = await Supabase.instance.client
          .from('ratings')
          .select('shipment_id, edit_count');

      if (response.isNotEmpty && mounted) {
        setState(() {
          for (var row in response) {
            ratingEditCount[row['shipment_id']] = row['edit_count'];
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching edit counts: $e");
    }
  }

  /// Load shipments from local storage for offline/fast access
  Future<void> loadCachedShipments() async {
    final cachedData = _prefs?.getString('shipments_cache');
    if (cachedData != null) {
      setState(() {
        shipments = List<Map<String, dynamic>>.from(jsonDecode(cachedData));
        filteredShipments = shipments;
        _processShipmentData();
        loading = false;
      });
    }
  }

  /// Save fetched shipments to local storage
  Future<void> saveShipmentToCache(List<Map<String, dynamic>> shipments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shipments_cache', jsonEncode(shipments));
  }

  /// Main method to fetch shipments from Supabase
  Future<void> fetchShipments() async {
    setState(() => loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      if (mounted) {
        setState(() {
          loading = false;
          shipments = [];
          filteredShipments = [];
        });
      }
      return;
    }

    try {
      final res = await _supabaseService.getShipmentsForUser(userId);

      // Filter All shipments, expect pending shipments
      final completedShipments = res.where((s) {
        final status = s['booking_status']?.toString().toLowerCase() ?? '';
        return status != 'pending'; // exclude only pending shipments
      }).toList();


      if (mounted) {
        setState(() {
          shipments = completedShipments;
          filteredShipments = shipments;
          loading = false;
        });
      }

      // Update cache and dependent data
      await saveShipmentToCache(shipments);
      await fetchEditCounts();
      await checkPdfStates();
      await fetchInvoiceRequests();

      _processShipmentData();
      _refreshController.refreshCompleted();
    } catch (e) {
      debugPrint("Error fetching shipments: $e");
      if (mounted) setState(() => loading = false);
      _refreshController.refreshFailed();
    }
  }

  void _processShipmentData() {
    _groupedShipments = groupShipmentsByMonth(filteredShipments);

    _sortedMonths = _groupedShipments.keys.toList()
      ..sort((a, b) {
        try {
          final da = DateFormat.yMMMM().parse(a);
          final db = DateFormat.yMMMM().parse(b);
          return db.compareTo(da);
        } catch (e) {
          return 0;
        }
      });

    // Set default month selection
    if (selectedMonth == null && _sortedMonths.isNotEmpty) {
      selectedMonth = _sortedMonths.first;
    } else if (selectedMonth != null &&
        !_sortedMonths.contains(selectedMonth)) {
      selectedMonth = _sortedMonths.isNotEmpty ? _sortedMonths.first : null;
    }
  }

  void searchShipments(String query) {
    if (mounted) {
      setState(() {
        searchQuery = query;
        applyFilters();
      });
    }
  }

  void filterByStatus(String status) {
    if (mounted) {
      setState(() {
        statusFilter = status;
        applyFilters();
      });
    }
  }

  void applyFilters() {
    filteredShipments = shipments.where((s) {
      final bookingStatus = s['booking_status']?.toString().toLowerCase() ?? '';

      final matchQuery = searchQuery.isEmpty ||
          s.values.any((value) => value.toString().toLowerCase().contains(searchQuery.toLowerCase()));

      final matchStatus = statusFilter == 'All' ||
          bookingStatus == statusFilter.toLowerCase();

      return matchQuery && matchStatus;
    }).toList();

    // Sort latest on top
    filteredShipments.sort((a, b) {
      final aDate = DateTime.tryParse(a['delivery_date'] ?? '') ?? DateTime.now();
      final bDate = DateTime.tryParse(b['delivery_date'] ?? '') ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    _processShipmentData(); // update list grouping
    setState(() {});
  }

  void _showStatusFilterDialog() {
    // These are your allowed statuses (no "Pending")
    final List<String> statuses = [
      'All',
      'Accepted',
      'En Route to Pickup',
      'Arrived at Pickup',
      'Loading',
      'Picked Up',
      'In Transit',
      'Arrived at Drop',
      'Unloading',
      'Delivered',
      'Completed',
    ];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('filterByStatus'.tr()),
        content: SingleChildScrollView(
          child: RadioGroup<String>(
            // 👇 Only RadioGroup handles value + change
            groupValue: statusFilter,
            onChanged: (val) {
              if (val == null) return;
              Navigator.pop(context);
              setState(() {
                statusFilter = val;
                applyFilters();
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: statuses.map((status) {
                return RadioListTile<String>(
                  value: status,
                  // ❌ NO groupValue
                  // ❌ NO onChanged here
                  title: Text(status.tr()),
                  activeColor: Colors.teal,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> groupShipmentsByMonth(
      List<Map<String, dynamic>> shipments,
      ) {
    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var shipment in shipments) {
      final dateStr = shipment['delivery_date'];
      if (dateStr == null || dateStr.isEmpty) continue;
      try {
        final date = DateTime.parse(dateStr);
        final monthKey = DateFormat.yMMMM().format(date);
        grouped.putIfAbsent(monthKey, () => []);
        grouped[monthKey]!.add(shipment);
      } catch (e) {
        // Ignore invalid dates
      }
    }

    // Ensure last 6 months exist in keys even if empty
    final now = DateTime.now();
    for (int i = 0; i < 6; i++) {
      final monthDate = DateTime(now.year, now.month - i);
      final monthKey = DateFormat.yMMMM().format(monthDate);
      grouped.putIfAbsent(monthKey, () => []);
    }

    return grouped;
  }

  String getMonthLabel(String monthKey) {
    final now = DateTime.now();
    final currentMonth = DateFormat.yMMMM().format(
      DateTime(now.year, now.month),
    );
    final prevMonth = DateFormat.yMMMM().format(
      DateTime(now.year, now.month - 1),
    );

    if (monthKey == currentMonth) return "This Month";
    if (monthKey == prevMonth) return "Previous Month";
    return monthKey;
  }

  /// Check if invoice PDFs exist locally or are valid URLs
  Future checkPdfStates() async {
    for (var shipment in shipments) {
      final shipmentId = shipment['shipment_id'].toString();
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$shipmentId.pdf';

      if (await File(filePath).exists()) {
        pdfStates[shipmentId] = PdfState.downloaded;
      } else {
        // Verify remote URL validity
        final String? pdfUrl = shipment['Invoice_link'] as String?;
        if (pdfUrl != null && pdfUrl.isNotEmpty) {
          try {
            final response = await http.head(Uri.parse(pdfUrl));
            pdfStates[shipmentId] = response.statusCode == 200
                ? PdfState.uploaded
                : PdfState.notGenerated;
          } catch (_) {
            pdfStates[shipmentId] = PdfState.notGenerated;
          }
        } else {
          pdfStates[shipmentId] = PdfState.notGenerated;
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future generateInvoice(Map<String, dynamic> shipment) async {
    // 1. Fetch Billing Address
    _fetchedBillingAddress = await fetchBillingAddressForShipment(shipment);
    if (_fetchedBillingAddress == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('billing_address_not_found'.tr())));
      return;
    }

    // 2. Fetch Company Addresses
    final companyAddresses = await fetchCompanyAddresses();
    if (companyAddresses.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('no_company_addresses'.tr())));
      return;
    }

    // 3. Select Company Address
    if (companyAddresses.length == 1) {
      _selectedCompanyAddress = companyAddresses.first;
    } else {
      if (!mounted) return;
      _selectedCompanyAddress = await showCompanyAddressDialog(
        context,
        companyAddresses,
      );
      if (_selectedCompanyAddress == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('please_select_company_address'.tr())),
        );
        return;
      }
    }

    // 4. Generate PDF
    final invoiceUrl = await generateInvoicePDF(
      shipment: shipment,
      price: _priceController.text,
      companyName: _companyNameController.text,
      companyAddress: _selectedCompanyAddress != null
          ? '${_selectedCompanyAddress!.flatNo}, ${_selectedCompanyAddress!.streetName}, ${_selectedCompanyAddress!.cityName}, ${_selectedCompanyAddress!.district}, ${_selectedCompanyAddress!.zipCode}'
          : '',
      companyMobile: _cMobileNumberController.text,
      customerName: _billToNameController.text,
      customerAddress: '',
      billingAddress: _fetchedBillingAddress,
      customerMobile: _billToMobileNumberController.text,
      invoiceNo: _invoiceNumberController.text,
      companySelectedAddress: _selectedCompanyAddress,
      bankName: _bankNameController.text,
      accountNumber: _accountNumberController.text,
      ifscCode: _ifscController.text,
      branch: _branchController.text,
      accountHolder: _accountHolderController.text,
      gstNumber: _gstController.text,
      taxPercentage: _taxPercentageController.text,
      taxAmount: _calculatedTax.toString(),
      totalAmount: _calculatedTotal.toString(),
      taxType: _selectedTaxType == TaxType.withinState ? "CGST+SGST" : "IGST",
    );

    // 5. Update Local State & Backend
    shipment['Invoice_link'] = invoiceUrl;
    shipment['hasInvoice'] = true;
    pdfStates[shipment['shipment_id'].toString()] = PdfState.uploaded;

    if (mounted) setState(() {});

    final shipmentId = shipment['shipment_id'].toString();
    await Supabase.instance.client
        .from('shipment')
        .update({'Invoice_link': invoiceUrl})
        .eq('shipment_id', shipmentId);

    // 6. Clean up requests & Notify
    try {
      await Supabase.instance.client
          .from('invoice_requests')
          .delete()
          .eq('shipment_id', shipmentId);
      _invoiceRequests.remove(shipmentId);
    } catch (e) {
      debugPrint("Error updating invoice request status: $e");
    }

    try {
      await _sendInvoiceGeneratedNotification(shipment);
    } catch (e) {
      debugPrint("Error sending 'invoice generated' notification: $e");
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('invoice_generated'.tr())));
  }

  Future downloadInvoice(Map shipment) async {
    final shipmentId = shipment['shipment_id'].toString();
    String? pdfUrl = shipment['Invoice_link'] as String?;

    // Fallback fetch if URL is missing
    if (pdfUrl == null || pdfUrl.isEmpty) {
      final shipmentRow = await Supabase.instance.client
          .from('shipment')
          .select('Invoice_link')
          .eq('shipment_id', shipmentId)
          .maybeSingle();
      pdfUrl = shipmentRow?['Invoice_link'] as String?;
    }

    if (pdfUrl == null || pdfUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('pdf_link_not_found'.tr())));
      return;
    }

    try {
      final response = await http.get(Uri.parse(pdfUrl));

      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final localPath = '${appDir.path}/$shipmentId.pdf';
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes, flush: true);

        pdfStates[shipmentId] = PdfState.downloaded;

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('pdf_downloaded'.tr())));
        }
      } else {
        throw Exception('Server responded with ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Error downloading PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF download failed')));
      }
    }
  }

  void previewInvoice(BuildContext context, String shipmentId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/$shipmentId.pdf';
    final file = File(localPath);

    if (await file.exists()) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(localPath: localPath),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF not found, re-downloading...')),
      );

      final shipment = shipments.firstWhere(
            (s) => s['shipment_id'] == shipmentId,
        orElse: () => <String, dynamic>{},
      );

      if (shipment.isNotEmpty) {
        await downloadInvoice(shipment);
        if (await file.exists() && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfPreviewScreen(localPath: localPath),
            ),
          );
        }
      }
    }
  }

  Future<void> confirmAndDelete(
      BuildContext context,
      Map<String, dynamic> shipment,
      ) async {
    final shipmentId = shipment['shipment_id'].toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Invoice?'),
        content: Text('Are you sure you want to delete this invoice?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final pdfPath = shipment['Invoice_link'] as String?;
      if (pdfPath != null && pdfPath.isNotEmpty) {
        // Delete from Storage
        final bucketPath = pdfPath.split('/invoices/').last;
        await Supabase.instance.client.storage.from('invoices').remove([
          bucketPath,
        ]);

        // Delete Local File
        final appDir = await getApplicationDocumentsDirectory();
        final localPath = '${appDir.path}/$shipmentId.pdf';
        final file = File(localPath);
        if (await file.exists()) await file.delete();

        // Update Database
        await Supabase.instance.client
            .from('shipment')
            .update({'Invoice_link': null})
            .eq('shipment_id', shipmentId);

        shipment['Invoice_link'] = null;
        shipment['hasInvoice'] = false;

        if (mounted) {
          setState(() {
            pdfStates[shipmentId] = PdfState.notGenerated;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Invoice deleted')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting invoice: $e')));
      }
    }
  }

  void requestInvoice(Map<String, dynamic> shipment) async {
    // Prioritize Agent, else Truck Owner
    final agentId = shipment['assigned_agent']?.toString();
    final truckOwnerId = shipment['assigned_truck_owner']?.toString();

    String? requestToId;
    if (agentId != null && agentId.trim().isNotEmpty) {
      requestToId = agentId;
    } else if (truckOwnerId != null && truckOwnerId.trim().isNotEmpty) {
      requestToId = truckOwnerId;
    }

    if (requestToId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot request: No agent or truck owner assigned'),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Requested invoice for Shipment ${shipment['shipment_id']}',
        ),
      ),
    );

    try {
      await Supabase.instance.client.from('invoice_requests').insert({
        'shipment_id': shipment['shipment_id'],
        'requested_by': customUserId,
        'requested_to': requestToId,
      });

      await _sendInvoiceRequestNotification(shipment, requestToId);

      if (mounted) {
        setState(() {
          _invoiceRequests.add(shipment['shipment_id']);
        });
      }
    } catch (e) {
      debugPrint("Exception while requesting invoice: $e");
    }
  }

  Future shareInvoice(Map shipment) async {
    final shipmentId = shipment['shipment_id'].toString();
    final publicUrl = shipment['Invoice_link'] as String?;

    if (publicUrl == null || publicUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('pdf_link_not_found'.tr())));
      return;
    }

    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: 'Here is the invoice for shipment $shipmentId: $publicUrl',
          subject: 'Invoice for $shipmentId',
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sharing invoice: $e')));
      }
    }
  }

  Future<void> _sendInvoiceRequestNotification(
      Map<String, dynamic> shipment,
      String receiverCustomId,
      ) async {
    final shipmentId = shipment['shipment_id'];

    // 1. Fetch Receiver UUID
    final receiverProfile = await Supabase.instance.client
        .from('user_profiles')
        .select('user_id')
        .eq('custom_user_id', receiverCustomId)
        .maybeSingle();

    final receiverUuid = receiverProfile?['user_id'] as String?;
    if (receiverUuid == null) return;

    // 2. Fetch Shipper Name
    final shipperProfile = await Supabase.instance.client
        .from('user_profiles')
        .select('name')
        .eq('custom_user_id', shipment['shipper_id'])
        .maybeSingle();
    final shipperName = shipperProfile?['name'] ?? 'A shipper';

    // 3. Notify Receiver
    await NotificationService.sendNotification(
      recipientUserId: receiverUuid,
      title: "Invoice Requested",
      message: "$shipperName requested an invoice for shipment $shipmentId.",
      data: {'type': 'invoice_request', 'shipment_id': shipmentId},
    );

    // 4. Notify Self (Confirmation)
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      await NotificationService.sendNotification(
        recipientUserId: currentUserId,
        title: "Invoice Requested",
        message: "You requested an invoice for shipment $shipmentId.",
        data: {'type': 'invoice_request_sent', 'shipment_id': shipmentId},
      );
    }
  }

  Future<void> _sendInvoiceGeneratedNotification(
      Map<String, dynamic> shipment,
      ) async {
    final shipperCustomId = shipment['shipper_id'] as String?;
    if (shipperCustomId == null) return;
    final shipmentId = shipment['shipment_id'];

    // 1. Fetch Shipper UUID
    final shipperProfile = await Supabase.instance.client
        .from('user_profiles')
        .select('user_id')
        .eq('custom_user_id', shipperCustomId)
        .maybeSingle();

    final shipperUuid = shipperProfile?['user_id'] as String?;
    if (shipperUuid == null) return;

    // 2. Notify Shipper
    await NotificationService.sendNotification(
      recipientUserId: shipperUuid,
      title: "Invoice Ready",
      message:
      "Your invoice for shipment $shipmentId is generated and ready to view.",
      data: {'type': 'invoice_generated', 'shipment_id': shipmentId},
    );

    // 3. Notify Self (Confirmation)
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      await NotificationService.sendNotification(
        recipientUserId: currentUserId,
        title: "Invoice Generated",
        message: "You generated an invoice for shipment $shipmentId.",
        data: {'type': 'invoice_generated_sent', 'shipment_id': shipmentId},
      );
    }
  }

  Future<void> fetchBankAndGst() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('bank_details, gst_number')
        .eq('user_id', user.id)
        .maybeSingle();

    if (response != null) {
      _gstController.text = response['gst_number'] ?? '';

      final bankJson = response['bank_details'];
      if (bankJson != null && bankJson.isNotEmpty) {
        List banks = [];
        if (bankJson is String) {
          banks = jsonDecode(bankJson);
        } else if (bankJson is List) {
          banks = bankJson;
        }

        Map primaryBank = banks.firstWhere(
              (b) => b['is_primary'] == true,
          orElse: () => banks.first,
        );

        _bankNameController.text = primaryBank['bank_name'] ?? '';
        _accountNumberController.text = primaryBank['account_number'] ?? '';
        _ifscController.text = primaryBank['ifsc_code'] ?? '';
        _branchController.text = primaryBank['branch'] ?? '';
        _accountHolderController.text =
            primaryBank['account_holder_name'] ?? '';
      }
    }
  }

  Future fetchBillingAddressForShipment(Map shipment) async {
    final shipperId = shipment['shipper_id'];
    if (shipperId == null) return null;

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('billing_address')
        .eq('custom_user_id', shipperId)
        .maybeSingle();

    if (response != null &&
        response['billing_address'] != null &&
        response['billing_address'] != '') {
      final map = jsonDecode(response['billing_address']);
      return BillingAddress.fromJson(map);
    }
    return null;
  }

  Future<List<CompanyAddress>> fetchCompanyAddresses() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('company_address1, company_address2, company_address3')
        .eq('user_id', user.id)
        .maybeSingle();

    final addresses = <CompanyAddress>[];
    if (response != null) {
      for (var key in [
        'company_address1',
        'company_address2',
        'company_address3',
      ]) {
        if (response[key] != null && response[key] != '') {
          final addrMap = jsonDecode(response[key]);
          addresses.add(CompanyAddress.fromJson(addrMap));
        }
      }
    }
    return addresses;
  }

  Future<CompanyAddress?> showCompanyAddressDialog(
      BuildContext context,
      List<CompanyAddress> addresses,
      ) async {
    return await showGeneralDialog<CompanyAddress>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'company_address'.tr(),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, child) {
        final curvedValue = Curves.easeInOut.transform(anim.value) - 1.0;
        return Transform(
          transform: Matrix4.translationValues(0.0, curvedValue * -50, 0.0),
          child: Opacity(
            opacity: anim.value,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_city,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'select_company_address'.tr(),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: addresses.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final addr = addresses[index];
                          return ListTile(
                            leading: const Icon(Icons.home_outlined),
                            title: Text(
                              "${addr.flatNo}, ${addr.streetName}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              "${addr.cityName}, ${addr.district}, ${addr.zipCode}",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                            onTap: () => Navigator.pop(ctx, addr),
                          );
                        },
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

  Future<void> _showGenerateInvoiceDialog(Map<String, dynamic> shipment) async {
    await fetchBankAndGst();

    final shipperId = shipment['shipper_id']?.toString();
    if (shipperId != null) {
      final customerInfo = await fetchCustomerNameAndMobile(shipperId);
      _billToNameController.text = customerInfo['name'] ?? '';
      _billToMobileNumberController.text = customerInfo['mobile_number'] ?? '';
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          void recalculateTotals() {
            final price = double.tryParse(_priceController.text) ?? 0.0;
            final taxPercent =
                double.tryParse(_taxPercentageController.text) ?? 0.0;

            if (taxPercent <= 0 || price <= 0) {
              setDialogState(() {
                _calculatedTax = 0.0;
                _calculatedTotal = price;
              });
              return;
            }

            setDialogState(() {
              _calculatedTax = (price * taxPercent) / 100;
              _calculatedTotal = price + _calculatedTax;
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "invoice_details".tr(),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            "company_information".tr(),
                            Icons.business,
                          ),
                          _buildTextField(
                            controller: _companyNameController,
                            label: "company_name".tr(),
                          ),
                          _buildTextField(
                            controller: _cMobileNumberController,
                            label: "company_mobile_no".tr(),
                            keyboard: TextInputType.phone,
                          ),
                          _buildTextField(
                            controller: _gstController,
                            label: "gst_number".tr(),
                          ),

                          const SizedBox(height: 16),
                          _buildSectionHeader(
                            "bank_details".tr(),
                            Icons.account_balance,
                          ),
                          _buildTextField(
                            controller: _bankNameController,
                            label: "bank_name".tr(),
                          ),
                          _buildTextField(
                            controller: _accountNumberController,
                            label: "account_number".tr(),
                            keyboard: TextInputType.number,
                          ),
                          _buildTextField(
                            controller: _ifscController,
                            label: "ifsc_code".tr(),
                          ),
                          _buildTextField(
                            controller: _branchController,
                            label: "branch".tr(),
                          ),
                          _buildTextField(
                            controller: _accountHolderController,
                            label: "account_holder_name".tr(),
                          ),

                          const SizedBox(height: 16),
                          _buildSectionHeader(
                            "customer_information".tr(),
                            Icons.person_outline,
                          ),
                          _buildTextField(
                            controller: _billToNameController,
                            label: "customer_name".tr(),
                          ),
                          _buildTextField(
                            controller: _billToMobileNumberController,
                            label: "customer_mobile_no".tr(),
                            keyboard: TextInputType.phone,
                          ),

                          const SizedBox(height: 16),
                          _buildSectionHeader("Invoice Data", Icons.receipt),
                          _buildTextField(
                            controller: _invoiceNumberController,
                            label: "invoice_no".tr(),
                          ),
                          _buildTextField(
                            controller: _priceController,
                            label: "price".tr(),
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => recalculateTotals(),
                          ),

                          const SizedBox(height: 16),
                          _buildSectionHeader(
                            "tax_details".tr(),
                            Icons.percent,
                          ),
                          _buildTextField(
                            controller: _taxPercentageController,
                            label: "tax_percentage".tr(),
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => recalculateTotals(),
                          ),

                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: RadioGroup<TaxType>(
                              groupValue: _selectedTaxType,
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() {
                                    _selectedTaxType = val;
                                    recalculateTotals();
                                  });
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<TaxType>(
                                    title: Text("within_state".tr()),
                                    value: TaxType.withinState,
                                  ),
                                  RadioListTile<TaxType>(
                                    title: Text("outside_state".tr()),
                                    value: TaxType.outsideState,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Tax Summary
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Tax Amount:"),
                                    Text(
                                      "₹${_calculatedTax.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Total:",
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    Text(
                                      "₹${_calculatedTotal.toStringAsFixed(2)}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Action Buttons
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text("cancel".tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (_validateInvoiceForm()) {
                                Navigator.pop(context);
                                await generateInvoice(shipment);
                                _clearInvoiceForm();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text("generate".tr()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType? keyboard,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blueAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  bool _validateInvoiceForm() {
    if (_companyNameController.text.isEmpty ||
        _cMobileNumberController.text.isEmpty ||
        _gstController.text.isEmpty ||
        _bankNameController.text.isEmpty ||
        _accountNumberController.text.isEmpty ||
        _ifscController.text.isEmpty ||
        _branchController.text.isEmpty ||
        _accountHolderController.text.isEmpty ||
        _billToNameController.text.isEmpty ||
        _billToMobileNumberController.text.isEmpty ||
        _invoiceNumberController.text.isEmpty ||
        _priceController.text.isEmpty ||
        _taxPercentageController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('please_fill_required'.tr())));
      return false;
    }
    return true;
  }

  void _clearInvoiceForm() {
    _companyNameController.clear();
    _cMobileNumberController.clear();
    _gstController.clear();
    _bankNameController.clear();
    _accountNumberController.clear();
    _ifscController.clear();
    _branchController.clear();
    _accountHolderController.clear();
    _billToNameController.clear();
    _billToMobileNumberController.clear();
    _invoiceNumberController.clear();
    _priceController.clear();
    _taxPercentageController.clear();
    _calculatedTax = 0.0;
    _calculatedTotal = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_sortedMonths.isEmpty && filteredShipments.isNotEmpty) {
      _processShipmentData();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('shipment_history'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showSearch(
                context: context,
                delegate: ShipmentSearchDelegate(shipments: shipments),
              );
              if (result != null) searchShipments(result);
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showStatusFilterDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await fetchShipments();
        },
        child: loading
            ? buildSkeletonLoader()
            : filteredShipments.isEmpty
            ? buildEmptyState()
            : Column(
          children: [
            _buildMonthDropdown(),
            const Divider(thickness: 1, height: 1),
            Expanded(child: _buildShipmentList()),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthDropdown() {
    if (_sortedMonths.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: "select_month".tr(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedMonth,
            isExpanded: true,
            hint: Text("choose_month".tr()),
            icon: const Icon(Icons.calendar_month, color: Colors.blue),
            onChanged: (value) => setState(() => selectedMonth = value),
            items: _sortedMonths.map((m) {
              return DropdownMenuItem(value: m, child: Text(getMonthLabel(m)));
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildShipmentList() {
    final shipmentsToShow = selectedMonth != null
        ? (_groupedShipments[selectedMonth] ?? [])
        : [];

    if (shipmentsToShow.isEmpty) {
      return Center(
        child: Text(
          "No shipments in $selectedMonth",
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 50),
      itemCount: shipmentsToShow.length,
      itemBuilder: (_, i) {
        final shipment = shipmentsToShow[i];
        final shipmentId = shipment['shipment_id'].toString();
        final isRequested = _invoiceRequests.contains(shipmentId);

        final status = shipment['booking_status']?.toString().toLowerCase() ?? '';

        return shipment_card.ShipmentCard(
          shipment: shipment,
          pdfStates: pdfStates,
          isInvoiceRequested: isRequested,
          customUserId: customUserId,
          role: role,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShipmentDetailsPage(
                  shipment: shipment,
                  isHistoryPage: true,
                ),
              ),
            );
          },

          // 👇 Invoice Actions ONLY if completed
          onPreviewInvoice: status == "completed"
              ? () => previewInvoice(context, shipmentId)
              : null,

          onDownloadInvoice: status == "completed"
              ? () async => await downloadInvoice(shipment)
              : null,

          onRequestInvoice: status == "completed"
              ? () => requestInvoice(shipment)
              : null,

          onGenerateInvoice: status == "completed"
              ? () => _showGenerateInvoiceDialog(shipment)
              : null,

          onDeleteInvoice: status == "completed"
              ? () async => await confirmAndDelete(context, shipment)
              : null,

          onShareInvoice: status == "completed"
              ? () async => await shareInvoice(shipment)
              : null,
        );
      },
    );
  }

  Widget buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Card(
            elevation: 2,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                radius: 20,
              ),
              title: Container(
                width: double.infinity,
                height: 16,
                color: Colors.grey,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 100, height: 12, color: Colors.grey),
                  const SizedBox(height: 4),
                  Container(width: 150, height: 12, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'no_shipments_found'.tr(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'try_refreshing_filters'.tr(),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: fetchShipments,
            icon: const Icon(Icons.refresh),
            label: Text('refresh'.tr()),
          ),
        ],
      ),
    );
  }
}

class ShipmentSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, dynamic>> shipments;

  ShipmentSearchDelegate({required this.shipments});

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => Container();

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.toLowerCase();
    if (q.isEmpty) {
      return Center(
        child: Text(
          "type_shipment_search".tr(),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final results = shipments.where((s) {
      final id = s['shipment_id']?.toString().toLowerCase() ?? '';
      final pickup = s['pickup']?.toString().toLowerCase() ?? '';
      final drop = s['drop']?.toString().toLowerCase() ?? '';
      return id.contains(q) || pickup.contains(q) || drop.contains(q);
    }).toList();

    if (results.isEmpty) {
      return Center(child: Text("No matching shipments for '$query'"));
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final s = results[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: const Icon(Icons.local_shipping, color: Colors.blue),
            title: Text(
              "Shipment ID: ${s['shipment_id']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${s['pickup']} -> ${s['drop']}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (s['delivery_date'] != null)
                  Text(
                    "Completed At: ${s['delivery_date']}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PdfPreviewScreen extends StatelessWidget {
  final String localPath;
  const PdfPreviewScreen({required this.localPath, Key? key}) : super(key: key);

  void sharePdf() {
    SharePlus.instance.share(
      ShareParams(files: [XFile(localPath)], text: 'sharing_invoice_pdf'.tr()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('invoice_preview'.tr()),
        actions: [
          IconButton(
            onPressed: sharePdf,
            icon: const Icon(Icons.share),
            tooltip: 'share_pdf'.tr(),
          ),
        ],
      ),
      body: PDFView(filePath: localPath),
    );
  }
}