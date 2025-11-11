import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';

class BillingAddress {
  String flatNo, streetName, cityName, district, zipCode;
  BillingAddress({
    required this.flatNo,
    required this.streetName,
    required this.cityName,
    required this.district,
    required this.zipCode,
  });
  Map<String, dynamic> toJson() => {
    'flatNo': flatNo,
    'streetName': streetName,
    'cityName': cityName,
    'district': district,
    'zipCode': zipCode,
  };
  factory BillingAddress.fromJson(Map<String, dynamic> json) => BillingAddress(
    flatNo: json['flatNo'] ?? '',
    streetName: json['streetName'] ?? '',
    cityName: json['cityName'] ?? '',
    district: json['district'] ?? '',
    zipCode: json['zipCode'] ?? '',
  );
}

class CompanyAddress {
  String flatNo, streetName, cityName, district, zipCode;
  CompanyAddress({
    required this.flatNo,
    required this.streetName,
    required this.cityName,
    required this.district,
    required this.zipCode,
  });
  Map<String, dynamic> toJson() => {
    'flatNo': flatNo,
    'streetName': streetName,
    'cityName': cityName,
    'district': district,
    'zipCode': zipCode,
  };
  factory CompanyAddress.fromJson(Map<String, dynamic> json) => CompanyAddress(
    flatNo: json['flatNo'] ?? '',
    streetName: json['streetName'] ?? '',
    cityName: json['cityName'] ?? '',
    district: json['district'] ?? '',
    zipCode: json['zipCode'] ?? '',
  );
}

class AddressBookPage extends StatefulWidget {
  const AddressBookPage({Key? key}) : super(key: key);
  @override
  _AddressBookPageState createState() => _AddressBookPageState();
}

class _AddressBookPageState extends State<AddressBookPage> {
  final supabase = Supabase.instance.client;
  final user = Supabase.instance.client.auth.currentUser;

  BillingAddress? _billingAddress;
  bool _loadingBilling = true;

