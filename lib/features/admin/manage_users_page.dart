import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/features/notifications/notification_service.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _roleFilter = 'All';

  late Future<List<Map<String, dynamic>>> _usersFuture;
  late TabController _tabController;

  final List<String> _roles = [
    'All',
    'shipper',
    'truckowner',
    'driver',
    'agent',
  ];

  @override
  void initState() {
    super.initState();
    _usersFuture = _fetchUsers();
    _tabController = TabController(length: 1, vsync: this);
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    final roleForQuery = _roleFilter == 'driver' ? 'All' : _roleFilter;

    final response = await Supabase.instance.client.rpc(
      'get_all_users_for_admin',
      params: {'search_query': _searchQuery, 'role_filter': roleForQuery},
    );

    final List<Map<String, dynamic>> allUsers = response == null
        ? []
        : List<Map<String, dynamic>>.from(response);

    return allUsers.where((user) {
      final role = (user['role'] ?? '').toLowerCase();
      if (role == 'admin') return false;
      return _roleFilter == 'All' || role == _roleFilter.toLowerCase();
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _usersFuture = _fetchUsers());
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final isDisabled = user['account_disable'] ?? false;
    final action = isDisabled ? 'enable'.tr() : 'disable'.tr();
    bool isBusy = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('$action ${'user_account'.tr()}'),
              content: Text(
                'confirm_user_action'.tr(
                  namedArgs: {
                    'action': action,
                    'name': user['name'] ?? 'Unknown',
                  },
                ),
              ),
              actions: [
                if (!isBusy)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('cancel'.tr()),
                  ),
                if (!isBusy)
                  ElevatedButton(
                    onPressed: () async {
                      setDialogState(() => isBusy = true);

                      try {
                        final admin = Supabase.instance.client.auth.currentUser;
                        final adminEmail = admin?.email ?? 'unknown_admin';

                        await toggleAccountStatusRpc(
                          customUserId: user['custom_user_id'],
                          disabled: !isDisabled,
                          changedBy: adminEmail,
                          changedByRole: 'admin',
                        );

                        /// ----- Push Notification Logic -----
                        final targetUser = user['custom_user_id'] ?? '';
                        final adminId =
                            await NotificationService.getCurrentCustomUserId();

                        if (!isDisabled) {
                          NotificationService.sendPushNotificationToUser(
                            recipientId: targetUser,
                            title: 'Account Disabled'.tr(),
                            message:
                                'Your account has been disabled by an administrator.'
                                    .tr(),
                          );
                        } else {
                          NotificationService.sendPushNotificationToUser(
                            recipientId: targetUser,
                            title: 'Account Enabled'.tr(),
                            message: 'Your account has been re-enabled.'.tr(),
                          );
                        }

                        if (adminId != null) {
                          NotificationService.sendPushNotificationToUser(
                            recipientId: adminId,
                            title: 'Action Saved'.tr(),
                            message:
                                'You updated the status for ${user['name']}.',
                          );
                        }

                        Navigator.pop(ctx, true);
                      } catch (e) {
                        Navigator.pop(ctx, false);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Text(action.toUpperCase()),
                  ),
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'user_account_success'.tr(namedArgs: {'action': action}),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showEditDialog(Map<String, dynamic> user) {
    final nameCtrl = TextEditingController(text: user['name'] ?? '');
    final emailCtrl = TextEditingController(text: user['email'] ?? '');
    String selectedRole = user['role'] ?? '';

    final roles = _roles.where((r) => r != 'All').toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('edit_user_profile'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(labelText: 'name'.tr()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtrl,
                    decoration: InputDecoration(labelText: 'email'.tr()),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: InputDecoration(labelText: 'role'.tr()),
                    items: roles
                        .map(
                          (role) =>
                              DropdownMenuItem(value: role, child: Text(role)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value ?? ''),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr()),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await Supabase.instance.client.rpc(
                      'admin_update_user',
                      params: {
                        'target_user_id': user['user_id'],
                        'new_name': nameCtrl.text,
                        'new_email': emailCtrl.text,
                        'new_role': selectedRole,
                      },
                    );
                    Navigator.pop(context);
                    _refresh();
                  },
                  child: Text('save'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('manage_users'.tr()),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [Tab(icon: const Icon(Icons.people), text: 'all_users'.tr())],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildUserListTab()],
      ),
    );
  }

  Widget _buildUserListTab() {
    return Column(
      children: [
        _buildSummaryHeader(),
        _buildSearchBar(),
        _buildFilterChips(),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _usersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              final users = (snapshot.data ?? [])
                  .where((u) => (u['role'] ?? '').toLowerCase() != 'admin')
                  .toList();

              if (users.isEmpty) {
                return Center(child: Text("no_users_found".tr()));
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (_, i) {
                    final user = users[i];
                    final isDisabled = user['account_disable'] ?? false;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getRoleColor(user['role']),
                          child: Text(
                            user['role']?[0].toUpperCase() ?? '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Text(
                          user['name'] ?? 'No Name',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDisabled ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          '${user['email']} · Role: ${user['role']}',
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isDisabled ? Icons.toggle_off : Icons.toggle_on,
                            color: isDisabled ? Colors.grey : Colors.green,
                          ),
                          onPressed: () => _toggleUserStatus(user),
                        ),
                        onTap: () => _showEditDialog(user),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          const Icon(Icons.info, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: FutureBuilder(
              future: _usersFuture,
              builder: (context, snapshot) {
                final count = snapshot.hasData ? snapshot.data!.length : 0;
                return Text(
                  'total_users'.tr(namedArgs: {'count': '$count'}),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: 'search_user'.tr(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
              _refresh();
            },
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
        onSubmitted: (_) => _refresh(),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        children: _roles.map((role) {
          return FilterChip(
            label: Text(role),
            selected: _roleFilter == role,
            onSelected: (_) {
              setState(() => _roleFilter = role);
              _refresh();
            },
          );
        }).toList(),
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'agent':
        return Colors.blue;
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
}

final _supabase = Supabase.instance.client;

Future<void> toggleAccountStatusRpc({
  required String customUserId,
  required bool disabled,
  required String changedBy,
  required String changedByRole,
}) async {
  await _supabase
      .from('user_profiles')
      .update({
        'account_disable': disabled,
        'updated_at': DateTime.now().toIso8601String(),
      })
      .eq('custom_user_id', customUserId);

  try {
    await _supabase.from('account_status_log').insert({
      'custom_user_id': customUserId,
      'disabled': disabled,
      'changed_by': changedBy,
      'changed_by_role': changedByRole,
      'changed_at': DateTime.now().toIso8601String(),
    });
  } catch (_) {}
}
