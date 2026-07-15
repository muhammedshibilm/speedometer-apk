import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'camera_model.dart';

/// Fetches speed/traffic camera nodes from the Overpass API and parses them
/// into [CameraModel] instances.
///
/// Query covers:
///  - highway=speed_camera  (fixed enforcement cameras)
///  - enforcement=average_speed  (section cameras / SPECS)
class OverpassService {
  static const String _baseUrl = 'https://overpass-api.de/api/interpreter';

  /// Fallback mirror – used if the primary endpoint is down.
  static const String _mirrorUrl = 'https://overpass.kumi.systems/api/interpreter';

  /// Builds an Overpass QL query for a bounding box.
  /// [south], [west], [north], [east] are WGS-84 decimal degrees.
  static String _buildQuery(
    double south,
    double west,
    double north,
    double east,
  ) {
    final bbox = '$south,$west,$north,$east';
    return '''
[out:json][timeout:30];
(
  node["highway"="speed_camera"]($bbox);
  node["enforcement"="average_speed"]($bbox);
);
out body;
''';
  }

  /// Fetches cameras for a bounding box (±radiusDeg around a centre point).
  ///
  /// Returns null on network failure or parsing error so the caller
  /// can fall back to cached data gracefully.
  static Future<List<CameraModel>?> fetchCamerasAround({
    required double lat,
    required double lon,
    double radiusDeg = 1.0, // ~111 km per degree
  }) async {
    final south = lat - radiusDeg;
    final north = lat + radiusDeg;
    final west = lon - radiusDeg;
    final east = lon + radiusDeg;

    final query = _buildQuery(south, west, north, east);

    try {
      final response = await _post(_baseUrl, query)
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return _parse(response.body);
      }
      // Try mirror on 5xx
      if (response.statusCode >= 500) {
        final mirror = await _post(_mirrorUrl, query)
            .timeout(const Duration(seconds: 35));
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

  /// Parses the Overpass JSON response into [CameraModel] list.
  /// Unknown / malformed nodes are silently skipped.
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

          // Determine camera type
          String type = 'speed_camera';
          if (tags['enforcement'] == 'average_speed') {
            type = 'average_speed';
          }

          // Parse maxspeed (may be "50", "50 mph", "national", etc.)
          int? maxspeed;
          final rawMax = tags['maxspeed']?.toString() ?? '';
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
