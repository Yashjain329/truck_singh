import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class TruckTypeStep extends StatelessWidget {
  final List<Map<String, dynamic>> truckTypes;
  final String? selectedTruckType;
  final ValueChanged<String> onTruckTypeSelected;
  final Widget progressBar;
  final String? shipperName;
  final bool isLoadingShipper;

  const TruckTypeStep({
    Key? key,
    required this.truckTypes,
    required this.selectedTruckType,
    required this.onTruckTypeSelected,
    required this.progressBar,
    required this.shipperName,
    required this.isLoadingShipper,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isLoadingShipper
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Text(
                    shipperName != null
                        ? "hiName".tr(namedArgs: {"name": shipperName!})
                        : "hiThere".tr(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
          progressBar,
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "selectTruckType".tr(),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: truckTypes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final type = truckTypes[index];
              final bool isSelected = selectedTruckType == type['key'];

              return GestureDetector(
                onTap: () => onTruckTypeSelected(type['key']),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.orange.shade100
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSelected ? Colors.orange : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        type['icon'],
                        size: 40,
                        color: isSelected
                            ? Colors.orange
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        type['key'].toString().tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.orange.shade800
                              : Colors.black87,
                        ),
                      ),
                      if (isSelected)
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.orange,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
