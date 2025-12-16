import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/features/auth/presentation/screens/login_screen.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/addressBook_page.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/app_version_page.dart';
import 'package:provider/provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../../../config/theme.dart';
import '../../../../services/user_data_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../../../admin/support_ticket_submission_page.dart';
import '../../../admin/user_support_tickets_page.dart';
import '../../../disable/unable_account_page.dart';
import 'notificationDetails_page.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/terms_conditions_page.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/privacy_policy_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final supabase = Supabase.instance.client;
  final user = Supabase.instance.client.auth.currentUser;
  final ImagePicker _picker = ImagePicker();
  String? profile_picture;

  String? name;
  String? email;
  String? customUserId;
  String? role;
  String? mobile_number;
  bool mobile_no_verified = false;
  String? gstNumber;
  List<Map<String, dynamic>> bankDetails = [];

  bool _loading = true;
  bool _editingName = false;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
  }

  Future<void> fetchUserProfile() async {
    final res = await supabase
        .from('user_profiles')
        .select()
        .eq('user_id', user!.id)
        .maybeSingle();

    if (res != null) {
      if (res['account_disable'] == true) {
        // 🚫 Immediately block the user
        await supabase.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("account_disabled".tr())));
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
          );
        }
        return;
      }

      setState(() {
        name = res['name'];
        email = res['email'];
        customUserId = res['custom_user_id'];
        role = res['role'];
        profile_picture = res['profile_picture'];
        mobile_number = res['mobile_number'];
        mobile_no_verified = res['mobile_no_verified'] ?? false;
        gstNumber = res['gst_number'];
        // Fetch bank details from JSONB field
        if (res['bank_details'] != null) {
          bankDetails = List<Map<String, dynamic>>.from(res['bank_details']);
        } else {
          bankDetails = [];
        }
        _loading = false;
      });
    }
  }

  // GST Number Management
  Future<void> _showEditGstDialog() async {
    final gstController = TextEditingController(text: gstNumber ?? "");
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('edit_gst_number'.tr()),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: gstController,
                decoration: InputDecoration(
                  labelText: 'gst_number_label'.tr(),
                  hintText: 'gst_number_hint'.tr(),
                  prefixIcon: const Icon(Icons.receipt),
                  border: const OutlineInputBorder(),
                  helperText: 'gst_number_format_helper'.tr(),
                ),
                maxLength: 15,
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value?.trim().isEmpty == true) {
                    return 'gst_number_required'.tr();
                  }
                  if (value!.trim().length != 15) {
                    return 'gst_number_length'.tr();
                  }
                  if (!_validateGSTNumber(value.trim())) {
                    return 'gst_number_invalid'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'gst_number_format_title'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'gst_number_format_details'.tr(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('save'.tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final newGst = gstController.text.trim().toUpperCase();
      if (newGst.isEmpty) return;

      if (!_validateGSTNumber(newGst)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('gst_number_invalid'.tr())));
        return;
      }

      try {
        await supabase
            .from('user_profiles')
            .update({'gst_number': newGst})
            .eq('user_id', user!.id);

        setState(() {
          gstNumber = newGst;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('gst_number_updated'.tr())));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('gst_number_update_error'.tr(args: [e.toString()])),
          ),
        );
      }
    }
  }

  bool _validateGSTNumber(String gst) {
    if (gst.length != 15) return false;

    // More comprehensive GST validation
    final gstRegex = RegExp(
      r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
    );

    if (!gstRegex.hasMatch(gst)) return false;

    // Validate state code (01-37)
    final stateCode = int.tryParse(gst.substring(0, 2));
    if (stateCode == null || stateCode < 1 || stateCode > 37) return false;

    // Validate that it's not all zeros or all same characters
    if (gst == '000000000000000' ||
        gst.split('').every((char) => char == gst[0]))
      return false;

    // Validate PAN format within GST (positions 2-11)
    final panPart = gst.substring(2, 12);
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
    if (!panRegex.hasMatch(panPart)) return false;

    return true;
  }

  // Bank Details Management
  Future<void> _showBankDetailsDialog([
    Map<String, dynamic>? existingBank,
  ]) async {
    final isEditing = existingBank != null;
    final formKey = GlobalKey<FormState>();

    final holderNameController = TextEditingController(
      text: existingBank?['account_holder_name'] ?? '',
    );
    final accountNumberController = TextEditingController(
      text: existingBank?['account_number'] ?? '',
    );
    final bankNameController = TextEditingController(
      text: existingBank?['bank_name'] ?? '',
    );
    final ifscController = TextEditingController(
      text: existingBank?['ifsc_code'] ?? '',
    );
    final branchController = TextEditingController(
      text: existingBank?['branch'] ?? '',
    );
    bool isPrimary = existingBank?['is_primary'] ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            isEditing ? 'edit_bank_details'.tr() : 'add_bank_details'.tr(),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: holderNameController,
                      decoration: InputDecoration(
                        labelText: 'account_holder_name'.tr(),
                        prefixIcon: const Icon(Icons.person),
                        hintText: 'account_holder_name_hint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value?.trim().isEmpty == true) {
                          return 'account_holder_name_required'.tr();
                        }
                        if (value!.trim().length < 2) {
                          return 'name_min_char'.tr();
                        }
                        if (!RegExp(r'^[a-zA-Z\s.]+$').hasMatch(value.trim())) {
                          return 'name_invalid_chars'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: accountNumberController,
                      decoration: InputDecoration(
                        labelText: 'account_number'.tr(),
                        prefixIcon: const Icon(Icons.account_balance),
                        hintText: 'account_number_hint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 18,
                      validator: (value) {
                        if (value?.trim().isEmpty == true) {
                          return 'account_number_required'.tr();
                        }
                        if (!RegExp(r'^[0-9]+$').hasMatch(value!.trim())) {
                          return 'account_number_digits_only'.tr();
                        }
                        if (value.trim().length < 9 ||
                            value.trim().length > 18) {
                          return 'account_number_length'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: bankNameController,
                      decoration: InputDecoration(
                        labelText: 'bank_name'.tr(),
                        prefixIcon: const Icon(Icons.account_balance_wallet),
                        hintText: 'bank_name_hint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value?.trim().isEmpty == true) {
                          return 'bank_name_required'.tr();
                        }
                        if (value!.trim().length < 3) {
                          return 'bank_name_min_char'.tr();
                        }
                        if (!RegExp(
                          r'^[a-zA-Z\s&.-]+$',
                        ).hasMatch(value.trim())) {
                          return 'bank_name_invalid_chars'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: ifscController,
                      decoration: InputDecoration(
                        labelText: 'ifsc_code'.tr(),
                        prefixIcon: const Icon(Icons.code),
                        hintText: 'ifsc_code_hint'.tr(),
                        border: const OutlineInputBorder(),
                        helperText: 'ifsc_code_format'.tr(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 11,
                      validator: (value) {
                        if (value?.trim().isEmpty == true) {
                          return 'ifsc_code_required'.tr();
                        }
                        if (value!.trim().length != 11) {
                          return 'ifsc_code_length'.tr();
                        }
                        if (!_validateIFSC(value.trim())) {
                          return 'ifsc_code_invalid'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: branchController,
                      decoration: InputDecoration(
                        labelText: 'branch_name'.tr(),
                        prefixIcon: const Icon(Icons.place),
                        hintText: 'branch_name_hint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value?.trim().isEmpty == true) {
                          return 'branch_name_required'.tr();
                        }
                        if (value!.trim().length < 3) {
                          return 'branch_name_min_char'.tr();
                        }
                        if (!RegExp(
                          r'^[a-zA-Z0-9\s,.-]+$',
                        ).hasMatch(value.trim())) {
                          return 'branch_name_invalid_chars'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CheckboxListTile(
                        title: Text('set_primary_account'.tr()),
                        subtitle: Text('default_account_info'.tr()),
                        value: isPrimary,
                        onChanged: (value) {
                          setDialogState(() {
                            isPrimary = value ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.blue,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'important_notes'.tr(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'bank_details_notes'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(isEditing ? 'update'.tr() : 'add'.tr()),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        final bankData = {
          'account_holder_name': holderNameController.text.trim(),
          'account_number': accountNumberController.text.trim(),
          'bank_name': bankNameController.text.trim(),
          'ifsc_code': ifscController.text.trim().toUpperCase(),
          'branch': branchController.text.trim(),
          'is_primary': isPrimary,
        };

        if (isEditing) {
          await _updateBankDetails(existingBank['bank_id'], bankData);
        } else {
          await _addBankDetails(bankData);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_msg'.tr(args: [e.toString()]))),
        );
      }
    }
  }

  bool _validateIFSC(String ifsc) {
    if (ifsc.length != 11) return false;

    // IFSC format: 4 letters + 0 + 6 alphanumeric
    final ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
    if (!ifscRegex.hasMatch(ifsc)) return false;

    // Check if it's not all same characters
    if (ifsc.split('').every((char) => char == ifsc[0])) return false;

    // Validate bank code (first 4 characters) - should not be common invalid codes
    final bankCode = ifsc.substring(0, 4);
    final invalidBankCodes = ['XXXX', 'TEST', 'DEMO', 'NULL'];
    if (invalidBankCodes.contains(bankCode)) return false;

    // The 5th character must be 0
    if (ifsc[4] != '0') return false;

    return true;
  }

  Future<void> _addBankDetails(Map<String, dynamic> bankData) async {
    try {
      // If this is primary, set all others to non-primary
      if (bankData['is_primary']) {
        for (var bank in bankDetails) {
          bank['is_primary'] = false;
        }
      }

      // Generate unique bank ID
      final bankId = 'bank_${bankDetails.length + 1}';
      final newBank = {
        'bank_id': bankId,
        ...bankData,
        'created_at': DateTime.now().toIso8601String(),
      };

      final updatedBankDetails = [...bankDetails, newBank];

      await supabase
          .from('user_profiles')
          .update({'bank_details': updatedBankDetails})
          .eq('user_id', user!.id);

      setState(() {
        bankDetails = updatedBankDetails;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank details added successfully')),
      );
    } catch (e) {
      throw Exception('Failed to add bank details: $e');
    }
  }

  Future<void> _updateBankDetails(
      String bankId,
      Map<String, dynamic> bankData,
      ) async {
    try {
      // If this is primary, set all others to non-primary
      if (bankData['is_primary']) {
        for (var bank in bankDetails) {
          if (bank['bank_id'] != bankId) {
            bank['is_primary'] = false;
          }
        }
      }

      // Update the specific bank
      final updatedBankDetails = bankDetails.map((bank) {
        if (bank['bank_id'] == bankId) {
          return {
            ...bank,
            ...bankData,
            'updated_at': DateTime.now().toIso8601String(),
          };
        }
        return bank;
      }).toList();

      await supabase
          .from('user_profiles')
          .update({'bank_details': updatedBankDetails})
          .eq('user_id', user!.id);

      setState(() {
        bankDetails = updatedBankDetails;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank details updated successfully')),
      );
    } catch (e) {
      throw Exception('Failed to update bank details: $e');
    }
  }

  Future<void> _deleteBankDetails(String bankId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bank Details'),
        content: const Text(
          'Are you sure you want to delete this bank account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final updatedBankDetails = bankDetails
            .where((bank) => bank['bank_id'] != bankId)
            .toList();

        await supabase
            .from('user_profiles')
            .update({'bank_details': updatedBankDetails})
            .eq('user_id', user!.id);

        setState(() {
          bankDetails = updatedBankDetails;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bank details deleted successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting bank details: $e')),
        );
      }
    }
  }

  void _showBankDetailsList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'bank_details'.tr(),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      Navigator.pop(context);
                      _showBankDetailsDialog();
                    },
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: bankDetails.isEmpty
                    ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_balance,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text('No bank details added yet'),
                    ],
                  ),
                )
                    : ListView.builder(
                  controller: scrollController,
                  itemCount: bankDetails.length,
                  itemBuilder: (context, index) {
                    final bank = bankDetails[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: bank['is_primary']
                              ? Colors.green
                              : Colors.grey,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(bank['bank_name'] ?? 'Unknown Bank'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'A/c: ***${bank['account_number']?.toString().substring(bank['account_number'].toString().length - 4)}',
                            ),
                            Text('IFSC: ${bank['ifsc_code']}'),
                            if (bank['is_primary'])
                              const Text(
                                'Primary Account',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            Navigator.pop(context);
                            if (value == 'edit') {
                              _showBankDetailsDialog(bank);
                            } else if (value == 'delete') {
                              _deleteBankDetails(bank['bank_id']);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Account Disable
  Future<void> _navigateToDisableAccount() async {
    final bool? confirmDisable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('disable_account_title'.tr()),
        content: Text(
          'disable_account_message'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('disable_account_button'.tr()),
          ),
        ],
      ),
    );



    if (confirmDisable != true) return;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final result = await supabase.rpc(
        'set_account_disable',
        params: {
          'target_custom_id': customUserId,
          'disable': true,
          'performed_by_user_id': currentUser.id,
        },
      );

      if (!mounted) return;

      if (result['ok'] == true) {
        // Successfully disabled account - navigate to unable account page
        final userProfile = {
          'name': name,
          'email': email,
          'custom_user_id': customUserId,
          'role': role,
          'mobile_number': mobile_number,
          'profile_picture': profile_picture,
        };

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => UnableAccountPage(userProfile: userProfile),
          ),
        );
      } else {
        String errorMessage = 'Failed to disable account';

        switch (result['error']) {
          case 'driver_has_active_shipment':
            errorMessage =
            'Cannot disable account while you have active shipments. Please complete or cancel your current shipments first.';
            break;
          case 'not_authorized':
            errorMessage = 'Not authorized to perform this action';
            break;
          default:
            errorMessage = result['error'] ?? errorMessage;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



  Future<void> _signOut(BuildContext context) async {
    final bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("confirm_logout".tr()),
        content: Text("logout_message".tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("cancel".tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("logout".tr()),
          ),
        ],
      ),
    );

    if (confirmLogout != true) return;
    try {
      OneSignal.logout();
      print('✅ OneSignal user logged out.');
    } catch (e) {
      print('❌ Error logging out from OneSignal: $e');
    }
    await supabase.auth.signOut();
    if (context.mounted) {
      UserDataService.clearCache();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    }
  }

  void _showThemeDialog(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
    ThemeMode currentMode =
    themeNotifier.isDarkMode ? ThemeMode.dark : ThemeMode.light;

    showDialog(
      context: context,
      builder: (context) {
        ThemeMode selectedMode = currentMode;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("chooseTheme".tr()),
              content: RadioGroup(
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedMode = value);
                  }
                },
                groupValue: selectedMode,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('light_mode'.tr()),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('dark_mode'.tr()),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("cancel".tr()),
                ),
                ElevatedButton(
                  onPressed: () {
                    themeNotifier.setThemeMode(selectedMode);
                    Navigator.pop(context);
                  },
                  child: Text("apply".tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }




  Future<void> _reportBug() async {
    final TextEditingController bugController = TextEditingController();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("reportBug".tr()),
        content: TextField(
          controller: bugController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: "bugHint".tr(),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("cancel".tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("save".tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final String bugText = bugController.text.trim();

      if (bugText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please describe the bug before reporting'),
          ),
        );
        return;
      }

      // Gmail deep link
      final Uri gmailUri = Uri.parse(
        "googlegmail://co?to=trucksingh.com@gmail.com&subject=Bug%20Report&body=${Uri.encodeComponent(bugText)}",
      );

      // Fallback mailto link
      final Uri mailtoUri = Uri(
        scheme: 'mailto',
        path: 'trucksingh.com@gmail.com',
        queryParameters: {'subject': 'Bug Report', 'body': bugText},
      );

      try {
        // Try Gmail app first
        if (await canLaunchUrl(gmailUri)) {
          await launchUrl(gmailUri, mode: LaunchMode.externalApplication);
        } else {
          // Fall back to default email app
          await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("emailError").tr()));
      }
    }
  }

  Future<void> _changePassword() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isOldObscured = true;
    bool isNewObscured = true;
    bool isConfirmObscured = true;

    String getPasswordStrength(String password) {
      if (password.isEmpty) return "";
      if (password.length < 6) return "Weak";
      bool hasUpper = password.contains(RegExp(r'[A-Z]'));
      bool hasLower = password.contains(RegExp(r'[a-z]'));
      bool hasDigit = password.contains(RegExp(r'\d'));
      bool hasSpecial = password.contains(RegExp(r'[@$!%*?&]'));

      int strengthScore = [
        hasUpper,
        hasLower,
        hasDigit,
        hasSpecial,
      ].where((element) => element).length;

      if (strengthScore <= 2) return "Weak";
      if (strengthScore == 3) return "Medium";
      return "Strong";
    }

    Color getStrengthColor(String strength) {
      switch (strength) {
        case "Weak":
          return Colors.red;
        case "Medium":
          return Colors.orange;
        case "Strong":
          return Colors.green;
        default:
          return Colors.grey;
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text("changePassword".tr()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Old Password
                TextField(
                  controller: oldPasswordController,
                  obscureText: isOldObscured,
                  decoration: InputDecoration(
                    labelText: "oldPassword".tr(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isOldObscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => isOldObscured = !isOldObscured),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // New Password + Strength Meter + Dynamic Hint
                TextField(
                  controller: newPasswordController,
                  obscureText: isNewObscured,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: "newPassword".tr(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isNewObscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => isNewObscured = !isNewObscured),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (_) {
                    final password = newPasswordController.text;
                    final strength = getPasswordStrength(password);


                    return strength.isEmpty
                        ? const SizedBox.shrink()
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: strength == "weak".tr()
                              ? 0.33
                              : strength == "medium".tr()
                              ? 0.66
                              : 1.0,
                          backgroundColor: Colors.grey[300],
                          color: getStrengthColor(strength),
                          minHeight: 6,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Strength: $strength",
                          style: TextStyle(
                            color: getStrengthColor(strength),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 10),

                // Confirm Password
                TextField(
                  controller: confirmPasswordController,
                  obscureText: isConfirmObscured,
                  decoration: InputDecoration(
                    labelText: "confirmNewPassword".tr(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isConfirmObscured
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(
                            () => isConfirmObscured = !isConfirmObscured,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("cancel".tr()),
            ),
            ElevatedButton(
              onPressed: () async {
                final oldPassword = oldPasswordController.text.trim();
                final newPassword = newPasswordController.text.trim();
                final confirmPassword = confirmPasswordController.text.trim();

                if (oldPassword.isEmpty ||
                    newPassword.isEmpty ||
                    confirmPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("allFieldsRequired".tr())),
                  );
                  return;
                }

                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("passwordMismatch".tr())),
                  );
                  return;
                }

                try {
                  final supabaseClient = Supabase.instance.client;
                  final email = supabaseClient.auth.currentUser?.email;

                  if (email == null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("noUser".tr())));
                    return;
                  }

                  // Re-authenticate with old password
                  final signInResponse = await supabaseClient.auth
                      .signInWithPassword(email: email, password: oldPassword);

                  if (signInResponse.user == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("wrongOldPassword".tr())),
                    );
                    return;
                  }

                  // Update password
                  final updateResponse = await supabaseClient.auth.updateUser(
                    UserAttributes(password: newPassword),
                  );

                  if (updateResponse.user != null) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("passwordUpdated".tr())),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("passwordUpdateFailed".tr())),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              },
              child: Text("update".tr()),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> deleteAccount() async {
    final supabase = Supabase.instance.client;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("block_account_title".tr()),
        content: Text("block_account_message".tr()),
        actions: [
          TextButton(
            child: Text("cancel".tr()),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("block_account_button".tr()),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );



    if (confirm != true) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Not logged in.")));
      return;
    }

    try {
      await supabase
          .from("user_profiles")
          .update({"account_disable": true})
          .eq('user_id', user.id);
      await supabase.auth.signOut();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("accountDisabledLogout".tr())));
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("error: $e".tr())));
    }
  }

  Future<void> checkIfDisabled() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final profile = await supabase
        .from("user_profile")
        .select("account_disable")
        .eq("user_id".tr(), user.id)
        .maybeSingle();

    if (profile != null && profile["account_disable"] == true) {
      await supabase.auth.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("accountDisabledSupport".tr())));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
        );
      }
    }
  }

  Future<void> _showEditProfileDialog() async {
    String? tempProfilePic = profile_picture;
    final TextEditingController nameController = TextEditingController(
      text: name ?? "",
    );
    final TextEditingController mobileController = TextEditingController(
      text: mobile_number ?? "",
    );
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('editProfile'.tr()),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ Profile picture with edit icon
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: tempProfilePic != null
                            ? (tempProfilePic!.startsWith("http")
                            ? NetworkImage(tempProfilePic!)
                        as ImageProvider
                            : FileImage(File(tempProfilePic!))
                        as ImageProvider)
                            : null,
                        child: tempProfilePic == null
                            ? const Icon(Icons.person, size: 50)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 4,
                        child: InkWell(
                          onTap: () async {
                            final option = await showModalBottomSheet<String>(
                              context: context,
                              builder: (BuildContext bc) {
                                return SafeArea(
                                  child: Wrap(
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.camera_alt),
                                        title: Text("takePhoto".tr()),
                                        onTap: () =>
                                            Navigator.pop(bc, "camera".tr()),
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.photo_library,
                                        ),
                                        title: Text("chooseFromGallery".tr()),
                                        onTap: () =>
                                            Navigator.pop(bc, "gallery".tr()),
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.attach_file),
                                        title: Text("chooseFile".tr()),
                                        onTap: () =>
                                            Navigator.pop(bc, "file".tr()),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );

                            if (option != null) {
                              XFile? pickedFile;
                              if (option == "camera") {
                                pickedFile = await _picker.pickImage(
                                  source: ImageSource.camera,
                                );
                              } else if (option == "gallery") {
                                pickedFile = await _picker.pickImage(
                                  source: ImageSource.gallery,
                                );
                              } else if (option == "file") {
                                FilePickerResult? result = await FilePicker
                                    .platform
                                    .pickFiles(type: FileType.image);
                                if (result != null &&
                                    result.files.single.path != null) {
                                  pickedFile = XFile(result.files.single.path!);
                                }
                              }

                              if (pickedFile != null) {
                                setStateDialog(
                                      () => tempProfilePic = pickedFile!.path,
                                );
                              }
                            }
                          },
                          child: const CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.blue,
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ✅ Editable Name Field
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: "fullName".tr(),
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'nameEmptyError';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ✅ Editable Mobile Number Field with validation
                  TextFormField(
                    controller: mobileController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: "mobileNumber".tr(),
                      prefixIcon: const Icon(Icons.phone),
                      suffixIcon: mobile_no_verified
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.warning, color: Colors.red),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final pattern = RegExp(r'^[0-9]{10}$'.tr());
                      if (value == null || !pattern.hasMatch(value.trim())) {
                        return 'mobileInvalidError'.tr();
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: Text("close".tr()),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              child: Text("update".tr()),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final updatedName = nameController.text.trim();
                final updatedMobile = mobileController.text.trim();

                // ✅ Update name if changed
                if (updatedName != name) {
                  await supabase
                      .from("user_profiles")
                      .update({"name": updatedName})
                      .eq("user_id", user!.id);
                  setStateDialog(() => name = updatedName);
                  setState(() => name = updatedName);
                }

                // ✅ Update mobile number if changed
                if (updatedMobile != mobile_number) {
                  await supabase
                      .from("user_profiles")
                      .update({"mobile_number": updatedMobile})
                      .eq("user_id", user!.id);
                  setStateDialog(() {
                    mobile_number = updatedMobile;
                    mobile_no_verified = false;
                  });
                  setState(() {
                    mobile_number = updatedMobile;
                    mobile_no_verified = false;
                  });
                }

                // ✅ Upload profile pic if changed
                if (tempProfilePic != null &&
                    !tempProfilePic!.startsWith("http")) {
                  try {
                    final File file = File(tempProfilePic!);
                    final String fileExt = p.extension(file.path);
                    final String fileName = '${const Uuid().v4()}$fileExt';
                    final String filePath =
                        'profile_picture/${user!.id}/$fileName';

                    await supabase.storage
                        .from('profilepic')
                        .upload(
                      filePath,
                      file,
                      fileOptions: const FileOptions(upsert: true),
                    );

                    final String publicUrl = supabase.storage
                        .from('profilepic')
                        .getPublicUrl(filePath);

                    await supabase
                        .from("user_profiles")
                        .update({"profile_picture": publicUrl})
                        .eq("user_id", user!.id);

                    setStateDialog(() => profile_picture = publicUrl);
                    setState(() => profile_picture = publicUrl);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("imageUploadFailed: $e")),
                    );
                  }
                }

                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("profileUpdated")));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr()), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(12.0),
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: SectionTitle(title: "accountInfo".tr()),
          ),
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: profile_picture != null
                      ? NetworkImage(profile_picture!)
                      : null,
                  child: profile_picture == null
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Icon(
                  Icons.person,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _editingName
                      ? TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: "fullName".tr(),
                    ),
                  )
                      : Text(
                    name ?? "noName".tr(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Icon(
                  Icons.phone,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        mobile_number ?? "noMobileNumber".tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (mobile_no_verified)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 18,
                        )
                      else
                        const Icon(
                          Icons.warning,
                          color: Colors.red,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (role == 'agent' || role == 'truck_owner')
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text

                      (
                      gstNumber ?? "no_gst_number".tr(),
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onPressed: _showEditGstDialog,
                  ),
                ],
              ),
            ),

          SectionTitle(title: "accountManagement".tr()),
          SettingsTile(
            icon: Icons.edit,
            title: "editProfile".tr(),
            onTap: _showEditProfileDialog,
          ),
          SettingsTile(
            icon: Icons.lock,
            title: "changePassword".tr(),
            onTap: _changePassword,
          ),
          // Bank Details - Only visible to agents and truck owners
          if (role == 'agent' || role == 'truck_owner')
            SettingsTile(
              icon: Icons.account_balance,
              title: '${'bank_details'.tr()}(${bankDetails.length})',
              onTap: _showBankDetailsList,
            ),
          SettingsTile(
            icon: Icons.block,
            title: 'disable_account'.tr(),
            onTap: _navigateToDisableAccount,
          ),
          SettingsTile(
            icon: Icons.delete_forever,
            title: "deleteAccount".tr(),
            onTap: deleteAccount,
          ),
          SectionTitle(title: "address".tr()),
          SettingsTile(
            icon: Icons.place,
            title: "addressBook".tr(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddressBookPage()),
              );
            },
          ),

          SectionTitle(title: "languagePreferences".tr()),
          SettingsTile(
            icon: Icons.language,
            title: "changeAppLanguage".tr(),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text("changeAppLanguage".tr()),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.language),
                          title: const Text("English"),
                          onTap: () async {
                            await context.setLocale(const Locale('en'));
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.language),
                          title: const Text("हिंदी"),
                          onTap: () async {
                            await context.setLocale(const Locale('hi'));
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          SettingsTile(
            icon: Icons.brightness_6,
            title: "theme".tr(),
            onTap: () => _showThemeDialog(context),
          ),

          SettingsTile(
            icon: Icons.notifications,
            title: "notificationSettings".tr(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationDetailsPage(),
                ),
              );
            },
          ),

          SectionTitle(title: "supportFeedback".tr()),
          if (role != 'Admin')
            SettingsTile(
              icon: Icons.support_agent,
              title: "requestSupport".tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SupportTicketSubmissionPage(),
                  ),
                );
              },
            ),
          if (role != 'Admin')
            SettingsTile(
              icon: Icons.history,
              title: 'my_support_tickets'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserSupportTicketsPage(),
                  ),
                );
              },
            ),

          SettingsTile(
            icon: Icons.info_outline,
            title: "appVersion".tr(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppVersionPage(),
                ),
              );
            },
          ),

          if (role != 'Admin')
            SettingsTile(
              icon: Icons.bug_report,
              title: "reportBug".tr(),
              onTap: _reportBug,
            ),

          SectionTitle(title: "legalInfo".tr()),
          SettingsTile(
            icon: Icons.article,
            title: "termsConditions".tr(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TermsConditionsPage(),
                ),
              );
            },
          ),
          SettingsTile(
            icon: Icons.privacy_tip,
            title: "privacyPolicy".tr(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PrivacyPolicyPage(),
                ),
              );
            },
          ),

          const SizedBox(height: 40),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: Text("logout".tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () => _signOut(context),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}


class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}