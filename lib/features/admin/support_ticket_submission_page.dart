import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import '../notifications/notification_service.dart';

class SupportTicketSubmissionPage extends StatefulWidget {
  const SupportTicketSubmissionPage({super.key});

  @override
  State<SupportTicketSubmissionPage> createState() =>
      _SupportTicketSubmissionPageState();
}

class _SupportTicketSubmissionPageState
    extends State<SupportTicketSubmissionPage> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _subjectController = TextEditingController();
  final _picker = ImagePicker();

  File? _selectedImage;
  bool _isSubmitting = false;
  String _selectedCategory = 'general';
  String _selectedPriority = 'medium';

  final List<String> _categoryKeys = [
    'general',
    'technical_issue',
    'data_not_loading',
    'app_crash',
    'login_problem',
    'payment_issue',
    'feature_request',
    'other'
  ];
  final Map<String, String> _categoryLabels = {
    'general': 'General',
    'technical_issue': 'Technical Issue',
    'data_not_loading': 'Data Not Loading',
    'app_crash': 'App Crash',
    'login_problem': 'Login Problem',
    'payment_issue': 'Payment Issue',
    'feature_request': 'Feature Request',
    'other': 'Other',
  };

  final List<String> _priorityKeys = ['low', 'medium', 'high', 'urgent'];
  final Map<String, String> _priorityLabels = {
    'low': 'Low',
    'medium': 'Medium',
    'high': 'High',
    'urgent': 'Urgent',
  };

  @override
  void dispose() {
    _messageController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      _showSnackBar('Error picking image: $e', Colors.red);
    }
  }

  Future<void> _takePicture() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      _showSnackBar('Error taking picture: $e', Colors.red);
    }
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title:  Text('Take Picture'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _takePicture();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title:  Text('Choose from Gallery'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              if (_selectedImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title:  Text('Remove Image'.tr()),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final fileName = '${const Uuid().v4()}.jpg';

      await Supabase.instance.client.storage
          .from('support-screenshots')
          .uploadBinary(fileName, bytes);

      final publicUrl = Supabase.instance.client.storage
          .from('support-screenshots')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      _showSnackBar('Error uploading image: $e', Colors.red);
      return null;
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get current user info
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _showSnackBar('Please log in to submit a support ticket'.tr(), Colors.red);
        return;
      }

      // Upload image if selected
      String? screenshotUrl;
      if (_selectedImage != null) {
        screenshotUrl = await _uploadImage();
      }

      // Get user profile data
      final userProfile = await Supabase.instance.client
          .from('user_profiles')
          .select('name, custom_user_id, role, email')
          .eq('user_id', user.id)
          .single();
      final ticketData = {
        'user_id': user.id,
        'user_name': userProfile['name'] ?? 'Unknown',
        'user_custom_id': userProfile['custom_user_id'] ?? 'Unknown',
        'user_email': userProfile['email'] ?? user.email ?? 'Unknown',
        'user_role': userProfile['role'] ?? 'Unknown',
        'subject': _subjectController.text.trim(),
        'category': _selectedCategory,
        'priority': _selectedPriority,
        'screenshot_url': screenshotUrl,
        'status': 'Pending',
        'message': _messageController.text.trim(),
        'chat_messages': [],
        'message_count': 0,
        'last_responder_type': 'user',
        'last_message_time': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await Supabase.instance.client
          .from('support_tickets')
          .insert(ticketData)
          .select()
          .single();

      final ticketId = response['id'].toString();
      final ticketSubject = _subjectController.text.trim();

      await NotificationService.sendNotification(
        recipientUserId: user.id,
        title: 'Ticket Created #$ticketId',
        message: 'We received your ticket "$ticketSubject". Our team will review it shortly.',
        data: {'type': 'support_ticket', 'ticket_id': ticketId},
      );
      NotificationService.notifyAdmins(
        title: 'New Support Ticket #$ticketId',
        message: '${userProfile['name'] ?? 'A user'} created a new ticket: $ticketSubject',
        data: {'type': 'support_ticket', 'ticket_id': ticketId},
      ).then((_) => print("Admin notifications sent"));

      _showSnackBar('Support ticket submitted successfully!'.tr(), Colors.green);
      Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Error submitting ticket: $e', Colors.red);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title:  Text('Request Support'.tr()), elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Describe your issue'.tr(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Our support team will help you resolve any problems you\'re experiencing with the app.'.tr(),
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Subject Field
                TextFormField(
                  controller: _subjectController,
                  decoration:  InputDecoration(
                    labelText: 'Subject *'.tr(),
                    hintText: 'Brief summary of your issue'.tr(),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a subject'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category'.tr(),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _categoryKeys.map((key) {
                    return DropdownMenuItem(
                      value: key,
                      child: Text(_categoryLabels[key]!.tr()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                ),

                const SizedBox(height: 16),


                DropdownButtonFormField<String>(
                  value: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Priority'.tr(),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.priority_high),
                  ),
                  items: _priorityKeys.map((key) {
                    return DropdownMenuItem(
                      value: key,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getPriorityColor(key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_priorityLabels[key]!.tr()),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedPriority = value!;
                    });
                  },
                ),

                const SizedBox(height: 16),

                // Message Field
                TextFormField(
                  controller: _messageController,
                  maxLines: 6,
                  decoration:  InputDecoration(
                    labelText: 'Describe your issue *'.tr(),
                    hintText:
                    'Please provide as much detail as possible about the problem you\'re experiencing...'.tr(),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please describe your issue'.tr();
                    }
                    if (value.trim().length < 10) {
                      return 'Please provide more details (at least 10 characters)'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.camera_alt, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Screenshot (Optional)'.tr(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Adding a screenshot helps us understand your issue better'.tr(),
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      if (_selectedImage != null) ...[
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(_selectedImage!, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          //color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: InkWell(
                          onTap: _showImagePicker,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(
                                  _selectedImage != null
                                      ? Icons.edit
                                      : Icons.add_a_photo,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _selectedImage != null
                                      ? 'Change Image'.tr()
                                      : 'Add Screenshot'.tr(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitTicket,
                    icon: _isSubmitting
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send),
                    label: Text(
                      _isSubmitting ? 'Submitting...'.tr() : 'Submit Support Request'.tr(),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Help Text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'We typically respond to support requests within 24 hours during business days.'.tr(),
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(String key) {
    switch (key) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'urgent':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

}