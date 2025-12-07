import 'package:flutter/material.dart';
import '../invoice/services/invoice_pdf_service.dart';
import 'package:easy_localization/easy_localization.dart';
import '../ratings/presentation/screen/rating.dart';

class ShipmentCard extends StatefulWidget {
  final Map<String, dynamic> shipment;
  final VoidCallback? onPreviewInvoice;
  final VoidCallback? onDownloadInvoice;
  final VoidCallback? onRequestInvoice;
  final VoidCallback? onGenerateInvoice;
  final VoidCallback? onDeleteInvoice;
  final VoidCallback? onShareInvoice;
  final VoidCallback? onTap;
  final String? customUserId;
  final String? role;
  final Map<String, PdfState> pdfStates;
  final bool isInvoiceRequested;

  const ShipmentCard({
    super.key,
    required this.shipment,
    this.onPreviewInvoice,
    this.onDownloadInvoice,
    this.onRequestInvoice,
    this.onGenerateInvoice,
    this.onDeleteInvoice,
    this.onShareInvoice,
    this.onTap,
    required this.pdfStates,
    required this.role,
    required this.customUserId,
    this.isInvoiceRequested = false,
  });

  @override
  State<ShipmentCard> createState() => _ShipmentCardState();
}

class _ShipmentCardState extends State<ShipmentCard> {
  // Helper function to get the icon based on shipment status
  IconData getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Icons.pending_actions;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'en route to pickup':
        return Icons.local_shipping_outlined;
      case 'arrived at pickup':
        return Icons.location_on_outlined;
      case 'loading':
        return Icons.upload_file_outlined;
      case 'picked up':
        return Icons.task_alt;
      case 'in transit':
        return Icons.route_outlined;
      case 'arrived at drop':
        return Icons.pin_drop_outlined;
      case 'unloading':
        return Icons.download_outlined;
      case 'delivered':
        return Icons.delivery_dining;
      case 'completed':
        return Icons.verified_outlined;
      default:
        return Icons.info_outline;
    }
  }

  // Helper function to get the color based on shipment status
  Color getStatusColor(String? status, BuildContext context) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.orange.shade700;
      case 'accepted':
        return Colors.blue.shade700;
      case 'en route to pickup':
      case 'arrived at pickup':
      case 'loading':
      case 'picked up':
      case 'in transit':
      case 'arrived at drop':
      case 'unloading':
        return Colors.purple.shade700;
      case 'delivered':
      case 'completed':
        return Colors.green.shade700;
      default:
        return Theme.of(context).textTheme.bodySmall?.color ?? Colors.black45;
    }
  }

  // function to full trim address
  String trimAddress(String address) {
    // Remove common redundant words
    String cleaned = address
        .replaceAll(
      RegExp(
        r'\b(At Post|Post|Tal|Taluka|Dist|District|Po)\b',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    List<String> parts = cleaned.split(',');
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 3) {
      String first = parts[0];
      String city = parts[parts.length - 2];
      return "$first,$city";
    } else if (parts.length == 2) {
      return "${parts[0]}, ${parts[1]}";
    } else {
      return cleaned.length > 50 ? "${cleaned.substring(0, 50)}..." : cleaned;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipmentId = widget.shipment['shipment_id'] ?? 'Unknown';
    final completedAt = widget.shipment['delivery_date'] ?? '';
    final status = widget.shipment['booking_status']?.toString();
    final isCompleted = status?.toLowerCase() == 'completed';

    final statusColor = getStatusColor(status, context);
    final statusIcon = getStatusIcon(status);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 3,
      clipBehavior: Clip.antiAlias, // Ensures content respects rounded corners
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- NEW STATUS HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status ?? 'Unknown Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (!isCompleted)
                    TextButton.icon(
                      onPressed: widget.onTap, // Re-use the main tap action
                      icon: const Icon(Icons.track_changes_outlined, size: 18),
                      label: Text("track".tr()),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // --- MAIN CONTENT ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shipmentId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (completedAt.isNotEmpty && isCompleted)
                    Text(
                      "completed : $completedAt".tr(),
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  const SizedBox(height: 12,),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'PICKUP: ${trimAddress(widget.shipment['pickup'] ?? '')}',
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.flag, color: Colors.red, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'DROP: ${trimAddress(widget.shipment['drop'] ?? '')}',
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  buildActionButtons(
                    widget.shipment,
                    context,
                    widget.customUserId,
                    widget.role,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildActionButtons(
      Map<String, dynamic> shipment,
      BuildContext context,
      String? customUserId,
      String? role,
      ) {
    final shipperId = shipment['shipper_id']?.toString();
    final shipmentId = shipment['shipment_id'].toString();
    final assignCompanyId = shipment['assigned_agent']?.toString();
    final driverId = shipment['assigned_driver']?.toString();
    final invoicePath = shipment['Invoice_link'];
    final hasInvoice =
        invoicePath != null && invoicePath.toString().trim().isNotEmpty;
    final state = widget.pdfStates[shipmentId] ?? PdfState.notGenerated;
    final status = shipment['booking_status']?.toString().toLowerCase() ?? '';
    if (status != 'completed') {
      return const SizedBox.shrink();
    }

    print(
      "buildActionButtons: role=$role, customUserId=$customUserId, shipperId=$shipperId, assignedCompanyId=$assignCompanyId, hasInvoice=$hasInvoice, state=$state",
    );
    print(
      "Shipment: ${shipment['shipment_id']}, assigned_agent=${shipment['assigned_agent']}, shipper_id=${shipment['shipper_id']}",
    );
    bool isCreator = (role == 'truckowner' && customUserId == shipperId);
    bool isAssigned =
        (role == 'truckowner' || role == 'agent' || role == 'company') &&
            (customUserId == assignCompanyId);
    bool canCreate = isCreator || isAssigned;

    if (canCreate) {
      if (hasInvoice) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: state == PdfState.downloaded
                  ? null
                  : widget.onDownloadInvoice,
              icon: const Icon(Icons.download, size: 18),
              label: Text(
                state == PdfState.downloaded
                    ? "downloaded".tr()
                    : "download".tr(),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
            IconButton(
              onPressed: state == PdfState.downloaded
                  ? widget.onPreviewInvoice
                  : null,
              icon: const Icon(Icons.visibility),
              tooltip: 'preview_pdf'.tr(),
            ),
            IconButton(
              onPressed: widget.onShareInvoice,
              icon: const Icon(Icons.share),
              tooltip: 'share_invoice'.tr(),
            ),
            IconButton(
              onPressed: widget.onDeleteInvoice,
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'delete_pdf'.tr(),
            ),
          ],
        );
      } else {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isInvoiceRequested)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          "invoice_requested_by_shipper".tr(),
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(
              child: ElevatedButton.icon(
                onPressed: widget.onGenerateInvoice,
                icon: const Icon(Icons.receipt),
                label: Text("generate_invoice".tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        );
      }
    }

    if (role == 'shipper' && customUserId == shipperId) {
      if (hasInvoice) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: state == PdfState.downloaded
                  ? null
                  : widget.onDownloadInvoice,
              icon: const Icon(Icons.download, size: 18),
              label: Text(
                state == PdfState.downloaded
                    ? "downloaded".tr()
                    : "download".tr(),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
            IconButton(
              onPressed: state == PdfState.downloaded
                  ? widget.onPreviewInvoice
                  : null,
              icon: const Icon(Icons.visibility),
              tooltip: 'preview_pdf'.tr(),
            ),
          ],
        );
      } else {
        if (widget.isInvoiceRequested) {
          return SizedBox(
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_circle_outline, color: Colors.grey),
              label: Text("requested".tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
              ),
            ),
          );
        } else {
          return SizedBox(
            child: ElevatedButton.icon(
              onPressed: widget.onRequestInvoice,
              icon: const Icon(Icons.receipt_rounded),
              label: Text("request_invoice".tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
              ),
            ),
          );
        }
      }
    }
    if (role == 'driver' && customUserId == driverId) {
      return Wrap(
        spacing: 8,
        children: [
          SizedBox(
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Rating(shipmentId: shipmentId),
                  ),
                );
              },
              icon: const Icon(Icons.star),
              label: Text("rate".tr()),
            ),
          ),
        ],
      );
    } else {
      return const SizedBox();
    }
  }
}