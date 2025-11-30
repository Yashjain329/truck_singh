import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/features/auth/model/address_model.dart';

enum PdfState { notGenerated, uploaded, downloaded }

Future<String> generateInvoicePDF({
  required Map<String, dynamic> shipment,
  required String price,
  required String companyName,
  required String companyAddress,
  required String companyMobile,
  required String customerName,
  required String customerAddress,
  required BillingAddress? billingAddress,
  required String customerMobile,
  required String invoiceNo,
  CompanyAddress? companySelectedAddress,
  required String bankName,
  required String accountNumber,
  required String ifscCode,
  required String branch,
  required String accountHolder,
  required String gstNumber,
  required String taxPercentage,
  required String taxAmount,
  required String totalAmount,
  required String taxType,
}) async {
  final pdf = pw.Document();
  final now = DateTime.now();

  final PdfColor primaryColor = PdfColors.blue800;
  final PdfColor secondaryColor = PdfColors.blueGrey600;
  final PdfColor tableHeaderColor = PdfColors.blue100;
  final border = pw.Border.all(color: PdfColors.blueGrey300, width: .8);

  String addressFormat(String addr) => addr.replaceAll(", ", ",\n");

  /// Reusable safe address fallback
  String safeAddress(String value, dynamic alt) =>
      value.isNotEmpty ? value : (alt != null ? alt : '');

  String finalCompanyAddress = safeAddress(
    companyAddress,
    companySelectedAddress != null
        ? "${companySelectedAddress.flatNo}, ${companySelectedAddress.streetName}, ${companySelectedAddress.cityName}, ${companySelectedAddress.district}, ${companySelectedAddress.zipCode}"
        : "",
  );

  String finalCustomerAddress = safeAddress(
    customerAddress,
    billingAddress != null
        ? "${billingAddress.flatNo}, ${billingAddress.streetName}, ${billingAddress.cityName}, ${billingAddress.district}, ${billingAddress.zipCode}"
        : "",
  );

  pw.Widget headerBox(String title, List<String> lines) => pw.Container(
    decoration: pw.BoxDecoration(border: border),
    padding: const pw.EdgeInsets.all(10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          color: tableHeaderColor,
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
              fontSize: 13,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        ...lines.map((e) => pw.Text(e, style: pw.TextStyle(fontSize: 10))),
      ],
    ),
  );

  pdf.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        /// Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  addressFormat(finalCompanyAddress),
                  style: pw.TextStyle(fontSize: 10, color: secondaryColor),
                ),
                pw.Text(
                  "Phone: $companyMobile",
                  style: pw.TextStyle(fontSize: 10, color: secondaryColor),
                ),
                pw.Text(
                  "GSTIN: $gstNumber",
                  style: pw.TextStyle(fontSize: 10, color: secondaryColor),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 16,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: primaryColor, width: 2),
                borderRadius: pw.BorderRadius.circular(6),
                color: primaryColor,
              ),
              child: pw.Text(
                "TAX INVOICE",
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),

        /// Bill To - Ship To - Invoice
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: headerBox("Bill To", [
                customerName,
                addressFormat(finalCustomerAddress),
                "Mobile: $customerMobile",
              ]),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: headerBox("Ship To", [
                shipment['drop'] ?? "N/A",
                "Mobile: $customerMobile",
              ]),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: headerBox("Invoice Details", [
                "Invoice No: $invoiceNo",
                "Date: ${DateFormat('dd-MM-yyyy').format(now)}",
              ]),
            ),
          ],
        ),

        pw.SizedBox(height: 18),

        /// Table Header
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          color: tableHeaderColor,
          child: pw.Row(
            children: [
              for (final t in [
                "No",
                "Item",
                "Qty",
                "Description",
                "Price",
                "Taxable Amt",
                taxType == "CGST+SGST" ? "CGST" : "IGST",
                taxType == "CGST+SGST" ? "SGST" : null,
                "Total",
              ].where((e) => e != null))
                pw.Expanded(
                  child: pw.Text(
                    t!,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),

        /// Item Row
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            children: [
              pw.Expanded(child: pw.Text("1")),
              pw.Expanded(
                child: pw.Text(
                  shipment['shipping_item'] ?? "Logistics Services",
                ),
              ),
              pw.Expanded(child: pw.Text("${shipment['weight'] ?? '1'} Ton")),
              pw.Expanded(
                child: pw.Text("${shipment['material_inside'] ?? ''}"),
              ),
              pw.Expanded(child: pw.Text(price)),
              pw.Expanded(child: pw.Text(taxAmount)),
              pw.Expanded(
                child: pw.Text(
                  taxType == "CGST+SGST"
                      ? "${double.parse(taxAmount) / 2}"
                      : taxPercentage,
                ),
              ),
              if (taxType == "CGST+SGST")
                pw.Expanded(child: pw.Text("${double.parse(taxAmount) / 2}")),
              pw.Expanded(
                child: pw.Text(
                  totalAmount,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 20),

        /// Totals
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Sub Total: $price"),
              pw.Text(
                taxType == "CGST+SGST"
                    ? "CGST + SGST: ${double.parse(taxAmount)}"
                    : "IGST: $taxAmount",
              ),
              pw.Text(
                "Total: $totalAmount",
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 20),

        /// Bank Info
        headerBox("Bank Details", [
          "Bank: $bankName",
          "Branch: $branch",
          "A/C: $accountNumber",
          "IFSC: $ifscCode",
          "Account Holder: $accountHolder",
        ]),

        pw.SizedBox(height: 20),
        pw.Text(
          "Terms & Conditions:",
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Text("This is a computer generated invoice."),
      ],
    ),
  );

  final pdfBytes = await pdf.save();

  final user = Supabase.instance.client.auth.currentUser!;
  final custom = await Supabase.instance.client
      .from('user_profiles')
      .select('custom_user_id')
      .eq('user_id', user.id)
      .maybeSingle();

  final shipperId = custom?['custom_user_id'];
  final filePath = "$shipperId/${shipment['shipment_id']}.pdf";

  await Supabase.instance.client.storage
      .from('invoices')
      .uploadBinary(
        filePath,
        pdfBytes,
        fileOptions: const FileOptions(upsert: true),
      );

  final url = Supabase.instance.client.storage
      .from('invoices')
      .getPublicUrl(filePath);

  await Printing.layoutPdf(onLayout: (_) => pdfBytes);

  return url;
}
