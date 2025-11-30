import 'package:equatable/equatable.dart';

enum ShipmentStatus { initial, loading, success, failure }

class ShipmentState extends Equatable {
  const ShipmentState({
    this.status = ShipmentStatus.initial,
    this.shipments = const <Map<String, dynamic>>[],
    this.errorMessage,
  });

  final ShipmentStatus status;
  final List<Map<String, dynamic>> shipments;
  final String? errorMessage;

  ShipmentState copyWith({
    ShipmentStatus? status,
    List<Map<String, dynamic>>? shipments,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ShipmentState(
      status: status ?? this.status,
      shipments: shipments ?? this.shipments,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, shipments, errorMessage];
}
