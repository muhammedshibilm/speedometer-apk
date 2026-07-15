import 'dart:math';
import 'camera_model.dart';

/// Result of a proximity check – returned by [ProximityDetector.findNearest].
class ProximityResult {
  final CameraModel camera;

  /// Straight-line distance to camera in metres.
  final double distanceMeters;

  /// True when [distanceMeters] <= criticalDistanceMeters (default 200 m).
  final bool isCritical;

  const ProximityResult({
    required this.camera,
    required this.distanceMeters,
    required this.isCritical,
  });

  String get distanceText {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

/// Proximity detection: haversine distance + optional ahead-of-travel filter.
class ProximityDetector {
  /// Field-of-view half-angle: camera must be within this of the heading.
  static const double _halfFovDeg = 70.0;

  /// Finds the nearest camera ahead of the user (or all-around if stationary).
  ///
  /// [headingDeg] – pass null when the user is stationary (speed < threshold)
  ///   to disable the directional filter and alert regardless of heading.
  static ProximityResult? findNearest({
    required double userLat,
    required double userLon,
    required double? headingDeg, // nullable = no direction filter
    required List<CameraModel> cameras,
    double alertRadiusMeters = 800,
    double criticalRadiusMeters = 200,
  }) {
    ProximityResult? best;

    for (final camera in cameras) {
      final dist = haversineMeters(userLat, userLon, camera.lat, camera.lon);
      if (dist > alertRadiusMeters) continue;

      // Only apply directional filter when heading is known (user is moving)
      if (headingDeg != null) {
        final bearing = bearingDeg(userLat, userLon, camera.lat, camera.lon);
        if (!isAhead(headingDeg, bearing, halfFovDeg: _halfFovDeg)) continue;
      }

      if (best == null || dist < best.distanceMeters) {
        best = ProximityResult(
          camera: camera,
          distanceMeters: dist,
          isCritical: dist <= criticalRadiusMeters,
        );
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Pure math helpers
  // ---------------------------------------------------------------------------

  /// Haversine great-circle distance in metres.
  static double haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = pow(sin(dLat / 2), 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dLon / 2), 2);
    return 2 * r * asin(sqrt(a.clamp(0, 1)));
  }

  /// Forward azimuth (bearing) in degrees [0, 360) from point 1 → point 2.
  static double bearingDeg(
      double lat1, double lon1, double lat2, double lon2) {
    final dLon = _rad(lon2 - lon1);
    final rLat1 = _rad(lat1);
    final rLat2 = _rad(lat2);
    final y = sin(dLon) * cos(rLat2);
    final x = cos(rLat1) * sin(rLat2) - sin(rLat1) * cos(rLat2) * cos(dLon);
    return (_deg(atan2(y, x)) + 360) % 360;
  }

  /// Returns true if [cameraBearing] is within [halfFovDeg] of [heading].
  static bool isAhead(double heading, double cameraBearing,
      {double halfFovDeg = _halfFovDeg}) {
    double diff = (cameraBearing - heading + 360) % 360;
    if (diff > 180) diff = 360 - diff; // normalise to [0, 180]
    return diff <= halfFovDeg;
  }

  static double _rad(double deg) => deg * pi / 180;
  static double _deg(double rad) => rad * 180 / pi;
}
