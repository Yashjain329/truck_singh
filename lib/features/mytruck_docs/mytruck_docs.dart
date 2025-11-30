import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../notifications/notification_service.dart';

enum FilePickerSource { camera, gallery }

class TruckDocsScreen extends StatefulWidget {
  const TruckDocsScreen({super.key});

  @override
  State createState() => _TruckDocsScreenState();
}

class _TruckDocsScreenState extends State<TruckDocsScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final uuid = const Uuid();
  final RefreshController refresh = RefreshController(initialRefresh: false);

  List<Map<String, dynamic>> trucks = [];
  Map<int, Map<String, Map<String, dynamic>>> truckDocs = {};
  Map<int, bool> expanded = {};
  String? uploadingTruck, uploadingType, loggedName;
  bool loading = true, searching = false, showPending = false;
  String search = '';
  final searchCtrl = TextEditingController();
  late AnimationController anim;

  final Map<String, Map<String, dynamic>> docTypes = {
    'Permit': {
      'icon': Icons.assignment,
      'desc': 'Valid permit',
      'color': Colors.blue,
    },
    'Insurance': {
      'icon': Icons.shield,
      'desc': 'Active insurance',
      'color': Colors.orange,
    },
    'Other': {
      'icon': Icons.insert_drive_file,
      'desc': 'Other document',
      'color': Colors.green,
    },
  };

  @override
  void initState() {
    super.initState();
    anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    searchCtrl.addListener(
      () => setState(() => search = searchCtrl.text.toLowerCase()),
    );
    fetchTrucks();
  }

  Future<String> getTempUser() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('temp_user_id');
    if (id == null) {
      id = uuid.v4();
      await prefs.setString('temp_user_id', id);
    }
    return id;
  }

  Future<String> getCustomUser() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return await getTempUser();
    try {
      final res = await supabase
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .single();
      return res['custom_user_id'] ?? 'TEMP_$userId';
    } catch (_) {
      return 'TEMP_$userId';
    }
  }

  Future fetchTrucks() async {
    setState(() => loading = true);
    try {
      final uid = await getCustomUser();
      final profile = await supabase
          .from('user_profiles')
          .select('name')
          .eq('custom_user_id', uid)
          .maybeSingle();
      loggedName = profile?['name'];

      final res = await supabase.from('trucks').select().eq('truck_admin', uid);
      trucks = List<Map<String, dynamic>>.from(res);
      expanded = {for (var t in trucks) t['id']: true};

      await Future.wait(trucks.map((t) => fetchDocs(t['id'])));
      anim.forward();
    } finally {
      loading = false;
      refresh.refreshCompleted();
      setState(() {});
    }
  }

  Future fetchDocs(int id) async {
    try {
      final res = await supabase
          .from('truck_documents')
          .select()
          .eq('truck_id', id);
      final list = List<Map<String, dynamic>>.from(res);
      final map = <String, Map<String, dynamic>>{};
      for (var type in docTypes.keys) {
        final doc = list.firstWhere(
          (d) => d['doc_type'] == type,
          orElse: () => {},
        );
        map[type] = {
          'uploaded': doc.isNotEmpty,
          'uploadedAt': doc['uploaded_at'],
          'filePath': doc['file_path'],
          'fileName': doc['file_name'],
          'docId': doc['id'],
        };
      }
      truckDocs[id] = map;
    } catch (_) {}
  }

  Future<List<String>> getTruckDrivers(String truckNo) async {
    try {
      final res = await supabase
          .from('shipment')
          .select('assigned_driver')
          .eq('assigned_truck', truckNo)
          .not('booking_status', 'in', '("Completed","cancelled")');
      return res
          .where((r) => r['assigned_driver'] != null)
          .map<String>((e) => e['assigned_driver'])
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future pickUpload(int id, String type) async {
    String? userId = supabase.auth.currentUser?.id;
    String? custom;

    if (userId == null) {
      custom = await getTempUser();
    } else {
      try {
        final profile = await supabase
            .from('user_profiles')
            .select('user_id')
            .eq('user_id', userId)
            .single();
        userId = profile['user_id'];
      } catch (_) {
        custom = userId;
        userId = null;
      }
    }

    final src = await showDialog<FilePickerSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, FilePickerSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, FilePickerSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (src == null) return;
    File? file;
    String name;

    if (src == FilePickerSource.camera) {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.camera);
      if (img == null) return;
      file = File(img.path);
      name = '${DateTime.now().millisecondsSinceEpoch}_${img.name}';
    } else {
      final result = await FilePicker.platform.pickFiles();
      if (result == null) return;
      file = File(result.files.single.path!);
      name =
          '${DateTime.now().millisecondsSinceEpoch}_${result.files.single.name}';
    }

    final path = '${userId ?? custom}/$id/$name';
    setState(() {
      uploadingTruck = "$id";
      uploadingType = type;
    });

    try {
      await supabase.storage.from('truck-docs').upload(path, file);
      await supabase.from('truck_documents').upsert({
        'truck_id': id,
        'user_id': userId,
        'custom_user_id': custom,
        'doc_type': type,
        'file_name': name,
        'file_path': path,
        'uploaded_at': DateTime.now().toIso8601String(),
      }, onConflict: 'truck_id,doc_type');

      if (custom != null) {
        final truck = trucks.firstWhere((t) => t['id'] == id);
        final drivers = await getTruckDrivers(truck['truck_number']);
        NotificationService.sendPushNotificationToUser(
          recipientId: custom,
          title: 'Document Uploaded'.tr(),
          message: 'Uploaded $type for ${truck['truck_number']}'.tr(),
          data: {'type': 'doc', 'truck': truck['truck_number']},
        );
        for (final d in drivers) {
          NotificationService.sendPushNotificationToUser(
            recipientId: d,
            title: 'Truck Document Updated'.tr(),
            message: '$loggedName uploaded $type for ${truck['truck_number']}'
                .tr(),
            data: {'type': 'update', 'truck': truck['truck_number']},
          );
        }
      }

      await fetchDocs(id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$type uploaded'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {uploadingTruck = null; uploadingType = null;});
    }
  }

  List<Map<String, dynamic>> filtered() {
    return trucks.where((t) {
      final id = t['id'];
      final docs = truckDocs[id] ?? {};
      final count = docs.values.where((d) => d['uploaded'] == true).length;
      final matchesText =
          search.isEmpty ||
          t['truck_number'].toString().toLowerCase().contains(search);
      final matchesPending = !showPending || count < docTypes.length;
      return matchesText && matchesPending;
    }).toList();
  }

  Widget buildDoc(int id, String type, Map info) {
    final typeInfo = docTypes[type]!;
    final uploaded = info['uploaded'] ?? false;
    final uploading = uploadingTruck == "$id" && uploadingType == type;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: uploaded ? Colors.green : Colors.grey.shade400,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(typeInfo['icon'], color: typeInfo['color']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(typeInfo['desc'], style: const TextStyle(fontSize: 12)),
                if (uploaded && info['uploadedAt'] != null)
                  Text(
                    'Uploaded: ${info['uploadedAt']}',
                    style: const TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),
          uploading
              ? const CircularProgressIndicator(strokeWidth: 2)
              : ElevatedButton(
                  onPressed: () => pickUpload(id, type),
                  child: Text(uploaded ? 'Update' : 'Upload'),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered();

    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search...'),
              )
            : const Text('Truck Documents'),
        actions: [
          searching
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    searching = false;
                    searchCtrl.clear();
                  }),
                )
              : Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => setState(() => searching = true),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.filter_list,
                        color: showPending ? Colors.blue : null,
                      ),
                      onPressed: () =>
                          setState(() => showPending = !showPending),
                    ),
                  ],
                ),
        ],
      ),
      body: SmartRefresher(
        controller: refresh,
        onRefresh: fetchTrucks,
        header: const WaterDropHeader(),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
            ? const Center(child: Text('No trucks found'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final t = list[i];
                  final id = t['id'];
                  final docs = truckDocs[id] ?? {};
                  final uploadedCount = docs.values
                      .where((d) => d['uploaded'] == true)
                      .length;
                  final isOpen = expanded[id] ?? true;

                  return AnimatedBuilder(
                    animation: anim,
                    builder: (_, child) => SlideTransition(
                      position:
                          Tween(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: anim,
                              curve: Interval(
                                i * .1,
                                1,
                                curve: Curves.easeOutBack,
                              ),
                            ),
                          ),
                      child: child!,
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.local_shipping),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t['truck_number'],
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isOpen
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onPressed: () =>
                                      setState(() => expanded[id] = !isOpen),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$uploadedCount / ${docTypes.length} uploaded',
                              style: TextStyle(
                                color: uploadedCount == docTypes.length
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                            if (isOpen) const SizedBox(height: 12),
                            if (isOpen)
                              ...docTypes.keys.map(
                                (type) => buildDoc(
                                  id,
                                  type,
                                  docs[type] ?? {'uploaded': false},
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
