import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'camera_model.dart';

/// Fetches speed/traffic/police camera nodes from the Overpass API.
///
/// Query covers:
///  - highway=speed_camera           (fixed speed cameras)
///  - enforcement=average_speed      (section cameras / SPECS)
///  - enforcement=traffic_signals    (red-light cameras)
///  - highway=traffic_signals        (traffic signals with camera)
///  - man_made=surveillance + surveillance:type=ANPR (ANPR / police cameras)
///  - enforcement=police             (police checkpoint cameras)
class OverpassService {
  static const String _baseUrl = 'https://overpass-api.de/api/interpreter';

  /// Fallback mirror – used if the primary endpoint is down.
  static const String _mirrorUrl =
      'https://overpass.kumi.systems/api/interpreter';

  /// Builds an Overpass QL query for a bounding box.
  static String _buildQuery(
    double south,
    double west,
    double north,
    double east,
  ) {
    final bbox = '$south,$west,$north,$east';
    return '''
[out:json][timeout:40];
(
  node["highway"="speed_camera"]($bbox);
  node["enforcement"="average_speed"]($bbox);
  node["enforcement"="traffic_signals"]($bbox);
  node["enforcement"="police"]($bbox);
  node["man_made"="surveillance"]["surveillance:type"="ANPR"]($bbox);
  node["camera:type"="speed"]($bbox);
);
out body;
''';
  }

  /// Fetches cameras for a bounding box (±[radiusDeg] around a centre point).
  ///
  /// Returns null on network failure so the caller can fall back to cache.
  static Future<List<CameraModel>?> fetchCamerasAround({
    required double lat,
    required double lon,
    double radiusDeg = 0.5, // ~55 km — smaller to avoid Overpass timeout
  }) async {
    final south = lat - radiusDeg;
    final north = lat + radiusDeg;
    final west = lon - radiusDeg;
    final east = lon + radiusDeg;

    final query = _buildQuery(south, west, north, east);

    try {
      final response =
          await _post(_baseUrl, query).timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        return _parse(response.body);
      }
      // Try mirror on 5xx
      if (response.statusCode >= 500) {
        final mirror = await _post(_mirrorUrl, query)
            .timeout(const Duration(seconds: 45));
        if (mirror.statusCode == 200) {
          return _parse(mirror.body);
        }
      }
      debugPrint('[OverpassService] HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[OverpassService] Error: $e');
      return null;
    }
  }

  static Future<http.Response> _post(String url, String body) {
    return http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'data': body},
    );
  }

  /// Maps OSM tags → [CameraModel.type] string.
  static String _resolveType(Map<String, dynamic> tags) {
    final enforcement = tags['enforcement']?.toString() ?? '';
    final highway = tags['highway']?.toString() ?? '';
    final surveillance = tags['surveillance:type']?.toString() ?? '';
    final camType = tags['camera:type']?.toString() ?? '';

    if (enforcement == 'average_speed') return CameraType.averageSpeed;
    if (enforcement == 'traffic_signals') return CameraType.redLight;
    if (enforcement == 'police') return CameraType.police;
    if (highway == 'speed_camera' || camType == 'speed') {
      return CameraType.speedCamera;
    }
    if (surveillance == 'ANPR') return CameraType.anpr;
    return CameraType.speedCamera; // fallback
  }

  /// Parses the Overpass JSON response into [CameraModel] list.
  static List<CameraModel> _parse(String jsonBody) {
    try {
      final data = jsonDecode(jsonBody) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];
      final now = DateTime.now();
      final cameras = <CameraModel>[];

      for (final el in elements) {
        try {
          final tags = el['tags'] as Map<String, dynamic>? ?? {};
          final id = el['id']?.toString() ?? '';
          final lat = (el['lat'] as num?)?.toDouble();
          final lon = (el['lon'] as num?)?.toDouble();

          if (id.isEmpty || lat == null || lon == null) continue;

          final type = _resolveType(tags);

          // Parse maxspeed (may be "50", "50 mph", "national", etc.)
          int? maxspeed;
          final rawMax = tags['maxspeed']?.toString() ??
              tags['maxspeed:enforcement']?.toString() ??
              '';
          final parsed = int.tryParse(rawMax.split(' ').first);
          if (parsed != null && parsed > 0 && parsed < 300) {
            maxspeed = parsed;
          }

          cameras.add(CameraModel(
            osmId: id,
            lat: lat,
            lon: lon,
            type: type,
            maxspeed: maxspeed,
            lastUpdated: now,
          ));
        } catch (_) {
          // Skip malformed elements
        }
      }
      debugPrint('[OverpassService] Parsed ${cameras.length} cameras');
      return cameras;
    } catch (e) {
      debugPrint('[OverpassService] Parse error: $e');
      throw FormatException('Failed to parse Overpass response: $e');
    }
  }
}

/// Canonical type strings used across the camera feature.
class CameraType {
  static const speedCamera = 'speed_camera';
  static const averageSpeed = 'average_speed';
  static const redLight = 'red_light';
  static const police = 'police';
  static const anpr = 'anpr';

  static const allTypes = [speedCamera, averageSpeed, redLight, police, anpr];
}
