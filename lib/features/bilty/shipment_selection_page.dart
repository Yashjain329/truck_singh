import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logistics_toolkit/features/bilty/bilty_pdf_preview_screen.dart';
import 'package:logistics_toolkit/features/bilty/transport_bilty_form.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PdfState { notDownloaded, downloaded }

class ShipmentSelectionPage extends StatefulWidget {
  const ShipmentSelectionPage({super.key});

  @override
  State<ShipmentSelectionPage> createState() => _ShipmentSelectionPageState();
}

class _ShipmentSelectionPageState extends State<ShipmentSelectionPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> shipments = [];
  final Map<String, Map<String, dynamic>> biltyMap = {};
  final Map<String, PdfState> biltyStates = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchShipments();
  }

  Future<void> _fetchShipments() async {
    setState(() => isLoading = true);

    final customId = _client.auth.currentUser?.userMetadata?['custom_user_id'];
    if (customId == null) {
      setState(() => isLoading = false);
      return;
    }

    shipments = List<Map<String, dynamic>>.from(
      await _client
          .from('shipment')
          .select('shipment_id, pickup, drop, delivery_date')
          .eq('assigned_agent', customId)
          .order('created_at', ascending: false),
    );

    for (var s in shipments) {
      final id = s['shipment_id'].toString();
      final bilty = await _client
          .from('bilties')
          .select()
          .eq('shipment_id', id)
          .maybeSingle();
      if (bilty != null) {
        biltyMap[id] = Map<String, dynamic>.from(bilty);

        final file = File(
          '${(await getApplicationDocumentsDirectory()).path}/$id.pdf',
        );
        biltyStates[id] = await file.exists()
            ? PdfState.downloaded
            : PdfState.notDownloaded;
      }
    }

    setState(() => isLoading = false);
  }

  Future<void> _downloadPdf(Map<String, dynamic> bilty) async {
    final id = bilty['shipment_id'].toString();
    final url = _client.storage
        .from('bilties')
        .getPublicUrl(bilty['file_path']);

    final _ = File(
      '${(await getApplicationDocumentsDirectory()).path}/$id.pdf',
    )..writeAsBytesSync((await http.get(Uri.parse(url))).bodyBytes);

    biltyStates[id] = PdfState.downloaded;
    setState(() {});
    _toast('biltyPdfDownloaded'.tr());
  }

  Future<void> _share(String id) async {
    final file = File(
      '${(await getApplicationDocumentsDirectory()).path}/$id.pdf',
    );
    if (!await file.exists()) return _toast('pleaseDownloadBeforeSharing'.tr());

    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: "Bilty: #$id"));
  }

  Future<void> _delete(String id) async {
    if (await _confirm('deleteBilty'.tr(), 'deleteBiltyConfirmation'.tr()) !=
        true)
      return;

    final bilty = biltyMap[id];
    if (bilty == null) return _toast('noBiltyFoundToDelete'.tr());

    isLoading = true;
    await _client.storage.from('bilties').remove([bilty['file_path']]);
    await _client.from('bilties').delete().eq('shipment_id', id);

    final file = File(
      '${(await getApplicationDocumentsDirectory()).path}/$id.pdf',
    );
    if (await file.exists()) file.deleteSync();

    biltyStates[id] = PdfState.notDownloaded;
    biltyMap.remove(id);

    setState(() {});
    isLoading = false;
    _toast('biltyDeletedSuccessfully'.tr());
  }

  Future<bool?> _confirm(String title, String msg) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('delete'.tr(), style: const TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String trimAddress(String address) =>
      address.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ------- UI --------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("selectShipmentForBilty".tr())),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _fetchShipments,
          child: shipments.isEmpty
              ? Center(child: Text("noShipmentsFound".tr()))
              : ListView.builder(
            itemCount: shipments.length,
            itemBuilder: (_, i) => _buildTile(shipments[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> s) {
    final id = s['shipment_id'].toString();
    final bilty = biltyMap[id];
    final state = biltyStates[id] ?? PdfState.notDownloaded;

    return Card(
      margin: const EdgeInsets.all(8),
      child: ListTile(
        title: Text(
          "Shipment $id",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("📍 ${trimAddress(s['pickup'] ?? '')}"),
            Text("🏁 ${trimAddress(s['drop'] ?? '')}"),
            Text("📅 ${s['delivery_date'] ?? 'N/A'}"),
            const SizedBox(height: 8),

            bilty == null
                ? ElevatedButton(
              onPressed: () => _openForm(id),
              child: Text("generateBilty".tr()),
            )
                : Row(
              children: [
                ElevatedButton(
                  onPressed: state == PdfState.downloaded
                      ? null
                      : () => _downloadPdf(bilty),
                  child: Text(
                    state == PdfState.downloaded
                        ? "downloaded".tr()
                        : "downloadBilty".tr(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_red_eye),
                  onPressed: () => _viewPdf(id),
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: state == PdfState.downloaded
                      ? () => _share(id)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _delete(id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openForm(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BiltyFormPage(shipmentId: id)),
    );
    _fetchShipments();
  }

  void _viewPdf(String id) async {
    final file = File(
      '${(await getApplicationDocumentsDirectory()).path}/$id.pdf',
    );
    if (!await file.exists()) return _toast('biltyPdfNotFound'.tr());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BiltyPdfPreviewScreen(localPath: file.path),
      ),
    );
  }
}