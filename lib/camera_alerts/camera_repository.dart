import 'dart:math' as math;
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
      final d = haversineMeters(lat, lon, c.lat, c.lon);
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

  /// Clears all stored cameras (useful to force a fresh sync).
  Future<void> clearAll() async {
    await _safeBox?.clear();
  }

  /// Total camera count stored locally.
  int get count => _safeBox?.length ?? 0;

  /// Timestamp of the most recent sync, or null if never synced.
  DateTime? get lastSyncTime {
    final box = _safeBox;
    if (box == null || box.isEmpty) return null;
    return box.values
        .map((c) => c.lastUpdated)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Accurate haversine distance in metres using dart:math.
  static double haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
