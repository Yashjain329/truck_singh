import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:logistics_toolkit/services/gemini_service.dart';
import 'package:logistics_toolkit/services/intent_parser.dart';
import 'package:logistics_toolkit/services/shipment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/services/supabase_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? actionParameters;
  final String? actionButtonLabel;
  final String? actionButtonScreen;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    this.isUser = false,
    this.actionParameters,
    this.actionButtonLabel,
    this.actionButtonScreen,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // ye tab kam ayega jab mereko chatmessage ko json me change krna hoga jaise ki gemini service me krra hu
  Map<String, dynamic> toJson() {
    return {
      "text": text,
      "isUser": isUser,
      if (actionParameters?["action"] != null)
        "action": actionParameters!["action"],
      if (actionParameters?["language"] != null)
        "language": actionParameters!["language"],
    };
  }
}

class ChatProvider extends ChangeNotifier {
  final GeminiService gemini;
  final SupabaseClient supabase;
  final FlutterTts _tts = FlutterTts();

  List<ChatMessage> messages = [];
  bool ttsEnabled = true;
  bool speaking = false;

  //New : Add typing indicator variable
  bool _isTyping = false;

  bool get isTyping => _isTyping;

  // NEW: Language preference
  String _preferredLanguage = 'hinglish'; //Default
  String get preferredLanguage => _preferredLanguage;

  // 🔥 NEW: Track if user manually changed language
  bool _languageManuallySet = false;

  ChatProvider({required this.gemini, required this.supabase}) {
    _tts.setStartHandler(() {
      speaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      speaking = false;
      notifyListeners();
    });
    _tts.setErrorHandler((msg) {
      speaking = false;
      notifyListeners();
    });
  }

  /// 🔥 NEW: Sync chatbot language with app language (call this from ChatScreen)
  void syncWithAppLanguage(BuildContext context) {
    // Only sync if user hasn't manually changed language
    if (!_languageManuallySet) {
      final appLangCode = context.locale.languageCode;

      // Map app language to chatbot language
      if (appLangCode == 'hi') {
        _preferredLanguage = 'hindi';
      } else if (appLangCode == 'en') {
        _preferredLanguage = 'english';
      } else {
        _preferredLanguage = 'hinglish'; // Default
      }

      notifyListeners();
      print('Chatbot language synced with app: $_preferredLanguage');
    }
  }

  /// NEW: Set preferred language for chatbot responses
  void setPreferredLanguage(String language) {
    _preferredLanguage = language;
    _languageManuallySet = true; // Mark as manually set
    notifyListeners();
    print('Chatbot Language Set: $language');
  }

  /// 🔥 NEW: Reset to app language
  void resetToAppLanguage(BuildContext context) {
    _languageManuallySet = false;
    syncWithAppLanguage(context);
  }

  void toggleTts() {
    ttsEnabled = !ttsEnabled;
    notifyListeners();
  }

  // add message in the chatList  from userChat
  void addUserMessage(String text) {
    messages.add(
      ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
    );
    notifyListeners();
  }

  // add message in the chatList from chatBot model response
  void addBotMessage(ChatMessage msg) {
    messages.add(msg);
    notifyListeners();
    if (ttsEnabled)
      _speak(msg.text, msgActionLang: msg.actionParameters?['language']);
  }

  Future<void> _speak(String text, {String? msgActionLang}) async {
    try {
      //Map chatbot language to TTS locale
      String ttsLocale = 'en-US';
      if (msgActionLang == 'hindi') {
        ttsLocale = 'hi-IN';
      } else if (msgActionLang == 'hinglish') {
        ttsLocale = 'hi-IN';
      }
      await _tts.setLanguage(ttsLocale);
      await _tts.speak(text);
    } catch (e) {
      print('TTS Error: $e');
    }
  }

