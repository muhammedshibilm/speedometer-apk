import 'package:hive/hive.dart';

part 'trip_model.g.dart';

@HiveType(typeId: 0)
class TripModel extends HiveObject {
  @HiveField(0)
  DateTime startTime;

  @HiveField(1)
  int durationSeconds;

  @HiveField(2)
  double distanceKm;

  @HiveField(3)
  double avgSpeed;

  @HiveField(4)
  double maxSpeed;

  TripModel({
    required this.startTime,
    required this.durationSeconds,
    required this.distanceKm,
    required this.avgSpeed,
    required this.maxSpeed,
  });
}
