import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ScheduleStep extends StatelessWidget {
  final DateTime? selectedDate;
  final String? pickupTime;
  final TextEditingController materialController;
  final TextEditingController notesController;
  final bool isPrivate;
  final VoidCallback onDatePick;
  final VoidCallback onTimePick;
  final ValueChanged<bool?> onPrivateChanged;
  final VoidCallback onChanged;
  final Widget progressBar;
  final DateTime? pickupDate;
  final VoidCallback onPickupDatePick;

  const ScheduleStep({
    Key? key,
    required this.selectedDate,
    required this.pickupTime,
    required this.materialController,
    required this.notesController,
    required this.isPrivate,
    required this.onDatePick,
    required this.onTimePick,
    required this.onPrivateChanged,
    required this.onChanged,
    required this.progressBar,
    required this.pickupDate,
    required this.onPickupDatePick,
  }) : super(key: key);

  /// Required Text Field (Material 3 compliant)
  Widget _requiredTextField(
    TextEditingController controller,
    String label, {
    bool isNumeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            '$label *',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 12,
            ),
          ),
          validator: (val) =>
              val == null || val.trim().isEmpty ? 'Enter $label' : null,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          progressBar,

          /// Title
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'scheduleDetails'.tr(),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 10),

          /// Delivery Date
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.calendar_today, color: Colors.orange),
            ),
            title: Text(
              selectedDate == null
                  ? 'selectDeliveryDate'.tr()
                  : 'deliveryPrefix'.tr(
                      namedArgs: {
                        "date": DateFormat(
                          'MMM dd, yyyy',
                        ).format(selectedDate!),
                      },
                    ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: selectedDate == null
                ? Text('tapChooseDate'.tr())
                : Text(
                    '${selectedDate!.difference(DateTime.now()).inDays + 1} days from now',
                  ),
            onTap: onDatePick,
          ),

          const Divider(height: 1),

          /// Pickup Date
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: Icon(Icons.event, color: Colors.green.shade700),
            ),
            title: Text(
              pickupDate == null
                  ? 'selectPickupDate'.tr()
                  : 'pickupPrefix'.tr(
                      namedArgs: {
                        "date": DateFormat('MMM dd, yyyy').format(pickupDate!),
                      },
                    ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: pickupDate == null
                ? Text('tapChoosePickupDate'.tr())
                : Text(
                    '${pickupDate!.difference(DateTime.now()).inDays} days from now',
                  ),
            onTap: onPickupDatePick,
          ),

          const Divider(height: 1),

          /// Pickup Time
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.access_time, color: Colors.blue),
            ),
            title: Text(
              pickupTime == null
                  ? 'selectPickupTime'.tr()
                  : 'pickupTimePrefix'.tr(namedArgs: {"time": pickupTime!}),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('preferredPickupTime'.tr()),
            onTap: onTimePick,
          ),

          const SizedBox(height: 20),

          /// Material Inside
          _requiredTextField(materialController, 'materialInside'.tr()),

          const SizedBox(height: 16),

          /// Special Instructions
          Text(
            'specialInstructions'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: notesController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'specialInstructionsHint'.tr(),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.orange, width: 2),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            onChanged: (_) => onChanged(),
          ),

          const SizedBox(height: 10),

          /// Make Shipment Private
          CheckboxListTile(
            value: isPrivate,
            onChanged: onPrivateChanged,
            title: Text('makeShipmentPrivate'.tr()),
            subtitle: Text('makeShipmentPrivateSub'.tr()),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            visualDensity: const VisualDensity(vertical: -1, horizontal: -3),
          ),
        ],
      ),
    );
  }
}
