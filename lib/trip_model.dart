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

  @HiveField(5)
  String name;

  @HiveField(6)
  List<double> speedReadings;

  @HiveField(7)
  List<double> latitudes;

  @HiveField(8)
  List<double> longitudes;

  // ── New behavior fields (9–13) – default values keep old trips readable ──

  @HiveField(9)
  int harshBrakeCount;

  @HiveField(10)
  int harshAccelCount;

  @HiveField(11)
  int sharpCornerCount;

  /// % of trip time spent above the speed limit (0–100).
  @HiveField(12)
  double timeOverLimitPct;

  /// Drive score 0–100 (computed at end of trip).
  @HiveField(13)
  int driveScore;

  TripModel({
    required this.startTime,
    required this.durationSeconds,
    required this.distanceKm,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.name,
    this.speedReadings = const [],
    this.latitudes = const [],
    this.longitudes = const [],
    // New optional params – default to zero so old Hive data keeps working
    this.harshBrakeCount = 0,
    this.harshAccelCount = 0,
    this.sharpCornerCount = 0,
    this.timeOverLimitPct = 0.0,
    this.driveScore = 100,
  });
}
