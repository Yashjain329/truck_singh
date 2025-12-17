import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/admin_service.dart';
import '../../config/theme.dart';

class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({super.key});
  @override
  State<AdminUserManagementPage> createState() =>
      _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;

  late TabController _tabController;

  List<Map<String, dynamic>> allUsers = [];
  bool isLoadingUsers = true;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  DateTime? _selectedDate;
  bool _isCreatingAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    try {
      setState(() => isLoadingUsers = true);
      final users = await AdminService.getAllUsers();

      // Deduplicate by custom_user_id
      final Map<String, Map<String, dynamic>> unique = {};
      for (final u in users) {
        final id = u['custom_user_id'];
        if (id != null) unique[id] = Map<String, dynamic>.from(u);
      }

      setState(() {
        allUsers = unique.values.toList();
        isLoadingUsers = false;
      });
    } catch (e) {
      setState(() => isLoadingUsers = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading users: $e')));
      }
    }
  }

  Future<void> _createAdminUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isCreatingAdmin = true);

    try {
      final dateOfBirthValue =
          _selectedDate?.toIso8601String() ?? DateTime(1990, 1, 1).toIso8601String();
      final mobileNumberValue = _mobileController.text.trim();

      final result = await AdminService.createAdminUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        dateOfBirth: dateOfBirthValue,
        mobileNumber: mobileNumberValue,
      );

      if (!mounted) return;

      final success = result['success'] as bool? ?? false;
      if (success) {
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _nameController.clear();
        _mobileController.clear();
        setState(() => _selectedDate = null);

        await _loadAllUsers();

        final requiresReauth = result['requires_reauth'] as bool? ?? false;
        if (requiresReauth) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: Text('⚠️ Admin Created - Reauth Required'),
              content: Text(
                'Admin ${result['admin_id'] as String? ?? 'N/A'} was created successfully, but you were logged out. Please log back in to continue.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: Text('Go to Login'),
                )
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ ${result['message'] as String? ?? 'Admin created successfully!'}\nMethod: ${result['method'] as String? ?? 'unknown'}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error creating admin: ${result['error'] as String? ?? 'Unknown error'}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating admin: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingAdmin = false);
    }
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 6570)),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    Widget? prefix,
    TextInputType? keyboardType,
    bool obscure = false,
    String? Function(String?)? validator,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: prefix,
        hintText: hint,
      ),
      keyboardType: keyboardType,
      obscureText: obscure,
      validator: validator,
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final isDisabled = user['account_disable'] ?? false;
    final role = (user['role'] ?? '').toString();
    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(role),
          child: Text(
            role.isNotEmpty ? role.substring(0, 1).toUpperCase() : 'U',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          user['name'] ?? 'No Name',
          style: TextStyle(fontWeight: FontWeight.bold, color: isDisabled ? Colors.grey : null),
        ),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ID: ${user['custom_user_id']}'),
          Text('Email: ${user['email'] ?? 'N/A'}'),
          Text('Role: ${_formatRole(user['role'])}'),
          if (isDisabled) Text('account_disabled'.tr(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (user['role'] == 'admin')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: Text('admin'.tr(), style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(isDisabled ? Icons.toggle_off : Icons.toggle_on, color: isDisabled ? Colors.grey : Colors.green),
            onPressed: () => _toggleUserStatus(user),
          ),
        ]),
        isThreeLine: true,
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return const Color(0xFF6A1B9A);
      case 'agent':
        return AppColors.tealBlue;
      case 'truckowner':
        return Colors.green;
      case 'driver':
        return Colors.orange;
      case 'shipper':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatRole(String? role) {
    if (role == null) return 'unknown'.tr();
    final r = role.toString();
    if (r.isEmpty) return 'unknown'.tr();
    return r.substring(0, 1).toUpperCase() + r.substring(1).toLowerCase();
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final isCurrentlyDisabled = user['account_disable'] ?? false;
    final action = isCurrentlyDisabled ? 'enable'.tr() : 'disable'.tr();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action ${user['name']}'),
        content: Text('confirm_user_action'.tr(namedArgs: {'action': action, 'name': user['name']})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action.toUpperCase())),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _loadAllUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('user_account_success'.tr(namedArgs: {'action': action}))));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildUserListTab() {
    if (isLoadingUsers) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadAllUsers,
      child: Column(children: [
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.info, color: Colors.blue[700]),
            const SizedBox(width: 8),
            Expanded(child: Text('${'My Created Admins:'.tr()} ${allUsers.length}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700]))),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllUsers),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: allUsers.length,
            itemBuilder: (context, index) => _buildUserTile(allUsers[index]),
          ),
        ),
      ]),
    );
  }

  Widget _buildCreateAdminTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.info, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Expanded(child: Text('create_admin'.tr(), style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.bold, fontSize: 16))),
                ]),
                const SizedBox(height: 8),
                Text('create_admin_account_info'.tr(), style: const TextStyle(fontSize: 14)),
              ]),
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _nameController,
              label: 'full_name'.tr(),
              prefix: const Icon(Icons.person),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'enter_full_name'.tr();
                if (v.trim().length < 2) return 'name_min_chars'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: InputDecoration(labelText: 'date_of_birth'.tr(), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.calendar_today)),
                child: Text(_selectedDate != null ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}' : 'select_dob'.tr(), style: TextStyle(color: _selectedDate != null ? Colors.black : Colors.grey)),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _mobileController,
              label: 'mobile_number'.tr(),
              prefix: const Icon(Icons.phone),
              keyboardType: TextInputType.phone,
              hint: 'mobile_hint'.tr(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'enter_mobile'.tr();
                if (v.trim().length != 10) return 'mobile_invalid'.tr();
                if (!RegExp(r'^[0-9]+$').hasMatch(v.trim())) return 'mobile_digits_only'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _emailController,
              label: 'admin_email'.tr(),
              prefix: const Icon(Icons.email),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.isEmpty) return 'enter_email'.tr();
                if (!v.contains('@')) return 'enter_valid_email'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'password'.tr(),
              prefix: const Icon(Icons.lock),
              obscure: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'enter_password'.tr();
                if (v.length < 6) return 'password_min_chars'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _confirmPasswordController,
              label: 'confirm_password'.tr(),
              prefix: const Icon(Icons.lock_outline),
              obscure: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'confirm_password_enter'.tr();
                if (v != _passwordController.text) return 'passwords_not_match'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreatingAdmin ? null : _createAdminUser,
                icon: _isCreatingAdmin
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.admin_panel_settings),
                label: Text(_isCreatingAdmin ? 'creating_admin'.tr() : 'create_admin_user'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('user_management'.tr()),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(icon: const Icon(Icons.admin_panel_settings), text: 'My Admins'.tr()),
            Tab(icon: const Icon(Icons.person_add), text: 'create_admin'.tr()),
          ],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [_buildUserListTab(), _buildCreateAdminTab()]),
    );
  }
}