  CompanyAddress? _companyAddress1;
  CompanyAddress? _companyAddress2;
  CompanyAddress? _companyAddress3;
  bool _loadingCompany = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<File> _getBillingFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/address.json');
  }
  Future<File> _getCompanyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/company_address.json');
  }

  Future<Map<String, dynamic>> _readJsonFile(File file) async {
    if (!await file.exists()) return {};
    final txt = await file.readAsString();
    return txt.isNotEmpty ? jsonDecode(txt) : {};
  }
  Future<void> _writeJsonFile(File file, Map<String, dynamic> data) async {
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> _loadAddresses() async {
    if (user == null) return;
    final userId = user!.id;

    // Load billing address from local JSON or Supabase fallback
    final billingFile = await _getBillingFile();
    final billingMap = await _readJsonFile(billingFile);
    if (billingMap.containsKey(userId)) {
      _billingAddress = BillingAddress.fromJson(billingMap[userId]);
    } else {
      final res = await supabase.from('user_profiles').select('billing_address').eq('user_id', userId).maybeSingle();
      if (res != null && res['billing_address'] != null && res['billing_address'] != "") {
        final bm = jsonDecode(res['billing_address']);
        _billingAddress = BillingAddress.fromJson(bm);
        billingMap[userId] = bm;
        await _writeJsonFile(billingFile, billingMap);
      }
    }
    _loadingBilling = false;

    // Load company addresses from local JSON or Supabase
    final companyFile = await _getCompanyFile();
    final companyMap = await _readJsonFile(companyFile);
    if (companyMap.containsKey(userId)) {
      var userAddrs = companyMap[userId] as Map<String, dynamic>;
      _companyAddress1 = userAddrs.containsKey('1') ? CompanyAddress.fromJson(userAddrs['1']) : null;
      _companyAddress2 = userAddrs.containsKey('2') ? CompanyAddress.fromJson(userAddrs['2']) : null;
      _companyAddress3 = userAddrs.containsKey('3') ? CompanyAddress.fromJson(userAddrs['3']) : null;
    } else {
      final res = await supabase.from('user_profiles').select('company_address1,company_address2,company_address3').eq('user_id', userId).maybeSingle();
      if (res != null) {
        Map<String, dynamic> userAddrs = {};
        if (res['company_address1'] != null && res['company_address1'] != "") {
          final c1 = jsonDecode(res['company_address1']);
          _companyAddress1 = CompanyAddress.fromJson(c1);
          userAddrs['1'] = c1;
        }
        if (res['company_address2'] != null && res['company_address2'] != "") {
          final c2 = jsonDecode(res['company_address2']);
          _companyAddress2 = CompanyAddress.fromJson(c2);
          userAddrs['2'] = c2;
        }
        if (res['company_address3'] != null && res['company_address3'] != "") {
          final c3 = jsonDecode(res['company_address3']);
          _companyAddress3 = CompanyAddress.fromJson(c3);
          userAddrs['3'] = c3;
        }
        companyMap[userId] = userAddrs;
        await _writeJsonFile(companyFile, companyMap);
      }
    }
    _loadingCompany = false;

    setState(() {});
  }

  Future<void> _saveBilling(BillingAddress address) async {
    if (user == null) return;
    final userId = user!.id;
    final billingFile = await _getBillingFile();
    final billingMap = await _readJsonFile(billingFile);
    billingMap[userId] = address.toJson();
    await _writeJsonFile(billingFile, billingMap);
    await supabase.from('user_profiles').update({'billing_address': jsonEncode(address.toJson())}).eq('user_id', userId);
    _billingAddress = address;
    setState(() {});
  }

  Future<void> _saveCompanyAddress(int slot, CompanyAddress address) async {
    if (user == null) return;
    final userId = user!.id;
    final key = slot.toString();
    final companyFile = await _getCompanyFile();
    final companyMap = await _readJsonFile(companyFile);
    Map<String, dynamic> userAddrs = companyMap[userId] is Map<String, dynamic> ? Map<String, dynamic>.from(companyMap[userId]) : {};
    userAddrs[key] = address.toJson();
    companyMap[userId] = userAddrs;
    await _writeJsonFile(companyFile, companyMap);
    await supabase.from('user_profiles').update({'company_address$key': jsonEncode(address.toJson())}).eq('user_id', userId);
    if (slot == 1) _companyAddress1 = address;
    else if (slot == 2) _companyAddress2 = address;
    else if (slot == 3) _companyAddress3 = address;
    setState(() {});
  }


  Future<void> _showBillingDialog() async {
    final flat = TextEditingController(text: _billingAddress?.flatNo ?? '');
    final street = TextEditingController(text: _billingAddress?.streetName ?? '');
    final city = TextEditingController(text: _billingAddress?.cityName ?? '');
    final district = TextEditingController(text: _billingAddress?.district ?? '');
    final zip = TextEditingController(text: _billingAddress?.zipCode ?? '');

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'billingAddress'.tr(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: flat,
                  decoration: InputDecoration(labelText: 'flatNo'.tr()),
                  validator: (value) => value!.trim().isEmpty ? 'Please enter flat number' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: street,
                  decoration: InputDecoration(labelText: 'streetName'.tr()),
                  validator: (value) => value!.trim().isEmpty ? 'Please enter street name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: city,
                  decoration: InputDecoration(labelText: 'cityName'.tr()),
                  validator: (value) => value!.trim().isEmpty ? 'Please enter city name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: district,
                  decoration: InputDecoration(labelText: 'district'.tr()),
                  validator: (value) => value!.trim().isEmpty ? 'Please enter district' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: zip,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'zipCode'.tr()),
                  validator: (value) => value!.trim().isEmpty ? 'Please enter zip code' : null,
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: Text('save'.tr()),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newAddr = BillingAddress(
                  flatNo: flat.text.trim(),
                  streetName: street.text.trim(),
                  cityName: city.text.trim(),
                  district: district.text.trim(),
                  zipCode: zip.text.trim(),
                );
                _saveBilling(newAddr);
                Navigator.pop(ctx);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBillingAddress() async {
    if (user == null) return;
    final userId = user!.id;

    try {
      // Update Supabase
      final res = await supabase
          .from('user_profiles')
          .update({'billing_address': null})
          .eq('user_id', userId);
      print('Supabase delete billing address response: $res');

      // Update local JSON file
      final file = await _getBillingFile();
      final billingData = await _readJsonFile(file);
      if (billingData.containsKey(userId)) {
        billingData.remove(userId);
        await _writeJsonFile(file, billingData);
        print('Local billing address deleted.');
      }

      // Clear state and refresh UI
      _billingAddress = null;
      setState(() {});

    } catch (e) {
      print('Error deleting billing address: $e');
    }
  }

  Future<void> _deleteCompanyAddress(int slot) async {
    if (user == null) return;
    final userId = user!.id;
    final key = slot.toString();

    // Update local JSON
    final companyFile = await _getCompanyFile();
    final companyMap = await _readJsonFile(companyFile);
    Map<String, dynamic> userAddrs = companyMap[userId] is Map<String, dynamic> ? Map<String, dynamic>.from(companyMap[userId]) : {};
    userAddrs.remove(key);
    companyMap[userId] = userAddrs;
    await _writeJsonFile(companyFile, companyMap);

    // Update Supabase
    await supabase.from('user_profiles').update({ 'company_address$key': null }).eq('user_id', userId);

    // Update state variables
    if (slot == 1) _companyAddress1 = null;
    else if (slot == 2) _companyAddress2 = null;
    else if (slot == 3) _companyAddress3 = null;

    setState(() {});
  }

  Future<void> _showCompanyDialog(int slot, [CompanyAddress? existing]) async {
    final flat = TextEditingController(text: existing?.flatNo ?? '');
    final street = TextEditingController(text: existing?.streetName ?? '');
    final city = TextEditingController(text: existing?.cityName ?? '');
    final district = TextEditingController(text: existing?.district ?? '');
    final zip = TextEditingController(text: existing?.zipCode ?? '');

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          existing == null ? 'addCompanyAddress'.tr() : 'editCompanyAddress'.tr(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: flat,
                    decoration: InputDecoration(labelText: 'flatNo'.tr()),
                    validator: (value) => value!.trim().isEmpty ? 'Please enter flat no' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: street,
                    decoration: InputDecoration(labelText: 'streetName'.tr()),
                    validator: (value) => value!.trim().isEmpty ? 'Please enter street name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: city,
                    decoration: InputDecoration(labelText: 'cityName'.tr()),
                    validator: (value) => value!.trim().isEmpty ? 'Please enter city name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: district,
                    decoration: InputDecoration(labelText: 'district'.tr()),
                    validator: (value) => value!.trim().isEmpty ? 'Please enter district' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: zip,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'zipCode'.tr()),
                    validator: (value) => value!.trim().isEmpty ? 'Please enter zip code' : null,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.only(bottom: 8, right: 8, left: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: Text('save'.tr()),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newAddr = CompanyAddress(
                  flatNo: flat.text.trim(),
                  streetName: street.text.trim(),
                  cityName: city.text.trim(),
                  district: district.text.trim(),
                  zipCode: zip.text.trim(),
                );
                _saveCompanyAddress(slot, newAddr);
                Navigator.pop(ctx);
              }
            },
          ),
        ],
      ),
    );
  }


  Widget _buildAddressCard({
    required String label,
    required String addressPreview,
    required IconData icon,
    required VoidCallback onEdit,
    VoidCallback? onDelete,
  }) {
    return Card(
      elevation: 3,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.blueAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      //fontWeight: FontWeight.w600,
                      //color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addressPreview,
                    style: const TextStyle(
                      fontSize: 14,
                      // color: Colors.black54,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'editAddress'.tr(),
                  onPressed: onEdit,
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: 'deleteAddress'.tr(),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final companySlots = [_companyAddress1, _companyAddress2, _companyAddress3];
    final filledCount = companySlots.where((addr) => addr != null).length;
    final canAddMore = filledCount < 3;

    List<Widget> companyWidgets = [];
    for (int i = 0; i < 3; i++) {
      if (companySlots[i] != null) {
        companyWidgets.add(_buildAddressCard(
          label: '${"company Address".tr()} ${i + 1}',
          addressPreview:
          '${companySlots[i]!.flatNo}, ${companySlots[i]!.streetName}, ${companySlots[i]!.cityName}, ${companySlots[i]!.district} - ${companySlots[i]!.zipCode}',
          icon: Icons.business,
          onEdit: () => _showCompanyDialog(i + 1, companySlots[i]),
          onDelete: () => _deleteCompanyAddress(i+1),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('address Book'.tr()),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Billing Address Section
                    Text(
                      "billing Address".tr(),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),

                    _loadingBilling
                        ? const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator()))
                        : _billingAddress != null
                        ? _buildAddressCard(
                      label: "home".tr(),
                      addressPreview:
                      '${_billingAddress!.flatNo}, ${_billingAddress!.streetName}, ${_billingAddress!.cityName}, ${_billingAddress!.district} - ${_billingAddress!.zipCode}',
                      icon: Icons.home,
                      onEdit: () => _showBillingDialog(),
                      onDelete: () => _deleteBillingAddress(),
                    )
                        : Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.home),
                        title: Text("no Billing Address Set".tr()),
                        trailing: TextButton(
                          onPressed: () => _showBillingDialog(),
                          child: Text("add".tr()),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Company Address Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "company Addresses".tr(),
                          style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        ElevatedButton.icon(
                          onPressed: canAddMore
                              ? () {
                            int nextSlot = [1, 2, 3][filledCount];
                            _showCompanyDialog(nextSlot);
                          }
                              : null,
                          icon: const Icon(Icons.add),
                          label:  Text("add Address".tr()),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    _loadingCompany
                        ? const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator()))
                        : companyWidgets.isEmpty
                        ? Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "no Company Addresses Added".tr(),
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                        : Column(
                      children: companyWidgets
                          .map((widget) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: widget,
                      ))
                          .toList(),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}