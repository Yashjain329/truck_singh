import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signature/signature.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'models/bilty_model.dart';
import 'models/bilty_template.dart';
import 'transport_bilty_preview.dart';

class BiltyFormPage extends StatefulWidget {
  final BiltyModel? bilty; // For editing existing bilty
  final String shipmentId;

  const BiltyFormPage({super.key, this.bilty, required this.shipmentId});

  @override
  State<BiltyFormPage> createState() => _BiltyFormPageState();
}

class _BiltyFormPageState extends State<BiltyFormPage> {
  final _formKey = GlobalKey<FormState>();
  late PageController _pageController;
  int _currentStep = 0;
  bool _isLoading = false;

  // Template
  late BiltyTemplate _template;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _values = {};
  final Map<String, bool> _checkboxValues = {};
  final Map<String, List<GoodsItem>> _goodsItems = {'goods': []};

  // Dates
  DateTime? _biltyDate;
  DateTime? _pickupDate;
  DateTime? _deliveryDate;

  // Payment status
  String _selectedPaymentStatus = 'To Pay';

  // Signature controllers
  final SignatureController _senderSignatureController = SignatureController(
    penStrokeWidth: 3,
    exportBackgroundColor: Colors.white,
  );
  final SignatureController _driverSignatureController = SignatureController(
    penStrokeWidth: 3,
    exportBackgroundColor: Colors.white,
  );
  final SignatureController _clerkSignatureController = SignatureController(
    penStrokeWidth: 3,
    exportBackgroundColor: Colors.white,
  );

  // Company configuration controllers
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyAddressController =
  TextEditingController();
  final TextEditingController _companyCityController = TextEditingController();

  late final List<String> _stepTitles;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _template = BiltyTemplate.defaultTemplate;
    _initializeControllers();
    _loadDriverInfo(widget.shipmentId);
    _loadRouteDetails(widget.shipmentId);
    _loadTruckDetails(widget.shipmentId);
    _loadCompanyAddress();
    _loadgstin();
    _loadBankDetails();

    _initializeForm();

    _stepTitles = [
      'Company',
      'Basic',
      'Sender',
      'Recipient',
      'Vehicle',
      'Route',
      'Goods',
      'Charges',
      'Bank',
      'Terms',
      'Signatures',
      'Review',
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    _senderSignatureController.dispose();
    _driverSignatureController.dispose();
    _clerkSignatureController.dispose();
    _companyNameController.dispose();
    _companyAddressController.dispose();

    // Dispose all controllers in the _controllers map
    for (var controller in _controllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _initializeControllers() {
    // Initialize controllers for all text inputs
    for (var section in _template.sections) {
      for (var element in section.elements) {
        if (element.type == 'text_input' ||
            element.type == 'text_area' ||
            element.type == 'number_input') {
          _controllers[element.id] = TextEditingController();
        }
        if (element.type == 'checkbox_group' &&
            element.checkboxOptions != null) {
          for (var option in element.checkboxOptions!) {
            _checkboxValues[option.id] = false;
          }
        }
      }
    }

    // Ensure controllers exist for additional granular fields used in the form
    const List<String> extraFieldIds = [
      'bilty_type',
      'transporter_code',
      'branch_code',
      'transporter_name',
      'transporter_gstin',
      'chassis_no',
      'sender_name',
      'sender_address',
      'sender_email',
      'sender_pan',
      'sender_gstin',
      'sender_phone',
      'recipient_name',
      'recipient_address',
      'recipient_email',
      'recipient_pan',
      'recipient_gstin',
      'recipient_phone',
      'vehicle_type',
      'truck_owner_phone',
      'driver_address',
    ];

    for (final fieldId in extraFieldIds) {
      _controllers.putIfAbsent(fieldId, () => TextEditingController());
    }
  }

  void _initializeForm() {
    if (widget.bilty != null) {
      _populateFromExistingBilty();
    } else {
      _setDefaultValues();
    }
  }

  void _populateFromExistingBilty() {
    final bilty = widget.bilty!;
    final metadata = bilty.metadata;

    // Set basic values
    _values['bilty_no'] = bilty.biltyNo;
    _values['from_where'] = bilty.origin;
    _values['till_where'] = bilty.destination;

    // Populate from metadata
    if (metadata.isNotEmpty) {
      if (metadata['consignor'] != null) {
        final consignor = metadata['consignor'];
        _values['sender_details'] =
        '${consignor['name']} \n${consignor['address']}';
      }

      if (metadata['consignee'] != null) {
        final consignee = metadata['consignee'];
        _values['recipient_details'] =
        '${consignee['name']} \n${consignee['address']}';
      }

      if (metadata['vehicle'] != null) {
        final vehicle = metadata['vehicle'];
        _values['truck_no'] = vehicle['vehicle_number'] ?? '';
        _values['driver_name'] = vehicle['driver_name'] ?? '';
        _values['driver_phone'] = vehicle['driver_phone'] ?? '';
        _values['driver_license'] = vehicle['driver_license'] ?? '';
        _values['vehicle_type'] = vehicle['vehicle_type'] ?? '';
        _values['engine_no'] = vehicle['engine_number'] ?? '';
        _values['truck_owner_name'] = vehicle['truck_owner_name'] ?? '';
      }

      // Populate dates
      if (metadata['dates'] != null) {
        final dates = metadata['dates'];
        _biltyDate = dates['bilty_date'] != null
            ? DateTime.parse(dates['bilty_date'])
            : null;
        _deliveryDate = dates['delivery_date'] != null
            ? DateTime.parse(dates['delivery_date'])
            : null;
        _pickupDate = dates['pickup_date'] != null
            ? DateTime.parse(dates['pickup_date'])
            : null;
      }

      // Populate goods
      if (metadata['goods'] != null) {
        _goodsItems['goods'] = (metadata['goods'] as List)
            .map((item) => GoodsItem.fromJson(item))
            .toList();
      }

      // Populate charges
      if (metadata['charges'] != null) {
        final charges = metadata['charges'];
        _values['basic_fare'] = charges['basic_fare']?.toString() ?? '';
        _values['other_charges'] = charges['other_charges']?.toString() ?? '';
        _values['gst'] = charges['gst']?.toString() ?? '';
        _selectedPaymentStatus = charges['payment_status'] ?? 'To Pay';
      }

      // Populate bank details
      if (metadata['bank_details'] != null) {
        final bank = metadata['bank_details'];
        _values['bank_name'] = bank['bank_name'] ?? '';
        _values['account_name'] = bank['account_name'] ?? '';
        _values['account_no'] = bank['account_no'] ?? '';
        _values['ifsc_code'] = bank['ifsc_code'] ?? '';
      }

      // Populate extra charges
      if (metadata['extra_charges'] != null) {
        _checkboxValues.addAll(
          Map<String, bool>.from(metadata['extra_charges']),
        );
      }

      // Populate remarks
      _values['remarks'] = metadata['remarks'] ?? '';
    }

    // Set values in controllers
    _values.forEach((key, value) {
      if (_controllers.containsKey(key)) {
        _controllers[key]!.text = value.toString();
      }
    });
  }

  void _setDefaultValues() {
    // Generate bilty number
    _generateBiltyNumber();

    // Set default dates
    _biltyDate = DateTime.now();
    _pickupDate = DateTime.now();
    _deliveryDate = DateTime.now().add(Duration(days: 3));

    // Add default goods item
    _addGoodsItem();
  }

  /// Generates a more unique bilty number by including seconds and milliseconds.
  void _generateBiltyNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}';
    final biltyNo = 'BILTY-$dateStr-$timeStr';
    _values['bilty_no'] = biltyNo;
    if (_controllers.containsKey('bilty_no')) {
      _controllers['bilty_no']!.text = biltyNo;
    }
  }

