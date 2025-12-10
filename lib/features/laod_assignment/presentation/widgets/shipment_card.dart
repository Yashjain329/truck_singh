import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ShipmentCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final VoidCallback onAccept;

  const ShipmentCard({
    super.key,
    required this.trip,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    // Read directly from the 'shipper_name' field, with fallback to ID
    final shipperName = trip['shipper_name'] ?? trip['shipper_id'] ?? 'Unknown Shipper';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // SHIPMENT INFO
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip['shipment_id'] ?? 'No ID',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color:
                          Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'shipper_name'.tr(namedArgs: {'name': shipperName}),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                // STATUS LABEL
                Text(
                  'waiting_acceptance'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                )
              ],
            ),
          ),

          // MAIN CONTENT
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildLocationRow(
                  Icons.radio_button_checked,
                  'pickup'.tr(),
                  trip['pickup'],
                  Colors.green,
                  context,
                ),
                const SizedBox(height: 8),
                _buildLocationRow(
                  Icons.location_on,
                  'drop'.tr(),
                  trip['drop'],
                  Colors.red,
                  context,
                ),

                const SizedBox(height: 16),

                // INFO CHIPS
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        Icons.inventory_2_outlined,
                        '${trip['shipping_item']} • '
                            '${trip['weight']?.toString().trim().isNotEmpty == true
                            ? '${trip['weight']} kg'
                            : (trip['unit']?.toString().trim().isNotEmpty == true
                            ? '${trip['unit']} Unit'
                            : '')}',
                        context,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoChip(
                        Icons.schedule,
                        '${trip['delivery_date']} • ${trip['pickup_time']}',
                        context,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ACCEPT BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showAcceptConfirmationDialog(context, onAccept);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('accept_shipment'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      Theme.of(context).colorScheme.primary,
                      foregroundColor:
                      Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle:
                      const TextStyle(fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(
      IconData icon,
      String label,
      String location,
      Color color,
      BuildContext context,
      ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                location,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(
      IconData icon, String text, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.grey.shade100
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void showAcceptConfirmationDialog(
      BuildContext context, VoidCallback onConfirm) {
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
          ElevatedButton(
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
}