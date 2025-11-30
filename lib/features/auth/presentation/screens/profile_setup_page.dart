import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/features/auth/presentation/screens/role_selection_page.dart';
import 'package:logistics_toolkit/features/auth/utils/user_role.dart';
import 'package:logistics_toolkit/features/auth/services/supabase_service.dart';
import 'dashboard_router.dart';

class ProfileSetupPage extends StatefulWidget {
  final UserRole selectedRole;

  const ProfileSetupPage({super.key, required this.selectedRole});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  DateTime? _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Prefill email from Supabase auth
    final user = SupabaseService.getCurrentUser();
    if (user?.email != null) {
      _emailController.text = user!.email!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => RoleSelectionPage()),
            );
          },
        ),
        // --- END FIX ---
        title: Text('complete_your_profile'.tr()),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRoleInfo(),
                    const SizedBox(height: 24),
                    _buildNameField(),
                    const SizedBox(height: 16),
                    _buildDateOfBirthField(),
                    const SizedBox(height: 16),
                    _buildMobileField(),
                    const SizedBox(height: 16),
                    _buildEmailField(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRoleInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(26), // 10% opacity
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(widget.selectedRole.icon, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Text(
            "selected_role".tr(
              namedArgs: {"role": widget.selectedRole.displayName},
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'full_name'.tr(),
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'please_enter_full_name'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildDateOfBirthField() {
    return InkWell(
      onTap: _selectDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'date_of_birth'.tr(),
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(
          _selectedDate != null
              ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
              : 'select_dob'.tr(),
          /*style: TextStyle(
            //color: _selectedDate != null ? Colors.black : Colors.grey,
          ),*/
        ),
      ),
    );
  }

  Widget _buildMobileField() {
    return TextFormField(
      controller: _mobileController,
      decoration: InputDecoration(
        labelText: 'mobile_number'.tr(),
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.phone),
        prefixText: '+91 ',
      ),
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'please_enter_mobile'.tr();
        }
        if (value.length != 10) {
          return 'please_enter_valid_mobile'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      enabled: true, //changed from false to true
      decoration: InputDecoration(
        labelText: 'email'.tr(),
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.email),
        filled: true,
        //fillColor: Color(0xFFEEEEEE),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        // 1. Checking if it's empty
        if (value == null || value.trim().isEmpty) {
          return 'please_enter_email'.tr();
        }

        // 2. Checking if it's a valid format
        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
        if (!emailRegex.hasMatch(value)) {
          return 'please_enter_valid_email'.tr();
        }

        // 3. If it's all good, return null (no error)
        return null;
      },
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _submitProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          'complete_setup'.tr(),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDate == null) {
      _showErrorDialog('please_select_dob'.tr());
      return;
    }

    final user = SupabaseService.getCurrentUser();
    if (user == null) {
      _showErrorDialog('please_sign_in_continue'.tr());
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ Generate the custom role-based ID
      final customUserId = await generateUniqueUserId();
      final success = await SupabaseService.saveUserProfile(
        userId: user.id,
        customUserId: customUserId,
        role: widget.selectedRole,
        name: _nameController.text.trim(),
        dateOfBirth: _selectedDate!.toIso8601String(),
        mobileNumber: _mobileController.text.trim(),
        email: user.email,
      );

      if (success) {
        // Profile completed successfully!
        print('✅ Profile setup completed successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile setup completed!'),
              backgroundColor: Colors.green,
            ),
          );
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            print(
              '🚀 Navigating to dashboard for role: ${widget.selectedRole}',
            );
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) =>
                    DashboardRouter(role: widget.selectedRole),
              ),
              (route) => false,
            );
          }
        }
      } else {
        _showErrorDialog('failed_save_profile'.tr());
      }
    } catch (e) {
      _showErrorDialog('error_occurred'.tr());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('error'.tr()),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ok'.tr()),
          ),
        ],
      ),
    );
  }

  Future<String> generateUniqueUserId() async {
    final prefix = widget.selectedRole.prefix;
    final random = Random();

    for (int i = 0; i < 10; i++) {
      final number = random.nextInt(10000); // 0 to 9999
      final candidateId = '$prefix${number.toString().padLeft(4, '0')}';

      final existing = await SupabaseService.client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('custom_user_id', candidateId)
          .maybeSingle();

      if (existing == null) {
        return candidateId; // Unique!
      }
    }

    throw Exception('failed_generate_id'.tr());
  }
}
