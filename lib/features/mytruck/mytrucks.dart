import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

// --- SERVICE CLASS ---
// Handles all database operations for trucks.
class TruckService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Helper to get the current user's custom ID.
  Future<String> _getCustomUserId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    try {
      final profile = await _supabase
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', user.id)
          .single();
      return profile['custom_user_id'];
    } catch (e) {
      throw Exception('Could not fetch user profile.');
    }
  }

  // Fetches all trucks for the current user and determines their availability based on active shipments.
  Future<List<Map<String, dynamic>>> fetchAllTrucks() async {
    final customUserId = await _getCustomUserId();

    // Get all trucks for this user
    final trucksResponse = await _supabase
        .from('trucks')
        .select('*')
        .eq('truck_admin', customUserId)
        .order('created_at', ascending: false);

    // Process each truck to determine its current status based on active shipments
    List<Map<String, dynamic>> trucksWithStatus = [];

    for (var truck in trucksResponse) {
      final truckNumber = truck['truck_number'];

      // Check if truck has any active (non-completed) shipments
      final activeShipmentResponse = await _supabase
          .from('shipment')
          .select(
            'booking_status, assigned_driver, user_profiles!shipment_assigned_driver_fkey(name)',
          )
          .eq('assigned_truck', truckNumber)
          .neq('booking_status', 'Completed')
          .limit(1);

      // Create truck data with dynamic status
      final truckWithStatus = Map<String, dynamic>.from(truck);

      if (activeShipmentResponse.isNotEmpty) {
        // Truck has active shipment - mark as "on_trip"
        truckWithStatus['status'] = 'on_trip';
        truckWithStatus['shipment'] = activeShipmentResponse;
      } else {
        // Check if truck status is manually set to maintenance
        if (truck['status'] == 'maintenance') {
          truckWithStatus['status'] = 'maintenance';
        } else {
          // Truck has no active shipments and not in maintenance - mark as available
          truckWithStatus['status'] = 'available';
        }
        truckWithStatus['shipment'] = [];
      }

      trucksWithStatus.add(truckWithStatus);
    }

    return trucksWithStatus;
  }

  // Add, update, and delete methods...
  Future<void> addTruck(Map<String, dynamic> truckData) async {
    final customUserId = await _getCustomUserId();
    await _supabase.from('trucks').insert({
      ...truckData,
      'truck_admin': customUserId,
    });
  }

  Future<void> updateTruck(
    String truckNumber,
    Map<String, dynamic> truckData,
  ) async {
    await _supabase
        .from('trucks')
        .update(truckData)
        .eq('truck_number', truckNumber);
  }

  Future<void> deleteTruck(String truckNumber) async {
    await _supabase.from('trucks').delete().eq('truck_number', truckNumber);
  }
}

// --- UI WIDGETS ---

class Mytrucks extends StatefulWidget {
  final bool selectable;
  const Mytrucks({super.key, this.selectable = false});

  @override
  State<Mytrucks> createState() => _MytrucksState();
}