  // NEW: Method to simulate typing
  Future<void> _simulateTyping({int milliseconds = 800}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  Future<void> send(
      String input, {
        required void Function(String screen) onNavigate,
      }) async {
    addUserMessage(input);
    //for start ai is typing
    _isTyping = true;
    notifyListeners();

    await _simulateTyping(milliseconds: 600);

    try {
      // isme messages jo hai history hai.
      final raw = await gemini.queryRaw(input, messages, _preferredLanguage);
      final parsed = parseBotOutput(raw);

      //
      String replyText = parsed.reply.isNotEmpty
          ? parsed.reply
          : 'Reply received';
      Map<String, dynamic> params = parsed.parameters;

      // Decide if message should include an action button (open_screen)
      String? buttonLabel;
      String? buttonScreen;
      if (parsed.action == 'open_screen') {
        final screen = params['screen']?.toString() ?? '';

        if (screen == "track_trucks" || screen == "shipments") {
          final user = SupabaseService.getCurrentUser();
          if (user != null) {
          final customUid = await SupabaseService.getCustomUserId(user.id);
            if (screen == "track_trucks") {
              params['truckOwnerId'] = customUid;
            }
            if(screen == "shipments"){
              print('useridhai$customUid');
              params['driverId'] = customUid;
            }
          }
        }

        if(screen == "emergency"){
          try {
            final response = await ShipmentService.getActiveShipmentForDriver();
            if (response == null || response.isEmpty) {
              replyText = _localizeReply(
                  langCode: parsed.language,
                  english: "You are not currently on an active shipment. Emergency/SOS is only available during active trips. You can ask: 'Show my shipments' or 'Open my trips'.",
                  hindi: "आप वर्तमान में किसी सक्रिय शिपमेंट पर नहीं हैं। आपातकालीन/SOS केवल सक्रिय यात्राओं के दौरान उपलब्ध है। आप पूछ सकते हैं: 'मेरी शिपमेंट दिखाओ' या 'मेरी यात्राएँ खोलें'।",
                hinglish: "Aap currently kisi active shipment par nahi hain. Emergency/SOS sirf active trips ke dauran hi available hai. Aap puch sakte ho: 'Meri shipments dikhao' ya 'Meri trips kholo'.",
              );
              buttonScreen = null;
              buttonLabel = null;
            }else{
              // Get the AGENT ID from the active shipment
              final agentId = response["assigned_agent"];
              if(agentId != null && agentId.isNotEmpty){
                params['agentId'] = agentId;

                // ✅ Set button to open emergency screen
                buttonLabel = _getButtonLabel(screen, parsed.language);
                buttonScreen = screen;

                // ✅ Success message
                replyText = _localizeReply(
                  langCode: parsed.language,
                  english: "Opening emergency assistance. You can contact your assigned agent for help.",
                  hindi: "आपातकालीन सहायता खोल रहे हैं। आप सहायता के लिए अपने असाइन किए गए एजेंट से संपर्क कर सकते हैं।",
                  hinglish: "Emergency assistance khol rahe hain. Aap help ke liye apne assigned agent se contact kar sakte ho.",
                );
              }else{
                // ✅ Shipment exists but no agent assigned
                replyText = _localizeReply(
                  langCode: parsed.language,
                  english: "No agent is assigned to your current shipment. Please contact support.",
                  hindi: "आपकी वर्तमान शिपमेंट को कोई एजेंट असाइन नहीं है। कृपया सपोर्ट से संपर्क करें।",
                  hinglish: "Aapki current shipment ko koi agent assign nahi hai. Kripya support se contact karein.",
                );
                buttonLabel = null;
                buttonScreen = null;
              }
            }
          }catch(e){
            print('Error fetching active shipment for emergency: $e');
            replyText = _localizeReply(
              langCode: parsed.language,
              english: "Unable to check your shipment status. Please try again.",
              hindi: "आपकी शिपमेंट स्थिति की जाँच करने में असमर्थ। कृपया पुनः प्रयास करें।",
              hinglish: "Aapki shipment status check karne mein unable. Kripya dobara try karein.",
            );
            buttonLabel = null;
            buttonScreen = null;
          }
        }


        if (screen.isNotEmpty) {
          buttonLabel = _getButtonLabel(screen, parsed.language);
          buttonScreen = screen;
        }
      }

      //Simulate more typing for complex queries
      if (parsed.action != 'unknown' && parsed.action != 'open_screen') {
        await _simulateTyping(milliseconds: 400);
      }

      //if the action requires a DB query, do it here
      switch (parsed.action) {

      case 'get_assigned_shipments':
      final response = await ShipmentService.getActiveShipmentForDriver();
      if(response == null) return;
      final activeShipmentId = response['shipment_id'];
      final status = response['booking_status'];
      final drop = params["drop"] = response["drop"];
      final pickup =  params["pickup"] = response["pickup"];
      replyText = _localizeReply(
      langCode: parsed.language,
      english:
      'You assigned shipment.\nShipment IDs: $activeShipmentId\nstatus: $status\ndrop: $drop\npickup: $pickup',
      hindi:
      'आपके पास असाइन शिपमेंट हैं।\nशिपमेंट आईडी: $activeShipmentId\nस्थिति: $status\nडिलीवरी स्थान: $drop\nउठाने का स्थान: $pickup',
      hinglish:
      'Aapke paas assigned shipments hain.\nShipment IDs: $activeShipmentId\nstatus: $status\ndrop: $drop\npickup: $pickup',
      );
      break;

        case 'get_active_shipments':
          final response = await ShipmentService.getAllMyShipments();
          final count = (response as List).length;
          final activeShipmentIds = filterIdsByMap(response, 'shipment_id');
          replyText = _localizeReply(
            langCode: parsed.language,
            english:
                'You currently have $count active shipments.\nShipment IDs: ${activeShipmentIds.join(", ")}',
            hindi:
                'आपके पास वर्तमान में $count सक्रिय शिपमेंट हैं।\nशिपमेंट आईडी: ${activeShipmentIds.join(", ")}',
            hinglish:
                'Aapke paas currently $count active shipments hain.\nShipment IDs: ${activeShipmentIds.join(", ")}',
          );
          break;

        case 'get_completed_shipments':
          final response = await ShipmentService.getAllMyCompletedShipments();
          final completed = (response as List).length;
          replyText = _localizeReply(
            langCode: parsed.language,
            english: '$completed of your shipments have been completed.',
            hindi: 'आपकी $completed शिपमेंट पूरी हो चुकी हैं।',
            hinglish: 'Aapki $completed shipments complete ho chuki hain.',
          );
          break;

        case 'get_shared_shipments':
          final response = await ShipmentService.getSharedShipments();
          final shipmentIds = response.map((s) => s['shipment_id']).toList();
          if (shipmentIds.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'You do not have any shared shipments.',
              hindi: 'आपके पास कोई साझा शिपमेंट नहीं है।',
              hinglish: 'Aapke paas koi shared shipments nahi hain.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              english:
                  'You have ${shipmentIds.length} shared shipments.\nShipment IDs: ${shipmentIds.join(", ")}',
              hindi:
                  'आपके पास ${shipmentIds.length} साझा शिपमेंट हैं।\nशिपमेंट आईडी: ${shipmentIds.join(", ")}',
              hinglish:
                  'Aapke paas ${shipmentIds.length} shared shipments hain.\nShipment IDs: ${shipmentIds.join(", ")}',
            );
          }
          break;

        case 'get_my_trucks':
          final response = await ShipmentService.getAllTrucks();
          final truckNumbers = response.map((t) => t['truck_number']).toList();
          if (truckNumbers.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'You currently have 0 registered trucks.',
              hindi: 'आपके पास वर्तमान में 0 पंजीकृत ट्रक हैं।',
              hinglish: 'Aapke paas currently 0 registered trucks hain.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              english:
                  'You have ${response.length} trucks.\nTruck Numbers: ${truckNumbers.join(", ")}',
              hindi:
                  'आपके पास ${response.length} ट्रक हैं।\nट्रक नंबर: ${truckNumbers.join(", ")}',
              hinglish:
                  'Aapke paas ${response.length} trucks hain.\nTruck Numbers: ${truckNumbers.join(", ")}',
            );
          }
          break;

        case 'get_available_trucks':
          final response = await ShipmentService.getAvailableTrucks();
          final truckNumbers = response.map((t) => t['truck_number']).toList();
          if (truckNumbers.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'There are currently no available trucks.',
              hindi: 'वर्तमान में कोई उपलब्ध ट्रक नहीं है।',
              hinglish: 'Currently koi available trucks nahi hain.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              english:
                  '${response.length} trucks are currently available.\nTruck Numbers: ${truckNumbers.join(", ")}',
              hindi:
                  '${response.length} ट्रक वर्तमान में उपलब्ध हैं।\nट्रक नंबर: ${truckNumbers.join(", ")}',
              hinglish:
                  '${response.length} trucks currently available hain.\nTruck Numbers: ${truckNumbers.join(", ")}',
            );
          }
          break;

        case 'get_shipments_by_status':
          if (params["status"] == "Pending") {
            final response = await ShipmentService.getPendingShipments();
            final totalShipments = response
                .map((s) => s['shipment_id'])
                .toList();
            final statusLabel = params['status'];

            if (totalShipments.isEmpty) {
              replyText = _localizeReply(
                langCode: parsed.language,
                english:
                    'You currently have 0 shipments with status "$statusLabel".',
                hindi:
                    'आपके पास वर्तमान में "$statusLabel" स्थिति वाली 0 शिपमेंट हैं।',
                hinglish:
                    'Aapke paas currently "$statusLabel" status ki 0 shipments hain.',
              );
            } else {
              replyText = _localizeReply(
                langCode: parsed.language,
                english:
                    'You have ${totalShipments.length} shipments with status "$statusLabel" (driver not assigned).\nShipment IDs: ${totalShipments.join(", ")}',
                hindi:
                    'आपके पास "$statusLabel" स्थिति वाली ${totalShipments.length} शिपमेंट हैं (ड्राइवर असाइन नहीं)।\nशिपमेंट आईडी: ${totalShipments.join(", ")}',
                hinglish:
                    'Aapke paas "$statusLabel" status ki ${totalShipments.length} shipments hain (driver assigned nahi).\nShipment IDs: ${totalShipments.join(", ")}',
              );
            }
          } else {
            final response = await ShipmentService.getShipmentByStatus(
              status: params["status"],
            );
            final totalShipments = response
                .map((s) => s['shipment_id'])
                .toList();
            final statusLabel = params['status'];

            if (totalShipments.isEmpty) {
              replyText = _localizeReply(
                langCode: parsed.language,
                english:
                    'You currently have 0 shipments with status "$statusLabel".',
                hindi:
                    'आपके पास वर्तमान में "$statusLabel" स्थिति वाली 0 शिपमेंट हैं।',
                hinglish:
                    'Aapke paas currently "$statusLabel" status ki 0 shipments hain.',
              );
            } else {
              replyText = _localizeReply(
                langCode: parsed.language,
                english:
                    'You have ${totalShipments.length} shipments with status "$statusLabel".\nShipment IDs: ${totalShipments.join(", ")}',
                hindi:
                    'आपके पास "$statusLabel" स्थिति वाली ${totalShipments.length} शिपमेंट हैं।\nशिपमेंट आईडी: ${totalShipments.join(", ")}',
                hinglish:
                    'Aapke paas "$statusLabel" status ki ${totalShipments.length} shipments hain.\nShipment IDs: ${totalShipments.join(", ")}',
              );
            }
          }
          break;

        case 'get_status_by_shipment_id':
          final id = params['shipment_id'];
          if (id == null || id.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'Please provide the shipment ID.',
              hindi: 'कृपया शिपमेंट आईडी प्रदान करें।',
              hinglish: 'Kripya shipment ID provide karein.',
            );
            break;
          }

