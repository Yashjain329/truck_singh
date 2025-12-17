import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

class CompanyDriverEmergencyScreen extends StatefulWidget {
  final String agentId;
  const CompanyDriverEmergencyScreen({super.key, required this.agentId});
  @override
  State<CompanyDriverEmergencyScreen> createState() =>
      _CompanyDriverEmergencyScreenState();
}

class _CompanyDriverEmergencyScreenState
    extends State<CompanyDriverEmergencyScreen> {
  final TextEditingController messageController = TextEditingController();

  final List<String> helpOptions = [
    'Technical Help',
    'Medical Help',
    'Fire',
    'Fleet Help',
  ];

  final Set<String> selectedOptions = {};
  bool _isSending = false;

  // Indian Highway Emergency Numbers
  final List<Map<String, String>> indianHighwayHelplines = [
    {
      'label': 'National Highway Helpline',
      'number': '1033',
      'desc': 'For accidents/breakdowns on NH',
    },
    {
      'label': 'National Emergency',
      'number': '112',
      'desc': 'Police, Fire, Ambulance',
    },
    {'label': 'Police', 'number': '100', 'desc': 'Local Police Support'},
    {'label': 'Ambulance', 'number': '108', 'desc': 'Medical Emergency'},
  ];

  void toggleSelection(String option) {
    setState(() {
      if (selectedOptions.contains(option)) {
        selectedOptions.remove(option);
      } else {
        selectedOptions.add(option);
      }
    });
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        _showErrorSnackBar('Could not launch dialer for $phoneNumber'.tr());
      }
    } catch (e) {
      _showErrorSnackBar('Error launching dialer: $e'.tr());
    }
  }

  Future<void> sendSOSNotification() async {
    if (selectedOptions.isEmpty) {
      _showErrorSnackBar(
        'Please select at least one type of help needed.'.tr(),
      );
      return;
    }

    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      _showErrorSnackBar(
        'Authentication error. Please log out and log in again.'.tr(),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final agentId = widget.agentId;
      final sosData = {
        'helpOptions': selectedOptions.toList(),
        'message': messageController.text,
      };

      final response = await http.post(
        Uri.parse(
          'https://rfbodmmhqkvqbufsbfnx.supabase.co/functions/v1/send-sos-notification',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'agentId': agentId, 'sosData': sosData}),
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar('SOS sent successfully!'.tr());
        if (mounted) Navigator.of(context).pop();
      } else {
        final errorBody = jsonDecode(response.body);
        _showErrorSnackBar('Failed to send SOS: ${errorBody['error']}'.tr());
      }
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e'.tr());
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showMessageBox = selectedOptions.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Emergency'.tr()),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Emergency Type'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 16),
              _buildHelpButtonsGrid(),
              const SizedBox(height: 16),
              if (showMessageBox)
                TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    labelText: 'Message for Agent'.tr(),
                    hintText: 'Describe the issue...'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.teal),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  maxLines: 3,
                ),
              if (showMessageBox) const SizedBox(height: 20),
              if (showMessageBox) _buildSubmitButton(),
              const SizedBox(height: 30),
              const Divider(thickness: 1),
              const SizedBox(height: 10),
              Text(
                'Indian Highway Helplines'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to call directly'.tr(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              _buildHelplineList(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpButtonsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: helpOptions.map(_buildGridHelpButton).toList(),
    );
  }

  Widget _buildGridHelpButton(String label) {
    final bool isSelected = selectedOptions.contains(label);
    IconData icon;
    List<Color> gradientColors;

    switch (label) {
      case 'Technical Help':
        icon = Icons.build;
        gradientColors = [Colors.blueAccent, Colors.indigo];
        break;
      case 'Medical Help':
        icon = Icons.local_hospital;
        gradientColors = [Colors.redAccent, Colors.red.shade700];
        break;
      case 'Fire':
        icon = Icons.local_fire_department;
        gradientColors = [Colors.orangeAccent, Colors.deepOrange];
        break;
      case 'Fleet Help':
        icon = Icons.local_shipping;
        gradientColors = [Colors.green, Colors.teal];
        break;
      default:
        icon = Icons.help;
        gradientColors = [Colors.grey.shade400, Colors.grey.shade600];
    }

    return GestureDetector(
      onTap: () => toggleSelection(label),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: Colors.black87, width: 3)
              : Border.all(color: Colors.transparent),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              label.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSending ? null : sendSOSNotification,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _isSending ? Colors.grey : Colors.teal,
        ),
        child: Center(
          child: _isSending
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  'Call The Agent'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHelplineList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: indianHighwayHelplines.length,
      itemBuilder: (context, index) {
        final item = indianHighwayHelplines[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.phone_in_talk, color: Colors.red),
            title: Text(item['label']!.tr()),
            subtitle: Text(item['desc']!.tr()),
            trailing: Text(
              item['number']!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: () => _makePhoneCall(item['number']!),
          ),
        );
      },
    );
  }
}