class _MytrucksState extends State<Mytrucks> {
  final TruckService _truckService = TruckService();
  late Future<List<Map<String, dynamic>>> _trucksFuture;
  String _selectedFilter = 'my_trucks'.tr();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    // When in selection mode (assign truck), default to showing only available trucks
    if (widget.selectable) {
      _selectedFilter = 'available_only'.tr();
    }
    _loadTrucks();
  }

  void _loadTrucks() {
    setState(() {
      _trucksFuture = _truckService.fetchAllTrucks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('all_trucks'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => _SearchDialog(initial: _searchText),
              );
              if (result != null) setState(() => _searchText = result);
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _trucksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildSkeletonLoader();
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyState();
          }

          final allTrucks = snapshot.data!;
          return Column(
            children: [
              _buildStatHeader(allTrucks),
              if (widget.selectable)
                Container(
                  width: double.infinity,
                  color: Colors.green.shade50,
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Text(
                        'Please select an available truck for assignment',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Showing only available trucks (not assigned to other shipments)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _loadTrucks(),
                  child: _buildFilteredList(allTrucks),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: widget.selectable ? null : _buildAddTruckButton(),
    );
  }

  // --- BUILD HELPER WIDGETS ---

  Widget _buildFilteredList(List<Map<String, dynamic>> allTrucks) {
    List<Map<String, dynamic>> filteredTrucks = List.from(allTrucks);

    // Apply status filter
    if (_selectedFilter == 'Available Only'.tr() ||
        _selectedFilter == 'available_only'.tr()) {
      filteredTrucks.retainWhere((t) => t['status'] == 'available');
    } else if (_selectedFilter == 'On Trip'.tr() ||
        _selectedFilter == 'on_trip'.tr()) {
      filteredTrucks.retainWhere((t) => t['status'] == 'on_trip');
    } else if (_selectedFilter == 'Maintenance'.tr() ||
        _selectedFilter == 'maintenance'.tr()) {
      filteredTrucks.retainWhere((t) => t['status'] == 'maintenance');
    }

    // Apply search filter
    if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      filteredTrucks.retainWhere(
        (truck) =>
            (truck['truck_number']?.toLowerCase() ?? '').contains(q) ||
            (truck['make']?.toLowerCase() ?? '').contains(q) ||
            (truck['model']?.toLowerCase() ?? '').contains(q),
      );
    }

    if (filteredTrucks.isEmpty) {
      return Center(child: Text('no_trucks_match'.tr()));
    }

    return ListView.builder(
      itemCount: filteredTrucks.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return _buildTruckCard(filteredTrucks[index]);
      },
    );
  }

  Widget _buildStatHeader(List<Map<String, dynamic>> allTrucks) {
    final total = allTrucks.length;
    final available = allTrucks.where((t) => t['status'] == 'available').length;
    final onTrip = allTrucks.where((t) => t['status'] == 'on_trip').length;
    final maintenance = allTrucks
        .where((t) => t['status'] == 'maintenance')
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard("total".tr(), total, Colors.cyan, 'all_trucks'.tr()),
          _buildStatCard(
            "available".tr(),
            available,
            Colors.green,
            'available_only'.tr(),
          ),
          _buildStatCard("on_trip".tr(), onTrip, Colors.blue, 'on_trip'.tr()),
          _buildStatCard(
            "maintenance".tr(),
            maintenance,
            Colors.red,
            'maintenance'.tr(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color, String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTruckCard(Map<String, dynamic> truck) {
    final status = truck['status'] ?? 'unknown';
    final shipments = truck['shipment'] as List<dynamic>? ?? [];
    String driverName = 'No Driver Assigned';
    if (shipments.isNotEmpty) {
      final driverData = shipments.first['driver'] as Map<String, dynamic>?;
      driverName = driverData?['name'] ?? driverName;
    }

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'available':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'on_trip':
        statusColor = Colors.blue;
        statusIcon = Icons.directions_car;
        break;
      case 'maintenance':
        statusColor = Colors.red;
        statusIcon = Icons.build;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text(
          truck['truck_number'] ?? 'N/A',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${truck['make'] ?? ''} ${truck['model'] ?? ''} - ${truck['capacity_tons'] ?? 'N/A'} tons',
            ),
            Text(
              'Driver: $driverName',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
        trailing: widget.selectable
            ? (status == 'available'
                  ? ElevatedButton(
                      onPressed: () => Navigator.pop(context, truck),
                      child: const Text('Select'),
                    )
                  : const Text(
                      'Unavailable',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ))
            : const Icon(Icons.edit_outlined, size: 20),
        onTap: widget.selectable
            ? (status == 'available'
                  ? () => Navigator.pop(context, truck)
                  : null)
            : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditTruckPage(truck: truck)),
              ).then((_) => _loadTrucks()),
      ),
    );
  }

  Widget _buildAddTruckButton() {
    return FloatingActionButton(
      onPressed: () =>
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddTruckPage()),
          ).then((value) {
            if (value == true) _loadTrucks();
          }),
      child: const Icon(Icons.add),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 5,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: Colors.grey.shade300),
          title: Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 100,
            height: 16,
            color: Colors.grey.shade300,
          ),
          subtitle: Container(
            width: 150,
            height: 12,
            color: Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_shipping, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'no_trucks_found'.tr(),
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'tap_to_add_truck'.tr(),
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// --- ADD/EDIT TRUCK PAGES AND DIALOGS ---

class AddTruckPage extends StatefulWidget {
  const AddTruckPage({super.key});
  @override
  State<AddTruckPage> createState() => _AddTruckPageState();
}

class _AddTruckPageState extends State<AddTruckPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {
    'truck_number': TextEditingController(),
    'engine_number': TextEditingController(),
    'chassis_number': TextEditingController(),
    'vehicle_type': TextEditingController(),
    'make': TextEditingController(),
    'model': TextEditingController(),
    'year': TextEditingController(),
    'capacity_tons': TextEditingController(),
    'current_location': TextEditingController(),
  };
  String _fuelType = 'Diesel';
  String _status = 'available';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      try {
        await TruckService().addTruck({
          'truck_number': _controllers['truck_number']!.text.trim(),
          'engine_number': _controllers['engine_number']!.text.trim(),
          'chassis_number': _controllers['chassis_number']!.text.trim(),
          'vehicle_type': _controllers['vehicle_type']!.text.trim(),
          'make': _controllers['make']!.text.trim(),
          'model': _controllers['model']!.text.trim(),
          'year': int.tryParse(_controllers['year']!.text.trim()),
          'capacity_tons': double.tryParse(
            _controllers['capacity_tons']!.text.trim(),
          ),
          'fuel_type': _fuelType,
          'status': _status,
          'current_location': _controllers['current_location']!.text.trim(),
        });
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error adding truck: $e')));
        }
      }
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('add_new_truck'.tr())),
      bottomNavigationBar: _buildSubmitButton(),
      body: SafeArea(child: _buildForm()),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _controllers['truck_number'],
            decoration: InputDecoration(
              labelText: 'truck_number_required'.tr(),
            ),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['engine_number'],
            decoration: InputDecoration(labelText: 'engine_number'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['chassis_number'],
            decoration: InputDecoration(labelText: 'chassis_number'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['vehicle_type'],
            decoration: InputDecoration(labelText: 'vehicle_type'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['make'],
            decoration: InputDecoration(labelText: 'make_required'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['model'],
            decoration: InputDecoration(labelText: 'model_required'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['year'],
            decoration: InputDecoration(labelText: 'year_required'.tr()),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['capacity_tons'],
            decoration: InputDecoration(labelText: 'capacity_required'.tr()),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['current_location'],
            decoration: InputDecoration(labelText: 'current_location'.tr()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _fuelType,
            decoration: InputDecoration(labelText: 'fuel_type'.tr()),
            items: ['Diesel', 'CNG', 'Electric']
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.tr()), // Localized dropdown item
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _fuelType = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: InputDecoration(labelText: 'status'.tr()),
            items: ['available', 'on_trip', 'maintenance']
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.tr()), // Localized dropdown item
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text('add_truck'.tr()),
        ),
      ),
    );
  }
}