          try {
            final status = await ShipmentService.getStatusByShipmentId(
              shipmentId: id,
            );
            if (status == null) {
              replyText = _localizeReply(
                langCode: parsed.language,
                english: 'No status found for $id.',
                hindi: '$id के लिए कोई स्थिति नहीं मिली।',
                hinglish: '$id ke liye koi status nahi mila.',
              );
            } else {
              replyText = _localizeReply(
                langCode: parsed.language,
                english: 'The status of $id is: $status.',
                hindi: '$id की स्थिति है: $status।',
                hinglish: '$id ka status hai: $status.',
              );
            }
          } catch (e) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'Error fetching status.',
              hindi: 'स्थिति प्राप्त करने में त्रुटि।',
              hinglish: 'Status fetch karne mein error.',
            );
          }
          break;

        case 'get_all_drivers':
          final response = await ShipmentService.getAllDrivers();
          final driverNumbers = response
              .map((d) => d['driver_custom_id'])
              .toList();
          if (driverNumbers.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'There are currently 0 registered drivers.',
              hindi: 'वर्तमान में 0 पंजीकृत ड्राइवर हैं।',
              hinglish: 'Currently 0 registered drivers hain.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              english:
                  'You have ${driverNumbers.length} drivers.\nDriver IDs: ${driverNumbers.join(", ")}',
              hindi:
                  'आपके पास ${driverNumbers.length} ड्राइवर हैं।\nड्राइवर आईडी: ${driverNumbers.join(", ")}',
              hinglish:
                  'Aapke paas ${driverNumbers.length} drivers hain.\nDriver IDs: ${driverNumbers.join(", ")}',
            );
          }
          break;

        case 'get_driver_details':
          final driverId = params['driver_id'];
          if (driverId == null) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'Driver ID is empty.',
              hindi: 'ड्राइवर आईडी खाली है।',
              hinglish: 'Driver ID khali hai.',
            );
            break;
          }
          final response = await ShipmentService.getDriverDetails(
            userId: driverId,
          );
          final name = response['name'];
          final email = response['email'];
          final role = response['role'];

          replyText = _localizeReply(
            langCode: parsed.language,
            english: 'Driver details:\nName: $name\nEmail: $email\nRole: $role',
            hindi: 'ड्राइवर विवरण:\nनाम: $name\nईमेल: $email\nभूमिका: $role',
            hinglish:
                'Driver details:\nNaam: $name\nEmail: $email\nRole: $role',
          );
          break;

        case 'track_trucks':
          final response = await ShipmentService.getTrackTrucks(
            truckId: params['truck_number'],
          );
          if (response == null) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'Truck not found.',
              hindi: 'ट्रक नहीं मिला।',
              hinglish: 'Truck nahi mila.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              english: 'Your truck is currently at $response.',
              hindi: 'आपका ट्रक वर्तमान में $response पर है।',
              hinglish: 'Aapka truck currently $response par hai.',
            );
          }
          break;

        case 'get_marketplace_shipment':
          final list = await ShipmentService.getAvailableMarketplaceShipments();
          final marketplaceIds = filterIdsByMap(list, "shipment_id");

          replyText = _localizeReply(
            langCode: parsed.language,
            english:
                'There are ${list.length} marketplace shipments available.\nShipment IDs: ${marketplaceIds.join(", ")}',
            hindi:
                '${list.length} मार्केटप्लेस शिपमेंट उपलब्ध हैं।\nशिपमेंट आईडी: ${marketplaceIds.join(", ")}',
            hinglish:
                '${list.length} marketplace shipments available hain.\nShipment IDs: ${marketplaceIds.join(", ")}',
          );
          break;

        case 'open_screen':
          final screen = params['screen']?.toString() ?? '';
          replyText = parsed.reply.isNotEmpty
              ? parsed.reply
              : _localizeReply(
                  langCode: parsed.language,
                  english: 'Opening $screen screen.',
                  hindi: '$screen स्क्रीन खोल रहे हैं।',
                  hinglish: '$screen screen khol rahe hain.',
                );

          if (screen.isNotEmpty) {
            buttonLabel = _getButtonLabel(screen, parsed.language);
            buttonScreen = screen;
          }
          break;

        default:

          if (replyText.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              english:
                  'I could not understand this request. You can ask about shipments, trucks, or drivers.',
              hindi:
                  'मैं इस अनुरोध को समझ नहीं सका। आप शिपमेंट, ट्रक या ड्राइवरों के बारे में पूछ सकते हैं।',
              hinglish:
                  'Main is request ko samajh nahi saka. Aap shipments, trucks ya drivers ke baare mein puch sakte ho.',
            );
          }
          break;
      }

      addBotMessage(
        ChatMessage(
          text: replyText,
          isUser: false,
          actionParameters: {
            'language': parsed.language,
            'action': parsed.action,
            // ✅ Sab parameters include karo
            if (params['truckOwnerId'] != null)
              'truckOwnerId': params['truckOwnerId'],
            if (params['driverId'] != null)
              'driverId': params['driverId'],
            if (params['agentId'] != null)
              'agentId': params['agentId'],
          },
          actionButtonLabel: buttonLabel,
          actionButtonScreen: buttonScreen,
        ),
      );
    } catch (e) {
      addBotMessage(

        ChatMessage(
          text: _localizeReply(
            langCode: _preferredLanguage,
            english:
                'I am having trouble understanding this. Please try again in simpler words.',
            hindi:
                'मुझे इसे समझने में परेशानी हो रही है। कृपया सरल शब्दों में पुनः प्रयास करें।',
            hinglish:
                'Mujhe ise samajhne mein pareshani ho rahi hai. Kripya simple shabdon mein dobara try karein.',
          ),
          isUser: false,
        ),
      );
      print('Send Error: $e');
    } finally {
      _isTyping = false;
      notifyListeners();
    }
  }

  // this is for format language in the response.
  String _localizeReply({
    required String langCode,
    required String english,
    required String hindi,
    required String hinglish,
  }) {
    // Gemini se "hi" aaega Hindi/Hinglish ke liye, "en" English ke liye
    switch (langCode) {
      case 'hindi':
        return hindi;
      case 'hinglish':
        return hindi;
      default:
        return english;
    }
  }

  String _getButtonLabel(String screen, String language) {
    final labels = {
      'english': 'Open $screen',
      'hindi': '$screen खोलें',
      'hinglish': '$screen kholen',
    };
    return labels[language] ?? labels['english']!;
  }

  //NEW : Clear chat method
  void clearChat() {
    messages.clear();
    _isTyping = false;
    notifyListeners();
  }
}

List<String> filterIdsByMap(List<Map<String, dynamic>> shipments, String key) {
  return shipments
      .map((map) => map[key].toString())
      .where((id) => id.isNotEmpty)
      .toList();
}
