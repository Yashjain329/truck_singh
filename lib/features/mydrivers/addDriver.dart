import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/services/user_data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/features/disable/otp_activation_service.dart';

class AddDriverPage extends StatefulWidget {
  const AddDriverPage({super.key});

  @override
  _AddDriverPageState createState() => _AddDriverPageState();
}

class _AddDriverPageState extends State<AddDriverPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController inputController = TextEditingController();

  bool _pageIsLoading = true;
  bool _actionIsLoading = false;
  List<Map<String, dynamic>> addedDrivers = [];
  String? loggedInOwnerCustomId;

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    final ownerId = await UserDataService.getCustomUserId();
    if (!mounted) return;

    if (ownerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('could_not_identify_user'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _pageIsLoading = false);
      return;
    }

    setState(() {
      loggedInOwnerCustomId = ownerId;
    });

    await fetchAddedDrivers();
    setState(() => _pageIsLoading = false);
  }

  Future<void> addDriver() async {
    final input = inputController.text.trim();

    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_enter_driver_id_or_mobile'.tr())),
      );
      return;
    }

    if (loggedInOwnerCustomId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('owner_info_not_loaded'.tr())));
      return;
    }

    setState(() => _actionIsLoading = true);

    try {
      Map<String, dynamic>? userResponse;

      if (RegExp(r'^\d{10,}\$').hasMatch(input)) {
        final userList = await supabase
            .from('user_profiles')
            .select()
            .eq('mobile_number', input)
            .limit(1);

        if (userList.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('no_driver_with_mobile'.tr())));
          setState(() => _actionIsLoading = false);
          return;
        }
        userResponse = userList.first;
      } else {
        final userList = await supabase
            .from('user_profiles')
            .select()
            .eq('custom_user_id', input)
            .limit(1);

        if (userList.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('driver_not_found_id'.tr())));
          setState(() => _actionIsLoading = false);
          return;
        }
        userResponse = userList.first;
      }

      final driverCustomId = userResponse['custom_user_id'];

      if (driverCustomId == loggedInOwnerCustomId) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('cannot_add_self_driver'.tr())));
        setState(() => _actionIsLoading = false);
        return;
      }
      if (!driverCustomId.startsWith('DRV')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('cannot_add_non_driver'.tr())));
        setState(() => _actionIsLoading = false);
        return;
      }

      final alreadyRelated = await supabase
          .from('driver_relation')
          .select()
          .eq('owner_custom_id', loggedInOwnerCustomId!)
          .eq('driver_custom_id', driverCustomId)
          .maybeSingle();

      if (alreadyRelated != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('driver_already_added'.tr())));
        setState(() => _actionIsLoading = false);
        return;
      }

      await supabase.from('driver_relation').insert({
        'owner_custom_id': loggedInOwnerCustomId,
        'driver_custom_id': driverCustomId,
      });

      await fetchAddedDrivers();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('✅ driver_linked_success'.tr())));
      inputController.clear();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _actionIsLoading = false);
      }
    }
  }

  Future<void> fetchAddedDrivers() async {
    if (loggedInOwnerCustomId == null) return;

    try {
      final relationData = await supabase
          .from('driver_relation')
          .select('driver_custom_id')
          .eq('owner_custom_id', loggedInOwnerCustomId!);

      if (relationData.isEmpty) {
        setState(() => addedDrivers = []);
        return;
      }

      final List<String> driverIds = List<String>.from(
        relationData.map((item) => item['driver_custom_id']),
      );

      final driverList = await supabase
          .from('user_profiles')
          .select()
          .inFilter('custom_user_id', driverIds);

      setState(() {
        addedDrivers = List<Map<String, dynamic>>.from(driverList);
      });
    } catch (e) {
      if (mounted) {
        setState(() => addedDrivers = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_fetch_driver_list $e'.tr())),
        );
      }
    }
  }

  Future<void> deleteDriver(String driverId) async {
    if (loggedInOwnerCustomId == null) return;
    try {
      await supabase
          .from('driver_relation')
          .delete()
          .eq('owner_custom_id', loggedInOwnerCustomId!)
          .eq('driver_custom_id', driverId);

      setState(() {
        addedDrivers.removeWhere(
              (driver) => driver['custom_user_id'] == driverId,
        );
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('driver_removed'.tr())));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error deleting driver: $e')));
    }
  }

  Future<void> _toggleDriverAccountStatus(Map<String, dynamic> driver) async {
    final bool isCurrentlyDisabled = driver['account_disable'] ?? false;
    final bool willDisable = !isCurrentlyDisabled;
    final action = willDisable ? 'disable' : 'enable';

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No authenticated user found')));
        return;
      }

      // Get current user's role and email
      String currentUserRole = 'agent'; // Default fallback
      String userEmail = currentUser.email ?? 'unknown_user';

      try {
        final profileResponse = await supabase
            .from('user_profiles')
            .select('role')
            .eq('user_id', currentUser.id)
            .maybeSingle();

        if (profileResponse != null && profileResponse['role'] != null) {
          currentUserRole = profileResponse['role'];
        }
      } catch (e) {
        print('Warning: Could not fetch user role: $e');
      }

      // Use the proper function that updates tracking columns
      await toggleAccountStatusRpc(
        customUserId: driver['custom_user_id'],
        disabled: willDisable,
        changedBy: userEmail,
        changedByRole: currentUserRole,
      );

      // Create a success result object for compatibility
      final result = {'ok': true};

      if (!mounted) return;

      // Success - toggleAccountStatusRpc doesn't return an error on success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Driver account ${action}d successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await fetchAddedDrivers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('manage_drivers'.tr())),
      body: _pageIsLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: inputController,
              decoration: InputDecoration(
                labelText: 'enter_driver_id_mobile'.tr(),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _actionIsLoading ? null : addDriver,
              icon: _actionIsLoading
                  ? Container(
                width: 24,
                height: 24,
                padding: const EdgeInsets.all(2.0),
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
                  : const Icon(Icons.person_add_alt_1),
              label: Text('add_driver'.tr()),
            ),
            const SizedBox(height: 20),
            Text(
              'your_added_drivers'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            Expanded(
              child: addedDrivers.isEmpty
                  ? Center(child: Text('no_drivers_added'.tr()))
                  : RefreshIndicator(
                onRefresh: fetchAddedDrivers,
                child: ListView.builder(
                  itemCount: addedDrivers.length,
                  itemBuilder: (context, index) {
                    final driver = addedDrivers[index];
                    final isDisabled =
                        driver['account_disable'] ?? false;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 0,
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          '${driver['name'] ?? 'No Name'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'ID: ${driver['custom_user_id']}\nContact: ${driver['mobile_number'] ?? 'N/A'}\nStatus: ${isDisabled ? 'Disabled' : 'Enabled'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              icon: Icon(
                                isDisabled
                                    ? Icons.check_circle
                                    : Icons.block,
                                size: 18,
                              ),
                              label: Text(
                                isDisabled
                                    ? 'disable'.tr()
                                    : 'enable'.tr(),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDisabled
                                    ? Colors.green
                                    : Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () async {
                                final action = isDisabled
                                    ? 'enable'.tr()
                                    : 'disable'.tr();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      'confirm_deletion'.tr(),
                                    ),
                                    content: Text(
                                      'confirm_remove_driver'.tr(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(
                                              ctx,
                                              false,
                                            ),
                                        child: Text('cancel'.tr()),
                                      ),
                                      ElevatedButton(
                                        style:
                                        ElevatedButton.styleFrom(
                                          backgroundColor:
                                          isDisabled
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(
                                              ctx,
                                              true,
                                            ),
                                        child: Text(
                                          action.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _toggleDriverAccountStatus(
                                    driver,
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_forever,
                                color: Colors.red.shade700,
                              ),
                              onPressed: () async {
                                final confirm =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      'confirm_deletion'.tr(),
                                    ),
                                    content: Text(
                                      'confirm_remove_driver'
                                          .tr(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(
                                              ctx,
                                              false,
                                            ),
                                        child: Text(
                                          'cancel'.tr(),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(
                                              ctx,
                                              true,
                                            ),
                                        child: Text(
                                          'delete'.tr(),
                                          style:
                                          const TextStyle(
                                            color:
                                            Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await deleteDriver(
                                    driver['custom_user_id'],
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}