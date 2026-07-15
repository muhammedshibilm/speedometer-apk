import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'camera_model.dart';
import 'camera_repository.dart';
import 'overpass_service.dart';
import 'proximity_detector.dart';

/// ChangeNotifier that drives the camera-alert feature:
///  - manages the camera Hive box + Overpass sync
///  - listens to the GPS stream forwarded from [DrivePage]
///  - exposes [nearestCamera] for the in-app banner
///  - fires local notifications when a critical zone is entered
class CameraAlertProvider extends ChangeNotifier {
  // ── Settings (can be overridden from ThemeProvider / settings UI) ─────────
  double alertRadiusMeters = 800;
  double criticalRadiusMeters = 200;
  bool alertSoundEnabled = true;
  bool alertVibrationEnabled = true;
  bool speedCameraEnabled = true;
  bool avgSpeedCameraEnabled = true;

  // ── State ─────────────────────────────────────────────────────────────────
  ProximityResult? nearestCamera;
  bool get isAlertActive => nearestCamera != null;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  int _cachedCameraCount = 0;
  int get cachedCameraCount => _cachedCameraCount;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  String _syncStatus = 'Never synced';
  String get syncStatus => _syncStatus;

  // ── Private ───────────────────────────────────────────────────────────────
  final CameraRepository _repo = CameraRepository();
  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  // Debounce: don't re-notify for the same camera within 30 s
  String? _lastAlertedCameraId;
  DateTime? _lastAlertTime;

  Timer? _syncTimer;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _repo.init();
    _cachedCameraCount = _repo.count;
    _lastSyncTime = _repo.lastSyncTime;
    _syncStatus = _lastSyncTime == null
        ? 'Never synced'
        : 'Last synced: ${_formattedDate(_lastSyncTime!)}';

    await _initNotifications();

    // Periodic weekly sync timer
    _syncTimer = Timer.periodic(const Duration(days: 7), (_) async {
      // We don't know position here; caller should call syncForLocation()
      debugPrint('[CameraAlertProvider] Weekly sync timer fired');
    });

    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  // ── Notification setup ────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Triggers an Overpass sync for the user's current location.
  /// Safe to call from the drive screen whenever tracking starts.
  Future<void> syncForLocation(double lat, double lon,
      {bool force = false}) async {
    if (_isSyncing) return;

    // Skip if last sync was < 6 days ago (unless forced)
    if (!force && _lastSyncTime != null) {
      final age = DateTime.now().difference(_lastSyncTime!);
      if (age.inDays < 6) {
        debugPrint('[CameraAlertProvider] Sync skipped – data fresh');
        return;
      }
    }

    _isSyncing = true;
    _syncStatus = 'Syncing…';
    notifyListeners();

    try {
      final cameras =
          await OverpassService.fetchCamerasAround(lat: lat, lon: lon);
      if (cameras != null) {
        if (cameras.isNotEmpty) {
          await _repo.upsertAll(cameras);
          _cachedCameraCount = _repo.count;
          _lastSyncTime = DateTime.now();
          _syncStatus = 'Last synced: ${_formattedDate(_lastSyncTime!)}';
        } else {
          _syncStatus = 'Sync done – no cameras in area';
        }
      } else {
        _syncStatus = 'Sync failed – using cached data';
      }
    } catch (e) {
      _syncStatus = 'Sync failed – using cached data';
      debugPrint('[CameraAlertProvider] Sync error: $e');
    }

    _isSyncing = false;
    notifyListeners();
  }

  // ── GPS position update hook ──────────────────────────────────────────────

  /// Call this from [DrivePage._onPosition] on every GPS fix.
  void onPositionUpdate(Position position) {
    if (!isBoxOpen) return;
    final heading = position.heading; // degrees, 0=N

    // Filter camera types per settings
    final allowed = <String>[];
    if (speedCameraEnabled) allowed.add('speed_camera');
    if (avgSpeedCameraEnabled) allowed.add('average_speed');

    // Fetch nearby cameras from Hive (small radius for perf)
    final candidates = _repo
        .getCamerasNear(
          lat: position.latitude,
          lon: position.longitude,
          radiusMeters: alertRadiusMeters + 200, // small buffer
        )
        .where((c) => allowed.contains(c.type))
        .toList();

    final result = ProximityDetector.findNearest(
      userLat: position.latitude,
      userLon: position.longitude,
      headingDeg: heading,
      cameras: candidates,
      alertRadiusMeters: alertRadiusMeters,
      criticalRadiusMeters: criticalRadiusMeters,
    );

    final previous = nearestCamera;
    nearestCamera = result;

    // Fire notification only when entering critical zone + debounce
    if (result != null && result.isCritical) {
      _maybeSendNotification(result);
    }

    // Only notify UI when state meaningfully changes
    if (result?.camera.osmId != previous?.camera.osmId ||
        result?.isCritical != previous?.isCritical) {
      notifyListeners();
    }
  }

  void _maybeSendNotification(ProximityResult result) {
    final now = DateTime.now();
    final sameCamera = _lastAlertedCameraId == result.camera.osmId;
    final recentEnough = _lastAlertTime != null &&
        now.difference(_lastAlertTime!).inSeconds < 30;
    if (sameCamera && recentEnough) return;

    _lastAlertedCameraId = result.camera.osmId;
    _lastAlertTime = now;

    final typeLabel =
        result.camera.type == 'average_speed' ? 'Average Speed' : 'Speed';
    final speedLabel = result.camera.maxspeed != null
        ? ' (${result.camera.maxspeed} km/h limit)'
        : '';

    _notifPlugin.show(
      1001, // fixed id – replaces previous camera alert
      '🚨 $typeLabel Camera Ahead',
      '${result.distanceText} away$speedLabel',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'camera_alerts',
          'Camera Alerts',
          channelDescription: 'Speed camera proximity warnings',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get isBoxOpen => Hive.isBoxOpen(CameraRepository.boxName);

  String _formattedDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
