import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import '../cubits/shipment_cubit.dart';
import 'shipment_card.dart';

class ShipmentListView extends StatelessWidget {
  final List<Map<String, dynamic>> shipments;
  final String searchQuery;

  const ShipmentListView({
    super.key,
    required this.shipments,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final filteredShipments = shipments.where((s) {
      final query = searchQuery.toLowerCase();
      final id = (s['shipment_id'] ?? '').toString().toLowerCase();
      final pickup = (s['pickup'] ?? '').toString().toLowerCase();
      final drop = (s['drop'] ?? '').toString().toLowerCase();
      // Search by shipper name as well
      final shipper = (s['shipper_name'] ?? '').toString().toLowerCase();

      return id.contains(query) ||
          pickup.contains(query) ||
          drop.contains(query) ||
          shipper.contains(query);
    }).toList();

    if (filteredShipments.isEmpty) {
      if (searchQuery.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'no_results_found'.tr(),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        );
      }
      return Center(child: Text('no_shipments'.tr()));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredShipments.length,
      itemBuilder: (context, index) {
        final trip = filteredShipments[index];
        return ShipmentCard(
          trip: trip,
          onAccept: () {
            // Trigger the accept action in the Cubit
            context.read<ShipmentCubit>().acceptShipment(
              shipmentId: trip['shipment_id'],
            );
          },
        );
      },
    );
  }
}