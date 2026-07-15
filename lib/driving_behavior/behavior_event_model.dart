import 'package:hive/hive.dart';

part 'behavior_event_model.g.dart';

/// A single harsh driving event recorded during a trip.
@HiveType(typeId: 2)
class BehaviorEventModel extends HiveObject {
  /// Key of the parent TripModel.
  @HiveField(0)
  int tripKey;

  /// 'brake' | 'accel' | 'corner' | 'speeding'
  @HiveField(1)
  String eventType;

  @HiveField(2)
  DateTime timestamp;

  /// Magnitude of the reading that triggered the event.
  @HiveField(3)
  double severity;

  BehaviorEventModel({
    required this.tripKey,
    required this.eventType,
    required this.timestamp,
    required this.severity,
  });
}