  // Styled Components
  Widget _buildStyledCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.tealBlue, size: 20),
                ),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController? controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    int? maxLines,
    String? hint,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines ?? 1,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.tealBlue),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          filled: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Ensure label is always visible
          floatingLabelBehavior: FloatingLabelBehavior.always,
          // Prevent label truncation
          labelStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildStyledDateField({
    required String label,
    required IconData icon,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    String? formattedDate;
    if (value != null) {
      formattedDate =
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    }

    return Container(
      color: Theme.of(context).cardColor,
      margin: EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 6),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.tealBlue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      formattedDate ?? 'Select Date'.tr(),
                      style: TextStyle(

                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today,
                    color: AppColors.tealBlue,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _loadgstin() async {
    try {
      final customUserId = Supabase
          .instance
          .client
          .auth
          .currentUser
          ?.userMetadata?['custom_user_id'];
      if (customUserId == null) {
        print("No logged in user found");
        return;
      }

      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('name,mobile_number,email,gst_number,billing_address')
          .eq('custom_user_id', customUserId)
          .maybeSingle();

      if (response != null) {
        final rawAddress = response['billing_address'];

        String formattedAddress = '';
        if (rawAddress != null) {
          try {
            final Map<String, dynamic> addressMap = jsonDecode(rawAddress);
            formattedAddress = [
              addressMap['flatNo'],
              addressMap['streetName'],
              addressMap['cityName'],
              addressMap['district'],
            ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
          } catch (e) {
            print("Error decoding driver address: $e");
          }
        }
        setState(() {
          _controllers['sender_name'] ??= TextEditingController();
          _controllers['sender_phone'] ??= TextEditingController();
          _controllers['sender_email'] ??= TextEditingController();
          _controllers['sender_address'] ??= TextEditingController();
          _controllers['sender_gstin'] ??= TextEditingController();
          _controllers['sender_name']!.text = response['name'];
          _controllers['sender_phone']!.text = response['mobile_number'];
          _controllers['sender_email']!.text = response['email'];
          _controllers['sender_address']!.text = formattedAddress;
          _controllers['sender_gstin']!.text = response['gst_number'];
        });
      }
    } catch (e) {
      print("Error fetching GSTIN: $e");
    }
  }

  //--------------- loading driver details to driver details -------------------
  Future<void> _loadDriverInfo(String shipmentId) async {
    // Step 1: get assigned driver ID from shipment
    final shipment = await Supabase.instance.client
        .from('shipment')
        .select('assigned_driver')
        .eq('shipment_id', shipmentId)
        .maybeSingle();

    final assignedDriverId = shipment?['assigned_driver'];
    if (assignedDriverId == null) return;
    print('Shipment fetched: $shipment');
    print('Assigned driver: $assignedDriverId');

    // Step 2: fetch driver details from user_profiles
    final response = await Supabase.instance.client
        .from('user_profiles')
        .select(
      'name, mobile_number, company_address1, company_address2, company_address3',
    )
        .eq('custom_user_id', assignedDriverId)
        .maybeSingle();

    if (response != null) {
      // Decode company address if it exists
      final rawAddress =
          response['company_address1'] ??
              response['company_address2'] ??
              response['company_address3'];

      String formattedAddress = '';
      if (rawAddress != null) {
        try {
          final Map<String, dynamic> addressMap = jsonDecode(rawAddress);
          formattedAddress = [
            addressMap['flatNo'],
            addressMap['streetName'],
            addressMap['cityName'],
            addressMap['district'],
          ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
        } catch (e) {
          print("Error decoding driver address: $e");
        }
      }

      // Populate the existing _controllers
      setState(() {
        _controllers['driver_name'] ??= TextEditingController();
        _controllers['driver_name']!.text = response['name'] ?? '';
        _controllers['driver_phone'] ??= TextEditingController();
        _controllers['driver_phone']!.text = response['mobile_number'] ?? '';
        _controllers['driver_address'] ??= TextEditingController();
        _controllers['driver_address']!.text = formattedAddress;
        _controllers['driver_license'] ??= TextEditingController();
        _controllers['driver_license']!.text = '';
      });
    }
  }
  //------------- load truck details to truck information --------------------

  Future<void> _loadTruckDetails(String shipmentId) async {
    final shipment = await Supabase.instance.client
        .from('shipment')
        .select('assigned_truckowner, assigned_truck')
        .eq('shipment_id', shipmentId)
        .maybeSingle();

    if (shipment == null) return;
    final assignedTruckNumber = shipment['assigned_truck'];
    final assignedTruckOwnerId = shipment['assigned_truckowner'];

    if (assignedTruckNumber != null) {
      final truckResponse = await Supabase.instance.client
          .from('trucks')
          .select('truck_number, engine_number,chassis_number,vehicle_type')
          .eq('truck_number', assignedTruckNumber)
          .maybeSingle();
      print("truck number : $assignedTruckNumber");

      final ownerResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('name, mobile_number')
          .eq('custom_user_id', assignedTruckOwnerId)
          .maybeSingle();
      print("truck owner: $assignedTruckOwnerId");

      setState(() {
        if (truckResponse != null) {
          _controllers['truck_no'] ??= TextEditingController();
          _controllers['engine_no'] ??= TextEditingController();
          _controllers['chassis_no'] ??= TextEditingController();
          _controllers['vehicle_type'] ??= TextEditingController();

          _controllers['truck_no']!.text = truckResponse['truck_number'] ?? '';
          _controllers['engine_no']!.text =
              truckResponse['engine_number'] ?? '';
          _controllers['chassis_no']!.text =
              truckResponse['chassis_number'] ?? '';
          _controllers['vehicle_type']!.text =
              truckResponse['vehicle_type'] ?? '';
        }

        if (ownerResponse != null) {
          _controllers['truck_owner_name'] ??= TextEditingController();
          _controllers['truck_owner_phone'] ??= TextEditingController();

          _controllers['truck_owner_name']!.text = ownerResponse['name'] ?? '';
          _controllers['truck_owner_phone']!.text =
              ownerResponse['mobile_number'] ?? '';
        }
      });
    }
  }

  //-------------- loading bank details to Bank Details section --------------------
  Future<void> _loadBankDetails() async {
    final customUserId = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['custom_user_id'];

    if (customUserId == null) return;

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('bank_details')
        .eq('custom_user_id', customUserId)
        .maybeSingle();

    if (response != null && response['bank_details'] != null) {
      final bankList = response['bank_details'];
      if (bankList is List && bankList.isNotEmpty) {
        // Pick primary bank or first bank
        final bank = bankList.firstWhere(
              (b) => b['is_primary'] == true,
          orElse: () => bankList[0],
        );

        setState(() {
          _controllers['bank_name'] ??= TextEditingController();
          _controllers['account_name'] ??= TextEditingController();
          _controllers['account_no'] ??= TextEditingController();
          _controllers['ifsc_code'] ??= TextEditingController();
          _controllers['bank_name']!.text = bank['bank_name'] ?? '';
          _controllers['account_name']!.text =
              bank['account_holder_name'] ?? '';
          _controllers['account_no']!.text = bank['account_number'] ?? '';
          _controllers['ifsc_code']!.text = bank['ifsc_code'] ?? '';
        });
      }
    }
  }
  Future<void> _loadRouteDetails(String shipmentId) async {
    if (shipmentId.isEmpty) return;

    final shipment = await Supabase.instance.client
        .from('shipment')
        .select('pickup, drop, pickup_date, delivery_date')
        .eq('shipment_id', shipmentId)
        .maybeSingle();

    if (shipment != null) {
      setState(() {
        _controllers['from_where'] ??= TextEditingController();
        _controllers['till_where'] ??= TextEditingController();
        _controllers['from_where']!.text = shipment['pickup'] ?? '';
        _controllers['till_where']!.text = shipment['drop'] ?? '';
        if (shipment['pickup_date'] != null) {
          _pickupDate = DateTime.tryParse(shipment['pickup_date'].toString());
        }
        if (shipment['delivery_date'] != null) {
          _deliveryDate = DateTime.tryParse(
            shipment['delivery_date'].toString(),
          );
        }
      });
    }
  }

  Future<void> _loadCompanyAddress() async {
    final customUserId = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['custom_user_id'];

    if (customUserId == null) return;

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('company_address1, company_address2, company_address3')
        .eq('custom_user_id', customUserId)
        .maybeSingle();

    if (response != null) {
      // Pick the first non-null address
      final rawAddress =
          response['company_address1'] ??
              response['company_address2'] ??
              response['company_address3'];

      if (rawAddress != null) {
        try {
          // Decode the JSON string into a Map
          final Map<String, dynamic> addressMap = jsonDecode(rawAddress);

          // Build a readable string
          final formattedAddress = [
            addressMap['flatNo'],
            addressMap['streetName'],
            addressMap['cityName'],
            addressMap['district'],
          ].where((e) => e != null && e.toString().isNotEmpty).join(', ');

          setState(() {
            _companyAddressController.text = formattedAddress;
          });
        } catch (e) {
          print("Error decoding address: $e");
        }
      }
    }
  }

  Future<DateTime?> _showStyledDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    return await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  void _addGoodsItem() {
    setState(() {
      _goodsItems['goods']!.add(
        GoodsItem(
          description: '',
          quantity: 1,
          weight: 0.0,
          rate: 0.0,
          amount: 0.0,
        ),
      );
    });
  }

  void _removeGoodsItem(int index) {
    setState(() {
      _goodsItems['goods']!.removeAt(index);
    });
  }


  // Opens a bottom sheet to add or edit a goods item to reduce congestion in the main UI
  void _openGoodsEditor({int? index}) {
    final bool isEditing = index != null;
    final GoodsItem initial = isEditing
        ? _goodsItems['goods']![index]
        : GoodsItem(
      description: '',
      quantity: 1,
      weight: 0.0,
      rate: 0.0,
      amount: 0.0,
    );

    final TextEditingController descriptionController = TextEditingController(
      text: initial.description,
    );
    final TextEditingController weightController = TextEditingController(
      text: initial.weight == 0 ? '' : initial.weight.toString(),
    );
    final TextEditingController qtyController = TextEditingController(
      text: initial.quantity.toString(),
    );
    final TextEditingController rateController = TextEditingController(
      text: initial.rate == 0 ? '' : initial.rate.toString(),
    );

    double computedAmount = initial.rate * initial.quantity;
    final TextEditingController amountController = TextEditingController(
      text: computedAmount.toStringAsFixed(2),
    );
    bool listenersAdded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void recomputeAmount() {
              final double rate =
                  double.tryParse(rateController.text.trim()) ?? 0;
              final int qty = int.tryParse(qtyController.text.trim()) ?? 0;
              setModalState(() {
                computedAmount = rate * qty;
              });
              amountController.text = computedAmount.toStringAsFixed(2);
            }

            if (!listenersAdded) {
              rateController.addListener(recomputeAmount);
              qtyController.addListener(recomputeAmount);
              listenersAdded = true;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEditing ? 'edit_item'.tr() : 'add_item'.tr(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStyledTextField(
                      controller: descriptionController,
                      label: 'description'.tr(),
                      icon: Icons.description,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStyledTextField(
                            controller: weightController,
                            label: 'weight_tons'.tr(),
                            icon: Icons.balance,
                            keyboardType: TextInputType.number,
                            onTap: null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStyledTextField(
                            controller: qtyController,
                            label: 'quantity'.tr(),
                            icon: Icons.confirmation_number,
                            keyboardType: TextInputType.number,
                            onTap: null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStyledTextField(
                            controller: rateController,
                            label: 'rate'.tr(),
                            icon: Icons.currency_rupee,
                            keyboardType: TextInputType.number,
                            onTap: null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            controller: amountController,
                            decoration: InputDecoration(
                              labelText: 'amount'.tr(),
                              prefixIcon: const Icon(Icons.summarize),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: Text(
                          isEditing ? 'save_changes'.tr() : 'add_item'.tr(),
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.tealBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          final String desc = descriptionController.text.trim();
                          final double weight =
                              double.tryParse(weightController.text.trim()) ??
                                  0;
                          final int qty =
                              int.tryParse(qtyController.text.trim()) ?? 0;
                          final double rate =
                              double.tryParse(rateController.text.trim()) ?? 0;
                          final double amount = rate * qty;

                          final GoodsItem newItem = GoodsItem(
                            description: desc,
                            quantity: qty,
                            weight: weight,
                            rate: rate,
                            amount: amount,
                          );

                          setState(() {
                            if (isEditing) {
                              _goodsItems['goods']![index] = newItem;
                            } else {
                              _goodsItems['goods']!.add(newItem);
                            }
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      setState(() {});
    });
  }

  Widget _buildGoodsInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  double _calculateTotalAmount() {
    double basicFare =
        double.tryParse(_controllers['basic_fare']?.text ?? '0') ?? 0;
    double otherCharges =
        double.tryParse(_controllers['other_charges']?.text ?? '0') ?? 0;
    double gstPercent = double.tryParse(_controllers['gst']?.text ?? '0') ?? 0;

    // Add goods amounts
    double goodsTotal = 0;
    for (var item in _goodsItems['goods']!) {
      goodsTotal += item.amount;
    }

    // Subtotal before GST
    double subtotal = basicFare + otherCharges + goodsTotal;

    // GST as a percentage of subtotal
    double gstAmount = subtotal * (gstPercent / 100);

    return subtotal + gstAmount;
  }
  Widget _buildCompanySettingsStep() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildStyledCard(
            title: 'company_information'.tr(),
            icon: Icons.business,
            child: Column(
              children: [
                _buildStyledTextField(
                  controller: _companyNameController,
                  label: 'company_name'.tr(),
                  icon: Icons.business,
                  hint: 'enter_company_name'.tr(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'please_enter_company_name'.tr();
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                CompanyAddressDropdown(
                  companyAddressController: _companyAddressController,
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
          SizedBox(height: 20),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'pdf_header_note'.tr(),
                    style: TextStyle(color: Colors.blue.shade700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicDetailsStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'bilty_information'.tr(),
          icon: Icons.receipt,
          child: Column(
            children: [
              _buildStyledTextField(
                controller: _controllers['bilty_no'],
                label: 'bilty_number'.tr(),
                icon: Icons.receipt,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'please_enter_bilty_number'.tr();
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['bilty_type'],
                    label: 'bilty_type'.tr(),
                    icon: Icons.category,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter bilty Type';
                      }
                      return null;
                    },
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['transporter_code'],
                    label: 'transporter_code'.tr(),
                    icon: Icons.code,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_transporter_code'.tr();
                      }
                      return null;
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['branch_code'],
                    label: 'branch_code'.tr(),
                    icon: Icons.business,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_branch_code'.tr();
                      }
                      return null;
                    },
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['transporter_name'],
                    label: 'transporter_name'.tr(),
                    icon: Icons.business,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_transporter_name'.tr();
                      }
                      return null;
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildStyledDateField(
                label: 'bilty_date'.tr(),
                icon: Icons.calendar_today,
                value: _biltyDate,
                onTap: () async {
                  if (_pickupDate == null || _deliveryDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('pickup_or_delivery_date_missing'.tr()),
                      ),
                    );
                    return;
                  }

                  // Ensure firstDate <= lastDate
                  final firstDate = _pickupDate!.isBefore(_deliveryDate!)
                      ? _pickupDate!
                      : _deliveryDate!;
                  final lastDate = _deliveryDate!.isAfter(_pickupDate!)
                      ? _deliveryDate!
                      : _pickupDate!;

                  final date = await _showStyledDatePicker(
                    context: context,
                    initialDate: _biltyDate != null
                        ? (_biltyDate!.isBefore(firstDate)
                        ? firstDate
                        : (_biltyDate!.isAfter(lastDate)
                        ? lastDate
                        : _biltyDate!))
                        : firstDate,
                    firstDate: firstDate,
                    lastDate: lastDate,
                  );

                  if (date != null && mounted) {
                    setState(() {
                      _biltyDate = date;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSenderDetailsStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'sender_information'.tr(),
          icon: Icons.person,
          child: Column(
            children: [
              _buildStyledTextField(
                controller: _controllers['sender_name'],
                label: 'sender_name'.tr(),
                icon: Icons.person,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'please_enter_sender_name'.tr();
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              _buildStyledTextField(
                controller: _controllers['sender_address'],
                label: 'sender_address'.tr(),
                icon: Icons.location_on,
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'please_enter_sender_address'.tr();
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['sender_phone'],
                    label: 'sender_phone'.tr(),
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['sender_email'],
                    label: 'sender_email'.tr(),
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['sender_gstin'],
                    label: 'sender_gstin'.tr(),
                    icon: Icons.receipt_long,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_gstin'.tr();
                      }
                      return null;
                    },
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['sender_pan'],
                    label: 'sender_pan'.tr(),
                    icon: Icons.credit_card,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecipientDetailsStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'recipient_information'.tr(),
          icon: Icons.person_outline,
          child: Column(
            children: [
              _buildStyledTextField(
                controller: _controllers['recipient_name'],
                label: 'recipient_name'.tr(),
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'please_enter_recipient_name'.tr();
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              _buildStyledTextField(
                controller: _controllers['recipient_address'],
                label: 'recipient_address'.tr(),
                icon: Icons.home,
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'please_enter_recipient_address'.tr();
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['recipient_phone'],
                    label: 'recipient_phone'.tr(),
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['recipient_email'],
                    label: 'recipient_email'.tr(),
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_recipient_email'.tr();
                      }
                      return null;
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['recipient_gstin'],
                    label: 'recipient_gstin'.tr(),
                    icon: Icons.receipt_long,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_gstin'.tr();
                      }
                      return null;
                    },
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['recipient_pan'],
                    label: 'recipient_pan'.tr(),
                    icon: Icons.credit_card,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleDriverStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'vehicle_information'.tr(),
          icon: Icons.local_shipping,
          child: Column(
            children: [
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['truck_no'],
                    label: 'truck_number'.tr(),
                    icon: Icons.local_shipping,
                  ),
                  _buildResponsiveTextField(
                    controller: _controllers['engine_no'],
                    label: 'engine_number'.tr(),
                    icon: Icons.build,
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _ctrl('chassis_no'),
                    label: 'chassis_number'.tr(),
                    icon: Icons.confirmation_number,
                  ),
                  _buildResponsiveTextField(
                    controller: _controllers['vehicle_type'],
                    label: 'vehicle_type'.tr(),
                    icon: Icons.category,
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['truck_owner_name'],
                    label: 'truck_owner_name'.tr(),
                    icon: Icons.person,
                  ),
                  _buildResponsiveTextField(
                    controller: _controllers['truck_owner_phone'],
                    label: 'truck_owner_phone'.tr(),
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        _buildStyledCard(
          title: 'driver_information'.tr(),
          icon: Icons.drive_eta,
          child: Column(
            children: [
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['driver_name'],
                    label: 'driver_name'.tr(),
                    icon: Icons.drive_eta,
                  ),
                  _buildResponsiveTextField(
                    controller: _controllers['driver_phone'],
                    label: 'driver_phone'.tr(),
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['driver_license'],
                    label: 'driver_license'.tr(),
                    icon: Icons.card_membership,
                  ),
                  _buildResponsiveTextField(
                    controller: _controllers['driver_address'],
                    label: 'driver_address'.tr(),
                    icon: Icons.location_on,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteDatesStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'route_information'.tr(),
          icon: Icons.route,
          child: Column(
            children: [
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['from_where'],
                    label: 'from_where'.tr(),
                    icon: Icons.place,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_origin'.tr();
                      }
                      return null;
                    },
                  ),
                  _buildResponsiveTextField(
                    controller: _controllers['till_where'],
                    label: 'till_where'.tr(),
                    icon: Icons.map,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_destination'.tr();
                      }
                      return null;
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildStyledCard(
                title: 'date_information'.tr(),
                icon: Icons.calendar_today,
                child: Column(
                  children: [
                    _buildResponsiveRow(
                      children: [
                        _buildStyledDateField(
                          label: 'pickup_date'.tr(),
                          icon: Icons.calendar_today,
                          value: _pickupDate,
                          onTap: () async {
                            final date = await _showStyledDatePicker(
                              context: context,
                              initialDate: _pickupDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setState(() {
                                _pickupDate = date;
                              });
                            }
                          },
                        ),
                        SizedBox(width: 16),
                        _buildStyledDateField(
                          label: 'delivery_date'.tr(),
                          icon: Icons.event,
                          value: _deliveryDate,
                          onTap: () async {
                            final date = await _showStyledDatePicker(
                              context: context,
                              initialDate: _deliveryDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setState(() {
                                _deliveryDate = date;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoodsDetailsStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'goods_and_charges'.tr(),
          icon: Icons.inventory,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'goods_items'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.tealBlue,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.tealBlue,
                          AppColors.tealBlue.withAlpha((0.8 * 255).round()),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _openGoodsEditor(),
                      icon: Icon(Icons.add, color: Colors.white, size: 18),
                      label: Text(
                        'add_item'.tr(),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              ..._goodsItems['goods']!.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.03 * 255).round()),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.description.isEmpty
                                  ? 'no_description'.tr()
                                  : item.description,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'edit'.tr(),
                                onPressed: () => _openGoodsEditor(index: index),
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              IconButton(
                                tooltip: 'delete'.tr(),
                                onPressed: () => _removeGoodsItem(index),
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildGoodsInfoChip('wt', (item.weight).toString()),
                          _buildGoodsInfoChip(
                            'qty',
                            (item.quantity).toString(),
                          ),
                          _buildGoodsInfoChip('rate', (item.rate).toString()),
                          _buildGoodsInfoChip(
                            'amt',
                            (item.amount).toStringAsFixed(2),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        SizedBox(height: 16),
        _buildStyledCard(
          title: 'charges'.tr(),
          icon: Icons.attach_money,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStyledTextField(
                      controller: _controllers['basic_fare'],
                      label: 'basic_fare_star'.tr(),
                      icon: Icons.money,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _buildStyledTextField(
                      controller: _controllers['other_charges'],
                      label: 'other_charges_optional'.tr(),
                      icon: Icons.receipt,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStyledTextField(
                      controller: _controllers['gst'],
                      label: 'gst_in_percent'.tr(),
                      icon: Icons.account_balance,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).cardColor,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPaymentStatus,
                        decoration: InputDecoration(
                          labelText: ' payment_status'.tr(),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: ['To Pay', 'Paid', 'Partial'].map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPaymentStatus = value!;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChargesPaymentStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'charges_details'.tr(),
          icon: Icons.attach_money,
          child: Column(
            children: [
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['basic_fare'],
                    label: 'basic_fare'.tr(),
                    icon: Icons.money,
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['other_charges'],
                    label: 'other_charges'.tr(),
                    icon: Icons.receipt,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStyledTextField(
                      controller: _controllers['gst'],
                      label: 'gst'.tr(),
                      icon: Icons.account_balance,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPaymentStatus,
                        decoration: InputDecoration(
                          labelText: 'payment_status'.tr(),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: ['To Pay'.tr(), 'Paid', 'Partial'].map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPaymentStatus = value!;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.tealBlue.withAlpha((0.1 * 255).round()),
                      AppColors.tealBlue.withAlpha((0.05 * 255).round()),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.tealBlue.withAlpha((0.2 * 255).round()),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'total_amount'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.tealBlue,
                      ),
                    ),
                    Text(
                      '₹${_calculateTotalAmount().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.tealBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        _buildStyledCard(
          title: 'extra_charges'.tr(),
          icon: Icons.add_shopping_cart,
          child: Column(
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildStyledCheckbox(
                    title: 'labour_charge'.tr(),
                    value: _checkboxValues['labour_charge'] ?? false,
                    onChanged: (value) {
                      setState(() {
                        _checkboxValues['labour_charge'] = value ?? false;
                      });
                    },
                  ),
                  _buildStyledCheckbox(
                    title: 'fork_expense'.tr(),
                    value: _checkboxValues['fork_expence'] ?? false,
                    onChanged: (value) {
                      setState(() {
                        _checkboxValues['fork_expence'] = value ?? false;
                      });
                    },
                  ),
                  _buildStyledCheckbox(
                    title: 'detention_charge'.tr(),
                    value: _checkboxValues['detention_charge'] ?? false,
                    onChanged: (value) {
                      setState(() {
                        _checkboxValues['detention_charge'] = value ?? false;
                      });
                    },
                  ),
                  _buildStyledCheckbox(
                    title: 'other_charges'.tr(),
                    value: _checkboxValues['other_charges'] ?? false,
                    onChanged: (value) {
                      setState(() {
                        _checkboxValues['other_charges'] = value ?? false;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStyledCheckbox({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      width: double.infinity,
      child: CheckboxListTile(
        title: Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        value: value,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildBankDetailsStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'bank_details'.tr(),
          icon: Icons.account_balance,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStyledTextField(
                      controller: _controllers['bank_name'],
                      label: 'bank_name_star'.tr(),
                      icon: Icons.account_balance,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'please_enter_bank_name'.tr();
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _buildStyledTextField(
                      controller: _controllers['account_name'],
                      label: 'account_name_star'.tr(),
                      icon: Icons.person_pin,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'please_enter_account_name'.tr();
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              _buildResponsiveRow(
                children: [
                  _buildResponsiveTextField(
                    controller: _controllers['account_no'],
                    label: 'account_number_star'.tr(),
                    icon: Icons.account_box,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_account_number'.tr();
                      }
                      return null;
                    },
                  ),
                  SizedBox(width: 16),
                  _buildResponsiveTextField(
                    controller: _controllers['ifsc_code'],
                    label: 'ifsc_code_star'.tr(),
                    icon: Icons.code,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'please_enter_ifsc_code'.tr();
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        _buildStyledCard(
          title: 'remarks_instructions'.tr(),
          icon: Icons.note,
          child: Column(
            children: [
              _buildStyledTextField(
                controller: _controllers['remarks'],
                label: 'special_instructions_optional'.tr(),
                icon: Icons.edit_note,
                maxLines: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsConditionsStep() {
    return Column(
      children: [
        _buildStyledCard(
          title: 'terms_conditions'.tr(),
          icon: Icons.gavel,
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'important_terms'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'important_terms_text'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              _buildStyledCheckbox(
                title: 'agree_terms'.tr(),
                value: _checkboxValues['terms_conditions'] ?? false,
                onChanged: (value) {
                  setState(() {
                    _checkboxValues['terms_conditions'] = value ?? false;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignaturesStep() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildStyledCard(
            title: 'sender_signature'.tr(),
            icon: Icons.person,
            child: Column(
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth > 0
                          ? constraints.maxWidth
                          : double.infinity;
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 198,
                          minWidth: width,
                        ),
                        child: RepaintBoundary(
                          child: Signature(
                            controller: _senderSignatureController,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _senderSignatureController.clear(),
                        icon: Icon(Icons.clear, size: 18),
                        label: Text('clear'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _senderSignatureController.undo(),
                        icon: Icon(Icons.undo, size: 18),
                        label: Text('undo'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade100,
                          foregroundColor: Colors.orange.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildReviewSubmitStep() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Basic Details
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'basic_details'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _buildSummaryRow(
                    'bilty_number'.tr(),
                    _controllers['bilty_no']?.text ?? '',
                  ),
                  _buildSummaryRow('bilty_type'.tr(), _val('bilty_type')),
                  _buildSummaryRow(
                    'transporter_code'.tr(),
                    _val('transporter_code'),
                  ),
                  _buildSummaryRow('branch_code', _val('branch_code')),
                  _buildSummaryRow(
                    'bilty_date'.tr(),
                    _biltyDate != null
                        ? '${_biltyDate!.day}/${_biltyDate!.month}/${_biltyDate!.year}'
                        : '',
                  ),
                  _buildSummaryRow(
                    'pickup_date'.tr(),
                    _pickupDate != null
                        ? '${_pickupDate!.day}/${_pickupDate!.month}/${_pickupDate!.year}'
                        : '',
                  ),
                  _buildSummaryRow(
                    'delivery_date'.tr(),
                    _deliveryDate != null
                        ? '${_deliveryDate!.day}/${_deliveryDate!.month}/${_deliveryDate!.year}'
                        : '',
                  ),
                  _buildSummaryRow(
                    'from'.tr(),
                    _controllers['from_where']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'to'.tr(),
                    _controllers['till_where']?.text ?? '',
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Parties
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'parties'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _buildSummaryRow('sender_name'.tr(), _val('sender_name')),
                  _buildSummaryRow(
                    'sender_address'.tr(),
                    _val('sender_address'),
                  ),
                  _buildSummaryRow('sender_gstin'.tr(), _val('sender_gstin')),
                  _buildSummaryRow('sender_phone'.tr(), _val('sender_phone')),
                  SizedBox(height: 12),
                  _buildSummaryRow(
                    'recipient_name'.tr(),
                    _val('recipient_name'),
                  ),
                  _buildSummaryRow(
                    'recipient_address'.tr(),
                    _val('recipient_address'),
                  ),
                  _buildSummaryRow(
                    'recipient_gstin'.tr(),
                    _val('recipient_gstin'),
                  ),
                  _buildSummaryRow(
                    'recipient_phone'.tr(),
                    _val('recipient_phone'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Vehicle Details
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vehicle_details'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _buildSummaryRow(
                    'truck_number'.tr(),
                    _controllers['truck_no']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'engine_number'.tr(),
                    _controllers['engine_no']?.text ?? '',
                  ),
                  _buildSummaryRow('chassis_number'.tr(), _val('chassis_no')),
                  _buildSummaryRow(
                    'vehicle_type'.tr(),
                    _controllers['vehicle_type']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'truck_owner_name'.tr(),
                    _controllers['truck_owner_name']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'truck_owner_phone'.tr(),
                    _val('truck_owner_phone'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Goods
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'goods'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  ..._goodsItems['goods']!
                      .map(
                        (item) => _buildSummaryRow(
                      '${item.description}',
                      'Qty: ${item.quantity},Weight: ${item.weight}, Rate: ${item.rate}, Amount: ${item.amount}',
                    ),
                  )
                      .toList(),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Charges
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'charges'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _buildSummaryRow(
                    'basic_fare'.tr(),
                    '₹ ${_controllers['basic_fare']?.text ?? ''}',
                  ),
                  _buildSummaryRow(
                    'other_charges'.tr(),
                    '₹ ${_controllers['other_charges']?.text ?? ''}',
                  ),
                  _buildSummaryRow(
                    'gst'.tr(),
                    '${_controllers['gst']?.text ?? ''} %',
                  ),
                  _buildSummaryRow(
                    'payment_status'.tr(),
                    _selectedPaymentStatus,
                  ),
                  _buildSummaryRow(
                    'total_amount:'.tr(),
                    '₹ ${_calculateTotalAmount().toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Bank Details
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'bank_details'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _buildSummaryRow(
                    'bank_name'.tr(),
                    _controllers['bank_name']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'account_name'.tr(),
                    _controllers['account_name']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'account_number'.tr(),
                    _controllers['account_no']?.text ?? '',
                  ),
                  _buildSummaryRow(
                    'ifsc_code'.tr(),
                    _controllers['ifsc_code']?.text ?? '',
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Remarks
          if (_controllers['remarks']?.text.isNotEmpty == true)
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'remarks'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildSummaryRow(
                      'special_instructions'.tr(),
                      _controllers['remarks']?.text ?? '',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTotal ? AppColors.tealBlue : null,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTotal ? AppColors.tealBlue : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextStep() {
    if (_currentStep < _stepTitles.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // Safely read a field value from controller or fallback store
  String _val(String id) {
    final ctrl = _controllers.putIfAbsent(id, () => TextEditingController());
    final text = ctrl.text;
    if (text.isNotEmpty) return text;
    final fallback = _values[id]?.toString() ?? '';
    return fallback;
  }

  // Ensure a controller exists for a field and return it
  TextEditingController _ctrl(String id) {
    return _controllers.putIfAbsent(id, () => TextEditingController());
  }

  Future<void> _submitBilty() async {
    if (!_formKey.currentState!.validate()) {
      for (int i = 0; i < _stepTitles.length; i++) {
        setState(() => _currentStep = i);
        await Future.delayed(Duration(milliseconds: 50));
        if (!_formKey.currentState!.validate()) {
          _pageController.animateToPage(
            i,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          break;
        }
      }
      return;
    }

    if (_biltyDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('please_select_bilty_date'.tr())));
      _pageController.animateToPage(
        1,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (_deliveryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_select_delivery_date'.tr())),
      );
      _pageController.animateToPage(
        1,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }
    if (_pickupDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('please_select_pickup_date'.tr())));
      return;
    }

    if (_deliveryDate != null && _deliveryDate!.isBefore(_pickupDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('delivery_date_before_pickup'.tr())),
      );
      return;
    }

    if (_deliveryDate!.isBefore(_biltyDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('delivery_date_before_bilty'.tr())),
      );
      _pageController.animateToPage(
        5,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('user_not_authenticated'.tr())));
        return;
      }
      final senderSignature = await _senderSignatureController.toPngBytes();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransportBiltyPreview(
            shipmentId: widget.shipmentId,
            biltyNo: _controllers['bilty_no']?.text ?? '',
            biltyType: _controllers['bilty_type']?.text,
            transporterCode: _controllers['transporter_code']?.text,
            branchCode: _controllers['branch_code']?.text,
            senderName: _controllers['sender_name']?.text ?? '',
            senderAddress: _controllers['sender_address']?.text ?? '',
            senderEmail: _controllers['sender_email']?.text,
            senderPAN: _controllers['sender_pan']?.text ?? '',
            senderGSTIN: _controllers['sender_gstin']?.text ?? '',
            senderPhone: _controllers['sender_phone']?.text ?? '',
            recipientName: _controllers['recipient_name']?.text ?? '',
            recipientAddress: _controllers['recipient_address']?.text ?? '',
            recipientEmail: _controllers['recipient_email']?.text,
            recipientPAN: _controllers['recipient_pan']?.text ?? '',
            recipientGSTIN: _controllers['recipient_gstin']?.text ?? '',
            recipientPhone: _controllers['recipient_phone']?.text ?? '',
            truckOwnerName: _controllers['truck_owner_name']?.text ?? '',
            truckOwnerPhone: _controllers['truck_owner_phone']?.text,
            driverName: _controllers['driver_name']?.text ?? '',
            driverAddress: _controllers['driver_address']?.text,
            chassisNo: _controllers['chassis_no']?.text ?? '',
            engineNo: _controllers['engine_no']?.text ?? '',
            truckNo: _controllers['truck_no']?.text ?? '',
            fromWhere: _controllers['from_where']?.text ?? '',
            tillWhere: _controllers['till_where']?.text ?? '',
            pickupDate: _pickupDate,
            biltyDate: _biltyDate,
            goods: _goodsItems['goods']!,
            basicFare: _controllers['basic_fare']?.text ?? '',
            otherCharges: _controllers['other_charges']?.text ?? '',
            gst: _controllers['gst']?.text ?? '',
            totalAmount: _calculateTotalAmount().toString(),
            paymentStatus: _selectedPaymentStatus,
            extraCharges: _checkboxValues,
            bankName: _controllers['bank_name']?.text ?? '',
            accountName: _controllers['account_name']?.text ?? '',
            accountNo: _controllers['account_no']?.text ?? '',
            ifscCode: _controllers['ifsc_code']?.text ?? '',
            remarks: _controllers['remarks']?.text ?? '',
            driverLicense: _controllers['driver_license']?.text ?? '',
            driverPhone: _controllers['driver_phone']?.text,
            vehicleType: _controllers['vehicle_type']?.text,
            transporterName: _controllers['transporter_name']?.text,
            transporterGSTIN: _controllers['transporter_gstin']?.text,
            deliveryDate: _deliveryDate,
            senderSignature: senderSignature != null
                ? base64Encode(senderSignature)
                : null,
            companyName: _companyNameController.text.isNotEmpty
                ? _companyNameController.text
                : null,
            companyAddress: _companyAddressController.text.isNotEmpty
                ? _companyAddressController.text
                : null,
            companyCity: _companyCityController.text.isNotEmpty
                ? _companyCityController.text
                : null,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error navigating to preview: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error preparing preview: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Widget _buildStepContent(int step) {
    switch (step) {
      case 0:
        return _buildCompanySettingsStep();
      case 1:
        return _buildBasicDetailsStep();
      case 2:
        return _buildSenderDetailsStep();
      case 3:
        return _buildRecipientDetailsStep();
      case 4:
        return _buildVehicleDriverStep();
      case 5:
        return _buildRouteDatesStep();
      case 6:
        return _buildGoodsDetailsStep();
      case 7:
        return _buildChargesPaymentStep();
      case 8:
        return _buildBankDetailsStep();
      case 9:
        return _buildTermsConditionsStep();
      case 10:
        return _buildSignaturesStep();
      case 11:
        return _buildReviewSubmitStep();
      default:
        return SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.bilty != null ? 'edit_bilty'.tr() : 'create_new_bilty'.tr(),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((0.2 * 255).round()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.visibility),
              tooltip: 'preview_bilty'.tr(),
              onPressed: _submitBilty,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_stepTitles.length, (index) {
                      final isCompleted = index < _currentStep;
                      final isActive = index == _currentStep;
                      return InkWell(
                        onTap: () => _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isActive
                                    ? AppColors.tealBlue
                                    : (isCompleted
                                    ? Colors.green
                                    : Colors.grey.shade300),
                                child: isCompleted
                                    ? Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                                    : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.black54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _stepTitles[index],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive
                                      ? AppColors.tealBlue
                                      : Colors.grey.shade600,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentStep = index;
                    });
                  },
                  itemCount: _stepTitles.length,
                  itemBuilder: (context, index) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildStepContent(index),
                    );
                  },
                ),
              ),
              Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _previousStep,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('previous'.tr()),
                        ),
                      ),
                    if (_currentStep > 0) SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _currentStep < _stepTitles.length - 1
                            ? _nextStep
                            : (_isLoading ? null : _submitBilty),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                        _isLoading && _currentStep == _stepTitles.length - 1
                            ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : Text(
                          _currentStep < _stepTitles.length - 1
                              ? 'next'.tr()
                              : 'submit'.tr(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveRow({
    required List<Widget> children,
  }) {
    final List<Widget> columnChildren = [];
    for (final w in children) {
      if (w is SizedBox && w.width != null && (w.width ?? 0) > 0) {
        columnChildren.add(const SizedBox(height: 12));
      } else  columnChildren.add(w);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: columnChildren,
    );
  }

  Widget _buildResponsiveTextField({
    required TextEditingController? controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    int? maxLines,
    String? hint,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: _buildStyledTextField(
        controller: controller,
        label: label,
        icon: icon,
        validator: validator,
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        hint: hint,
      ),
    );
  }
}

class CompanyAddressDropdown extends StatefulWidget {
  final TextEditingController companyAddressController;

  const CompanyAddressDropdown({
    required this.companyAddressController,
    super.key,
  });

  @override
  _CompanyAddressDropdownState createState() => _CompanyAddressDropdownState();
}

class _CompanyAddressDropdownState extends State<CompanyAddressDropdown> {
  List<String> _addresses = [];
  String? _selectedAddress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
  }

  Future<void> _fetchAddresses() async {
    final customUserId = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['custom_user_id'];
    if (customUserId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('company_address1, company_address2, company_address3')
          .eq('custom_user_id', customUserId)
          .maybeSingle();

      if (response != null) {
        List<String> addresses = [];

        for (var key in [
          'company_address1',
          'company_address2',
          'company_address3',
        ]) {
          final rawAddress = response[key];
          if (rawAddress != null && rawAddress.toString().isNotEmpty) {
            try {
              final Map<String, dynamic> addressMap = jsonDecode(rawAddress);
              String formattedAddress = [
                addressMap['flatNo'],
                addressMap['streetName'],
                addressMap['cityName'],
                addressMap['district'],
              ].where((e) => e != null && e.toString().isNotEmpty).join(', ');

              if (formattedAddress.isNotEmpty) {
                addresses.add(formattedAddress);
              }
            } catch (e) {
              print("Error decoding $key: $e");
            }
          }
        }

        setState(() {
          _addresses = addresses;
          if (_addresses.isNotEmpty) {
            _selectedAddress = _addresses.first;
            widget.companyAddressController.text = _selectedAddress!;
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _addresses = [];
          _selectedAddress = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching addresses: $e");
      setState(() {
        _addresses = [];
        _selectedAddress = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_addresses.isEmpty) {
      return Text("no_addresses_found".tr());
    }

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: "select_company_address".tr(),
        border: OutlineInputBorder(),
      ),
      initialValue: _selectedAddress,
      items: _addresses
          .map((addr) => DropdownMenuItem(value: addr, child: Text(addr)))
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedAddress = value;
          widget.companyAddressController.text = value ?? '';
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'please_select_address'.tr();
        }
        return null;
      },
    );
  }
}