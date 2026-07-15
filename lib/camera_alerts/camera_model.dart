import 'package:hive/hive.dart';

part 'camera_model.g.dart';

/// OSM speed/traffic/police camera node stored locally in Hive.
@HiveType(typeId: 1)
class CameraModel extends HiveObject {
  /// OSM node id – used as dedup key.
  @HiveField(0)
  String osmId;

  @HiveField(1)
  double lat;

  @HiveField(2)
  double lon;

  /// One of: 'speed_camera', 'average_speed', 'red_light', 'police', 'anpr'
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

  /// Human-readable label for UI display.
  String get typeLabel {
    switch (type) {
      case 'average_speed':
        return 'Average Speed Camera';
      case 'red_light':
        return 'Red-Light Camera';
      case 'police':
        return 'Police Camera';
      case 'anpr':
        return 'ANPR / Police Camera';
      case 'speed_camera':
      default:
        return 'Speed Camera';
    }
  }

  @override
  String toString() =>
      'Camera($osmId, $type, ${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}, ${maxspeed ?? "?"}km/h)';
}
