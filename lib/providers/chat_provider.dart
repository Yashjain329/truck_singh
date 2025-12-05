
import 'package:flutter/cupertino.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:logistics_toolkit/features/mytruck/mytrucks.dart';
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

  ChatMessage({
    required this.text,
    this.isUser = false,
    this.actionParameters,
    this.actionButtonLabel,
    this.actionButtonScreen,
  });

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
  bool loading = false;

  ChatProvider({required this.gemini, required this.supabase}) {
    _tts.setStartHandler(() => speaking = true);
    _tts.setCompletionHandler(() {
      speaking = false;
      notifyListeners();
    });
    _tts.setErrorHandler((msg) {
      speaking = false;
      notifyListeners();
    });
  }

  // this is for format language in the response.
  String _localizeReply({
    required String langCode,
    required String hiText,
    required String enText,
  }) {
    // Gemini se "hi" aaega Hindi/Hinglish ke liye, "en" English ke liye
    if (langCode == 'hi') {
      return hiText;
    } else {
      return enText;
    }
  }


  void toggleTts() {
    ttsEnabled = !ttsEnabled;
    notifyListeners();
  }

  // add message in the chatList  from userChat
  void addUserMessage(String text) {
    messages.add(ChatMessage(text: text, isUser: true));
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
      final langCode = msgActionLang ?? 'en';
      await _tts.setLanguage(langCode);
      await _tts.speak(text);
    } catch (e) {
      print(e);
    }
  }

  Future<void> send(
    String input, {
    required void Function(String screen) onNavigate,
  }) async {
    addUserMessage(input);
    loading = true;
    notifyListeners();

    try {
      // isme messages jo hai history hai.
      final raw = await gemini.queryRaw(input, messages);
      final parsed = parseBotOutput(raw);

      //
      String replyText = parsed.reply.isNotEmpty
          ? parsed.reply
          : 'Reply received';
      Map<String, dynamic> params = parsed.parameters;

      // Decide if message should include an action button (open_screen)
      String? buttonLabel;
      String? buttonScreen;
      if (parsed.action == 'open_screen'){
        final screen = params['screen']?.toString() ?? '';

        if (screen == "track_trucks") {
          final user = await SupabaseService.getCurrentUser();
          print('User in tracktruck:$user');
          final customUid = await SupabaseService.getCustomUserId(user!.id);
          print('customUid in trackTruck:$customUid');

          params['truckOwnerId'] = customUid;
        }

        if (screen.isNotEmpty) {
          buttonLabel = 'open ${screen}';
          buttonScreen = screen;
        }
      }

      //if the action requires a DB query, do it here
      switch (parsed.action) {

      //GET ACTIVE SHIPMENTS
        case 'get_active_shipments':
          final response = await ShipmentService.getAllMyShipments();
          final count = (response as List).length;
          final active_shipment_ids = filterIdsByMap(response, 'shipment_id');
          replyText = _localizeReply(
            langCode: parsed.language,
            hiText: 'Aapki $count shipments abhi active hain.\nActive Shipments IDs: ${active_shipment_ids.join(",")}',
            enText: 'You currently have $count active shipments.\nActive shipment IDs: ${active_shipment_ids.join(",")}',
          );
          break;

      //GET COMPLETED SHIPMENTS
        case 'get_completed_shipments':
          final response = await ShipmentService.getAllMyCompletedShipments();
          final completed = (response as List).length;
          replyText = _localizeReply(
            langCode: parsed.language,
            hiText: 'Aapke $completed shipments complete ho chuke hain.',
            enText: '$completed of your shipments have been completed.',
          );
          break;

      //GET SHARED SHIPMENTS
        case 'get_shared_shipments':
          final response = await ShipmentService.getSharedShipments();
          final shipmentIds = response.map((singleShipment) => singleShipment['shipment_id']).toList();
          if (shipmentIds.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Koi bhi shipment shared nahi hai.',
              enText: 'You do not have any shared shipments.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              'Aapke paas ${shipmentIds.length} shipments abhi shared hain.\nShipments IDs: ${shipmentIds.join(",")}',
              enText:
              'You currently have ${shipmentIds.length} shared shipments.\nShipment IDs: ${shipmentIds.join(",")}',
            );
          }
          break;


      //GET ALL TRUCKS
        case 'get_my_trucks':
          final response = await ShipmentService.getAllTrucks();
          final truckNumbers = response.map((single_truck) => single_truck['truck_number']).toList() ;
          if (truckNumbers.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Aapke paas abhi 0 trucks registered hain.',
              enText: 'You currently have 0 registered trucks.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              '${response.length} trucks hain.\nTrucks Numbers: ${truckNumbers.join(",")}',
              enText:
              'You have ${response.length} trucks.\nTruck numbers: ${truckNumbers.join(",")}',
            );
          }
          break;

      //GET AVAILABLE TRUCKS
        case 'get_available_trucks':
          final response = await ShipmentService.getAvailableTrucks();
          final truckNumbers = response.map((single_truck) => single_truck['truck_number']).toList() ;
          if (truckNumbers.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Abhi koi bhi truck khali nahi hai.',
              enText: 'There are currently no available (empty) trucks.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              '${response.length} trucks abhi khali hain.\nTrucks Numbers: ${truckNumbers.join(",")}',
              enText:
              '${response.length} trucks are currently available.\nTruck numbers: ${truckNumbers.join(",")}',
            );
          }
          break;

      //GET SHIPMENTS BY STATUS
        case 'get_shipments_by_status':
          final response = await ShipmentService.getShipmentByStatus(
            status: params["status"],
          );

          print("STATUS FROM CHAT PROVIDERa: '${params["status"]}'");


          final totalShipments = response.map((shipment) => shipment['shipment_id']).toList() ;
          print("STATUS FROM CHAT PROVIDERb: '${totalShipments.length}'");

          final statusLabel = params['status'];

          if (totalShipments.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              'Abhi 0 shipments "$statusLabel" status me hain.',
              enText:
              'You currently have 0 shipments with status "$statusLabel".',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              '${totalShipments.length} shipments abhi "$statusLabel" status me hain.\nShipment IDs: ${totalShipments.join(",")}',
              enText:
              'You currently have ${totalShipments.length} shipments with status "$statusLabel".\nShipment IDs: ${totalShipments.join(",")}',
            );
          }
          break;

      //  GET STATUS BY SHIPMENT ID
        case 'get_status_by_shipment_id':
          final id = params['shipment_id'];

          print("shipmentid in the chatprobider : $id");

          if (id == null || id.isEmpty) {
            replyText = "Shipment ID batao.";
            break;
          }

          final shipmentId = id;

          try {
            final status = await ShipmentService.getStatusByShipmentId(
              shipmentId: shipmentId,
            );

            if (status == null) {
              replyText = _localizeReply(
                langCode: parsed.language,
                hiText: '$shipmentId ka koi status nahi mila.',
                enText: 'No status found for $shipmentId.',
              );
            } else {
              replyText = _localizeReply(
                langCode: parsed.language,
                hiText: '$shipmentId ka status: $status hai.',
                enText: 'The status of $shipmentId is: $status.',
              );
            }
          } catch (e) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Status fetch karne me error aaya.',
              enText: 'There was an error while fetching the status.',
            );
          }
          break;

      //GET ALL DRIVERS
        case 'get_all_drivers':
          final response = await ShipmentService.getAllDrivers();
          final driverNumbers = response.map((driver) => driver['driver_custom_id']).toList() ;
          if (driverNumbers.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Abhi 0 drivers registered hain.',
              enText: 'There are currently 0 registered drivers.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              '${driverNumbers.length} drivers hain.\nDriver Numbers: ${driverNumbers.join(",")}',
              enText:
              'You have ${driverNumbers.length} drivers.\nDriver IDs: ${driverNumbers.join(",")}',
            );
          }
          break;

      //GET DRIVER DETAILS
        case 'get_driver_details':
          final driverId = params['driver_id'];
          if (driverId == null) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Driver ID empty hai.',
              enText: 'Driver ID is empty.',
            );
            return;
          }
          final response =
          await ShipmentService.getDriverDetails(userId: driverId);
          final name = response['name'];
          final email = response['email'];
          final role = response['role'];

          replyText = _localizeReply(
            langCode: parsed.language,
            hiText:
            'Driver details:\nNaam: $name\nEmail: $email\nRole: $role',
            enText:
            'Driver details:\nName: $name\nEmail: $email\nRole: $role',
          );
          break;


      //GET TRACK TRUCKS
        case 'track_trucks':
          final response = await ShipmentService.getTrackTrucks(
            truckId: params['truck_number'],
          );
          if (response == null) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Truck nahi mila.',
              enText: 'Truck not found.',
            );
          } else {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText: 'Aapka truck abhi $response me hai.',
              enText: 'Your truck is currently at $response.',
            );
          }
          break;

      //GET MARKETPLACE SHIPMENTS
        case 'get_marketplace_shipment':
          final list =
          await ShipmentService.getAvailableMarketplaceShipments();
          final marketPlaceShipmentsIds =
          filterIdsByMap(list, "shipment_id");

          replyText = _localizeReply(
            langCode: parsed.language,
            hiText:
            '${list.length} marketplace shipments available hain.\nMarket Place Shipments: ${marketPlaceShipmentsIds.join(",")}',
            enText:
            'There are ${list.length} marketplace shipments available.\nShipment IDs: ${marketPlaceShipmentsIds.join(",")}',
          );
          break;


          // OPEN SCREEN
        case 'open_screen':
          final screen = params['screen']?.toString() ?? '';
          replyText = parsed.reply.isNotEmpty
              ? parsed.reply
              : _localizeReply(
            langCode: parsed.language,
            hiText: '$screen screen open kar raha hoon.',
            enText: 'Opening $screen screen.',
          );

          if (screen.isNotEmpty) {
            buttonLabel = _localizeReply(
              langCode: parsed.language,
              hiText: 'Go to $screen',
              enText: 'Go to $screen',
            );
            buttonScreen = screen;
          }
          break;
        default:
          // unknown: model may already have included a helpful reply
          if (replyText.isEmpty) {
            replyText = _localizeReply(
              langCode: parsed.language,
              hiText:
              'Mujhe ye request clear nahi hui, aap shipments, trucks ya drivers se related sawal puch sakte ho.',
              enText:
              'I could not clearly understand this request. You can ask about your shipments, trucks or drivers.',
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
            'truckOwnerId':params['truckOwnerId']
          },
          actionButtonLabel: buttonLabel,
          actionButtonScreen: buttonScreen,
        ),
      );

      // If action is open_screen, also auto-navigate (optional). We'll not auto-navigate to avoid surprising user.
      // If you want auto navigation uncomment next lines:
      // if (parsed.action == 'open_screen' && buttonScreen != null) {
      //   onNavigate(buttonScreen);
      // }
    } catch (e) {
      addBotMessage(
        ChatMessage(text: _localizeReply(
          langCode: 'en',
          hiText:
          'Mujhe samajhne me dikkat aa rahi hai, dubara simple shabdon me likho.',
          enText:
          'I am having trouble understanding this, please try again in simpler words.',
        )
          , isUser: false),
      );
      print(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

List<String> filterIdsByMap(List<Map<String, dynamic>> shipments, String key) {
  return shipments
      .map((map) => map[key].toString() ?? "")
      .where((id) => id.isNotEmpty)
      .toList();
}

//
// List<Map<String, dynamic>> filterShipments(
//     List<Map<String, dynamic>> shipments,
//     ) {
//   return shipments.map((map) {
//     return {
//       for (final key in shipment_map_keys)
//         if (map.containsKey(key)) key: map[key],
//     };
//   }).toList();
// }
//
//
//
// final shipment_map_keys = [
//   'shipment_id',
//   'shipper_id',
//   'pickup',
//   'drop',
//   'pickup_latitude',
//   'pickup_longitude',
//   'dropoff_latitude',
//   'dropoff_longitude',
//   'shipping_item',
//   'weight',
//   'unit',
//   'delivery_date',
//   'pickup_date',
//   'material_inside',
//   'truck_type',
//   'pickup_time',
//   'notes',
//   'booking_status',
//   'assigned_company',
// ];