class EditTruckPage extends StatefulWidget {
  final Map<String, dynamic> truck;
  const EditTruckPage({super.key, required this.truck});
  @override
  State<EditTruckPage> createState() => _EditTruckPageState();
}

class _EditTruckPageState extends State<EditTruckPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {
    'truck_number': TextEditingController(),
    'engine_number': TextEditingController(),
    'chassis_number': TextEditingController(),
    'vehicle_type': TextEditingController(),
    'make': TextEditingController(),
    'model': TextEditingController(),
    'year': TextEditingController(),
    'capacity_tons': TextEditingController(),
    'current_location': TextEditingController(),
  };
  String _fuelType = 'Diesel';
  String _status = 'available';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controllers['truck_number']!.text = widget.truck['truck_number'] ?? '';
    _controllers['engine_number']!.text = widget.truck['engine_number'] ?? '';
    _controllers['chassis_number']!.text = widget.truck['chassis_number'] ?? '';
    _controllers['vehicle_type']!.text = widget.truck['vehicle_type'] ?? '';
    _controllers['make']!.text = widget.truck['make'] ?? '';
    _controllers['model']!.text = widget.truck['model'] ?? '';
    _controllers['year']!.text = widget.truck['year']?.toString() ?? '';
    _controllers['capacity_tons']!.text =
        widget.truck['capacity_tons']?.toString() ?? '';
    _controllers['current_location']!.text =
        widget.truck['current_location'] ?? '';
    _fuelType = widget.truck['fuel_type'] ?? 'Diesel';
    _status = widget.truck['status'] ?? 'available';
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      try {
        await TruckService().updateTruck(widget.truck['truck_number'], {
          'make': _controllers['make']!.text.trim(),
          'engine_number': _controllers['engine_number']!.text.trim(),
          'chassis_number': _controllers['chassis_number']!.text.trim(),
          'vehicle_type': _controllers['vehicle_type']!.text.trim(),
          'model': _controllers['model']!.text.trim(),
          'year': int.tryParse(_controllers['year']!.text.trim()),
          'capacity_tons': double.tryParse(
            _controllers['capacity_tons']!.text.trim(),
          ),
          'fuel_type': _fuelType,
          'status': _status,
          'current_location': _controllers['current_location']!.text.trim(),
        });
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error updating truck: $e')));
        }
      }
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteTruck() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('confirm_deletion'.tr()),
            content: Text('delete_truck_confirmation'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'delete'.tr(),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isSubmitting = true);
    try {
      await TruckService().deleteTruck(widget.truck['truck_number']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting truck: $e')));
      }
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('edit_truck'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.red,
            onPressed: _isSubmitting ? null : _deleteTruck,
          ),
        ],
      ),
      body: _buildForm(),
      bottomNavigationBar: _buildSubmitButton(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _controllers['truck_number'],
            enabled: false,
            decoration: InputDecoration(labelText: 'truck_number'.tr()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['engine_number'],
            enabled: false,
            decoration: InputDecoration(labelText: 'engine_number'.tr()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['chassis_number'],
            enabled: false,
            decoration: InputDecoration(labelText: 'chassis_number'.tr()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['vehicle_type'],
            enabled: false,
            decoration: InputDecoration(labelText: 'vehicle_type'.tr()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['make'],
            decoration: InputDecoration(labelText: 'make_required_field'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['model'],
            decoration: InputDecoration(labelText: 'model_required_field'.tr()),
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['year'],
            decoration: InputDecoration(labelText: 'year_required'.tr()),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['capacity_tons'],
            decoration: InputDecoration(
              labelText: 'capacity_required_field'.tr(),
            ),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty ? 'required'.tr() : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _controllers['current_location'],
            decoration: InputDecoration(labelText: 'current_location'.tr()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _fuelType,
            decoration: InputDecoration(labelText: 'fuel_type'.tr()),
            items: ['Diesel', 'CNG', 'Electric']
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.tr()), // Localized item
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _fuelType = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: InputDecoration(labelText: 'status'.tr()),
            items: ['available', 'on_trip', 'maintenance']
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.tr()), // Localized item
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text('update_truck'.tr()),
        ),
      ),
    );
  }
}

class _SearchDialog extends StatefulWidget {
  final String initial;
  const _SearchDialog({required this.initial});
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  late TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('search_truck'.tr()),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: "search_hint".tr()),
        onSubmitted: (val) => Navigator.pop(context, val),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text('search'.tr()),
        ),
      ],
    );
  }
}
