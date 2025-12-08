import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'shipment_tracking_page.dart';

class SharedShipmentsPage extends StatefulWidget {
  const SharedShipmentsPage({super.key});

  @override
  State<SharedShipmentsPage> createState() => _SharedShipmentsPageState();
}

class _SharedShipmentsPageState extends State<SharedShipmentsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sharedShipments = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSharedShipments();
  }

  Future<void> _fetchSharedShipments() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_shipments_shared_with_me',
      );

      dynamic data;
      if (response is PostgrestResponse) {
        data = response.data;
      } else {
        data = response;
      }

      if (data != null && data is List) {
        final List<Map<String, dynamic>> allShipments =
            List<Map<String, dynamic>>.from(data);

        final now = DateTime.now();
        final filtered = allShipments.where((shipment) {
          final status = shipment['booking_status']?.toString().toLowerCase();
          final completedAtStr =
              shipment['completed_at'] ?? shipment['updated_at'];

          if (status == 'completed' && completedAtStr != null) {
            final completedAt = DateTime.tryParse(completedAtStr.toString());
            if (completedAt != null) {
              return now.difference(completedAt).inHours < 24;
            }
          }
          return true;
        }).toList();

        if (mounted) {
          setState(() {
            _sharedShipments = filtered;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "fetch_error".tr(args: [e.toString()]);
        });
      }
      print(_errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("shared_with_me".tr())),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_sharedShipments.isEmpty) {
      return Center(
        child: Text(
          "no_shared_shipments".tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSharedShipments,
      child: ListView.builder(
        itemCount: _sharedShipments.length,
        itemBuilder: (context, index) {
          final shipment = _sharedShipments[index];
          final sharerName = shipment['sharer_name'] ?? 'someone'.tr();
          final shipmentId =
              shipment['shipment_id']?.toString() ?? "unknown".tr();

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.teal,
              ),
              title: Text(
                shipmentId,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "${'shared_by'.tr()}: $sharerName\n"
                "${'status'.tr()}: ${shipment['booking_status'] ?? 'N/A'}",
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              isThreeLine: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ShipmentTrackingPage(shipmentId: shipmentId),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
