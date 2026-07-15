import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'camera_model.dart';

/// CRUD wrapper around the Hive `cameras` box.
///
/// All methods are safe to call even before the box is open (they short-circuit
/// to empty results / no-ops).
class CameraRepository {
  static const String boxName = 'cameras';

  Box<CameraModel>? _box;

  Box<CameraModel>? get _safeBox {
    if (_box == null || !_box!.isOpen) {
      if (Hive.isBoxOpen(boxName)) {
        _box = Hive.box<CameraModel>(boxName);
      }
    }
    return _box;
  }

  /// Opens (or reuses) the Hive box.
  Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      _box = await Hive.openBox<CameraModel>(boxName);
    } else {
      _box = Hive.box<CameraModel>(boxName);
    }
  }

  /// Returns all cameras within [radiusMeters] of [lat],[lon].
  List<CameraModel> getCamerasNear({
    required double lat,
    required double lon,
    double radiusMeters = 5000,
  }) {
    final box = _safeBox;
    if (box == null) return [];
    return box.values.where((c) {
      final d = _haversineMeters(lat, lon, c.lat, c.lon);
      return d <= radiusMeters;
    }).toList();
  }

  /// Upserts [cameras] into Hive, deduplicating by OSM id.
  Future<int> upsertAll(List<CameraModel> cameras) async {
    final box = _safeBox;
    if (box == null) return 0;

    // Build an index of existing entries keyed by osmId
    final existing = <String, dynamic>{};
    for (final key in box.keys) {
      final c = box.get(key);
      if (c != null) existing[c.osmId] = key;
    }

    int added = 0;
    for (final camera in cameras) {
      if (existing.containsKey(camera.osmId)) {
        // Update in-place
        await box.put(existing[camera.osmId], camera);
      } else {
        await box.add(camera);
        added++;
      }
    }
    debugPrint('[CameraRepo] Upserted ${cameras.length} cameras ($added new)');
    return cameras.length;
  }

  /// Total camera count stored locally.
  int get count => _safeBox?.length ?? 0;

  /// Timestamp of the most recent sync, or null if never synced.
  DateTime? get lastSyncTime {
    final box = _safeBox;
    if (box == null || box.isEmpty) return null;
    // Find the max lastUpdated
    return box.values
        .map((c) => c.lastUpdated)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Simple haversine distance in metres.
  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = _sin2(dLat / 2) +
        _cos(_toRad(lat1)) * _cos(_toRad(lat2)) * _sin2(dLon / 2);
    final c = 2 * _asin(_sqrt(a));
    return r * c;
  }

  static double _toRad(double d) => d * 3.141592653589793 / 180;
  static double _sin2(double x) {
    final s = _sin(x);
    return s * s;
  }

  static double _sin(double x) {
    // dart:math is not imported to keep this file dependency-free;
    // use inline approximation via dart's built-in
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }

  static double _cos(double x) =>
      1 - (x * x) / 2 + (x * x * x * x) / 24;

  static double _asin(double x) => x + (x * x * x) / 6;

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x;
    for (int i = 0; i < 20; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }
}
