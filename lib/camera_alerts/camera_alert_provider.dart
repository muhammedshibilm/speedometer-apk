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
  // ── Settings ─────────────────────────────────────────────────────────────
  double alertRadiusMeters = 800;
  double criticalRadiusMeters = 200;
  bool alertSoundEnabled = true;
  bool alertVibrationEnabled = true;

  // Per-type toggles (all on by default)
  bool speedCameraEnabled = true;
  bool avgSpeedCameraEnabled = true;
  bool redLightCameraEnabled = true;
  bool policeCameraEnabled = true;
  bool anprEnabled = true;

  // ── State ──────────────────────────────────────────────────────────────────
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

  // ── Private ────────────────────────────────────────────────────────────────
  final CameraRepository _repo = CameraRepository();
  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  // Debounce: don't re-notify for the same camera within 30 s
  String? _lastAlertedCameraId;
  DateTime? _lastAlertTime;

  Timer? _syncTimer;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _repo.init();
    _cachedCameraCount = _repo.count;
    _lastSyncTime = _repo.lastSyncTime;
    _syncStatus = _lastSyncTime == null
        ? 'Never synced'
        : 'Last synced: ${_formattedDate(_lastSyncTime!)}';

    await _initNotifications();
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  // ── Notification setup ─────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  // ── Sync ───────────────────────────────────────────────────────────────────

  /// Triggers an Overpass sync for the user's current location.
  ///
  /// By default skips if last sync was < 6 days ago and returned cameras.
  /// Pass [force] = true to always re-fetch (e.g. from settings).
  Future<void> syncForLocation(double lat, double lon,
      {bool force = false}) async {
    if (_isSyncing) return;

    // Skip if last sync was recent AND we already have cameras stored
    if (!force && _lastSyncTime != null) {
      final age = DateTime.now().difference(_lastSyncTime!);
      if (age.inDays < 6 && _cachedCameraCount > 0) {
        debugPrint('[CameraAlertProvider] Sync skipped – data fresh '
            '($_cachedCameraCount cameras)');
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
          _syncStatus =
              'Synced: $_cachedCameraCount cameras (${_formattedDate(_lastSyncTime!)})';
        } else {
          _syncStatus = 'Sync done – no cameras found in this area';
          _lastSyncTime = DateTime.now(); // mark as synced so we don't retry immediately
        }
      } else {
        _syncStatus = 'Sync failed – check connection. Using cached data.';
      }
    } catch (e) {
      _syncStatus = 'Sync error – using cached data';
      debugPrint('[CameraAlertProvider] Sync error: $e');
    }

    _isSyncing = false;
    notifyListeners();
  }

  // ── GPS position update hook ───────────────────────────────────────────────

  /// Call this from [DrivePage._onPosition] on every GPS fix.
  void onPositionUpdate(Position position) {
    if (!isBoxOpen) return;

    // Build the list of allowed camera types from toggle settings
    final allowed = <String>[];
    if (speedCameraEnabled) allowed.add(CameraType.speedCamera);
    if (avgSpeedCameraEnabled) allowed.add(CameraType.averageSpeed);
    if (redLightCameraEnabled) allowed.add(CameraType.redLight);
    if (policeCameraEnabled) allowed.add(CameraType.police);
    if (anprEnabled) allowed.add(CameraType.anpr);

    if (allowed.isEmpty) {
      if (nearestCamera != null) {
        nearestCamera = null;
        notifyListeners();
      }
      return;
    }

    final candidates = _repo
        .getCamerasNear(
          lat: position.latitude,
          lon: position.longitude,
          radiusMeters: alertRadiusMeters + 300,
        )
        .where((c) => allowed.contains(c.type))
        .toList();

    // Only apply heading filter when actually moving (speed > 3 km/h)
    // to avoid false-negatives when stationary at 0 heading.
    final double? headingOrNull =
        position.speed > 0.8 ? position.heading : null;

    final result = ProximityDetector.findNearest(
      userLat: position.latitude,
      userLon: position.longitude,
      headingDeg: headingOrNull,
      cameras: candidates,
      alertRadiusMeters: alertRadiusMeters,
      criticalRadiusMeters: criticalRadiusMeters,
    );

    final previous = nearestCamera;
    nearestCamera = result;

    // Fire notification only when entering critical zone
    if (result != null && result.isCritical) {
      _maybeSendNotification(result);
    }

    // Only rebuild UI when state meaningfully changes
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

    final label = result.camera.typeLabel;
    final speedLabel = result.camera.maxspeed != null
        ? ' (${result.camera.maxspeed} km/h limit)'
        : '';

    // Choose notification icon/emoji per type
    final emoji = _emojiFor(result.camera.type);

    _notifPlugin.show(
      1001, // fixed id – replaces previous alert
      '$emoji $label Ahead',
      '${result.distanceText} away$speedLabel',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'camera_alerts',
          'Camera Alerts',
          channelDescription: 'Speed & traffic camera proximity warnings',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  String _emojiFor(String type) {
    switch (type) {
      case CameraType.police:
      case CameraType.anpr:
        return '🚔';
      case CameraType.redLight:
        return '🚦';
      case CameraType.averageSpeed:
        return '📷';
      default:
        return '🚨';
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get isBoxOpen => Hive.isBoxOpen(CameraRepository.boxName);

  String _formattedDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
