import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logistics_toolkit/features/Report%20Analysis/report_chart.dart';
import 'package:logistics_toolkit/features/driver_documents/driver_documents_page.dart';
import 'package:logistics_toolkit/features/laod_assignment/presentation/screen/allLoads.dart';
import 'package:logistics_toolkit/features/mytruck/mytrucks.dart';
import 'package:logistics_toolkit/features/notifications/presentation/screen/notification_center.dart';
import 'package:logistics_toolkit/features/sos/company_driver_sos.dart';
import 'package:logistics_toolkit/features/tracking/tracktruckspage.dart';
import 'package:logistics_toolkit/features/trips/myTrips.dart';
import 'package:logistics_toolkit/features/trips/myTrips_history.dart';
import '../features/bilty/shipment_selection_page.dart';
import '../features/chat/agent_chat_list_page.dart';
import '../features/complains/mycomplain.dart';
import '../features/driver_status/driver_status_changer.dart';
import '../features/laod_assignment/presentation/cubits/shipment_cubit.dart';
import '../features/laod_assignment/presentation/screen/load_assignment_screen.dart';
import '../features/mydrivers/mydriver.dart';
import '../features/ratings/presentation/screen/trip_ratings.dart';
import '../features/settings/presentation/screen/settings_page.dart';
import '../features/shipment/shipper_form_page.dart';
import '../features/tracking/shared_shipments_page.dart';
import '../features/truck_documents/truck_documents_page.dart';

Future<void> openScreen(String? screen, context, Map params) async {
  switch (screen) {
    case "my_shipments":
      Navigator.push(context, MaterialPageRoute(builder: (_) => MyShipments()));
      break;

    case "all_loads":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => allLoadsPage()),
      );
      break;

    case "shared_shipments":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SharedShipmentsPage()),
      );
      break;

    case "track_trucks":
      final truckOwnerId = params['truckOwnerId'];
      print('truckOwnerId in the openscreen:$truckOwnerId');

      if (truckOwnerId == null) {
        print("TRACK ERROR: truckOwnerId not found");
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackTrucksPage(truckOwnerId: truckOwnerId),
        ),
      );
      break;

    case "my_trucks":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => Mytrucks()),
      );
      break;

    case "my_drivers":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MyDriverPage()),
      );
      break;

    case "truck_documents":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TruckDocumentsPage()),
      );
      break;

    case "driver_documents":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DriverDocumentsPage()),
      );
      break;

    case "my_trips":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MyTripsHistory()),
      );
      break;

    case "my_chats":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AgentChatListPage()),
      );
      break;

    case "bilty":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ShipmentSelectionPage()),
      );
      break;

    case "ratings":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TripRatingsPage()),
      );
      break;

    case "complaints":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ComplaintHistoryPage()),
      );
      break;

    case "setting":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SettingsPage()),
      );
      break;

    case "notification":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const NotificationCenterPage()),
      );
      break;

    case "report_and_analysis":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReportAnalysisPage()),
      );
      break;

    case "invoice":
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MyTripsHistory()),
      );
      break;

    case "create_shipments":
      print('createshipments call ho gya hai bro');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ShipperFormPage()),
      );
      break;

    case "find_shipments":
      print("findShipment call ho gya hai bro ");

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider(
            create: (context) => ShipmentCubit(),
            child: const LoadAssignmentScreen(),
          ),
        ),
      );
      break;

    case "shipments":
      final driverId = params['driverId'];
      print('driverrid:$driverId');
      if (driverId == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DriverStatusChanger(driverId: driverId),
        ),
      );
      break;

    case "emergency":
      final agentId = params['agentId'];
      if (agentId == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CompanyDriverEmergencyScreen(agentId: agentId),
        ),
      );
      break;
  }
}
