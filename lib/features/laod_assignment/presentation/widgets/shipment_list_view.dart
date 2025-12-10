import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/shipment_cubit.dart';
import 'shipment_card.dart';
import 'package:easy_localization/easy_localization.dart';

class ShipmentListView extends StatelessWidget {
  final List<Map<String, dynamic>> shipments;
  final String searchQuery;

  const ShipmentListView({
    super.key,
    required this.shipments,
    required this.searchQuery,
  });

  /// Confirmation Dialog — Updated for latest Flutter Material 3
  void showAcceptConfirmationDialog(
      BuildContext context,
      VoidCallback onConfirm
      ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('confirm_shipment'.tr()),
        content: Text('confirm_accept_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: Text('yes_accept'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // SEARCH LOGIC
    final List<Map<String, dynamic>> filteredList = searchQuery.isEmpty
        ? shipments
        : shipments.where((trip) {
      final id = (trip['shipment_id'] ?? '')
          .toString()
          .toLowerCase();

      final source = (trip['pickup'] ?? '')
          .toString()
          .toLowerCase();

      final dest = (trip['drop'] ?? '')
          .toString()
          .toLowerCase();

      // UPDATED: Now searching against 'shipper_name' from the table
      final shipperName = (trip['shipper_name'] ?? '')
          .toString()
          .toLowerCase();

      final q = searchQuery.toLowerCase();

      return id.contains(q) ||
          source.contains(q) ||
          dest.contains(q) ||
          shipperName.contains(q);
    }).toList();

    // NO MATCH UI
    if (filteredList.isEmpty) {
      return Center(
        child: Text(
          'no_shipments_match'.tr(),
        ),
      );
    }
    // LIST VIEW
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final trip = filteredList[index];

        return ShipmentCard(
          trip: trip,
          onAccept: () {
            showAcceptConfirmationDialog(context, () {
              context.read<ShipmentCubit>().acceptShipment(
                shipmentId: trip['shipment_id'],
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('shipment accepted'.tr()),
                ),
              );
            });
          },
        );
      },
    );
  }
}