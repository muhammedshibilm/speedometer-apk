import 'package:hive/hive.dart';

part 'camera_model.g.dart';

/// OSM speed/traffic camera node stored locally in Hive.
@HiveType(typeId: 1)
class CameraModel extends HiveObject {
  /// OSM node id – used as dedup key.
  @HiveField(0)
  String osmId;

  @HiveField(1)
  double lat;

  @HiveField(2)
  double lon;

  /// 'speed_camera' or 'average_speed'
  @HiveField(3)
  String type;

  /// Posted speed limit in km/h. null = unknown.
  @HiveField(4)
  int? maxspeed;

  @HiveField(5)
  String source;

  @HiveField(6)
  DateTime lastUpdated;

  CameraModel({
    required this.osmId,
    required this.lat,
    required this.lon,
    required this.type,
    this.maxspeed,
    this.source = 'overpass',
    required this.lastUpdated,
  });

  @override
  String toString() =>
      'Camera($osmId, $type, ${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}, ${maxspeed ?? "?"}km/h)';
}
