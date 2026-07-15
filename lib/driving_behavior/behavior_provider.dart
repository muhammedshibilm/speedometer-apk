import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'behavior_event_model.dart';
import 'trip_score.dart';

/// Detects harsh driving events using GPS delta-speed and sensor data.
///
/// Usage:
///   1. Call [startTrip] when tracking begins.
///   2. Feed GPS speeds via [onSpeedUpdate] (km/h) each GPS tick.
///   3. Call [stopTrip] to get a [TripBehaviorSummary] and persist events.
class BehaviorProvider extends ChangeNotifier {
  // ── Thresholds (configurable) ─────────────────────────────────────────────
  /// m/s² – GPS-derived deceleration that qualifies as harsh braking.
  double harshBrakeThreshold = -1.5;

  /// m/s² – GPS-derived acceleration that qualifies as harsh accel.
  double harshAccelThreshold = 1.5;

  /// rad/s – gyroscope Z-axis spike for sharp corners.
  double cornerThreshold = 0.6;

  // ── Live state ────────────────────────────────────────────────────────────
  int harshBrakeCount = 0;
  int harshAccelCount = 0;
  int sharpCornerCount = 0;
  int secondsOverLimit = 0;
  int totalSeconds = 0;

  bool _tripActive = false;
  bool get tripActive => _tripActive;

  // ── Private ───────────────────────────────────────────────────────────────
  double? _lastSpeedMs; // m/s
  DateTime? _lastSpeedTime;

  // Debounce: ignore repeated events within a cooldown window
  DateTime? _lastBrakeTime;
  DateTime? _lastAccelTime;
  DateTime? _lastCornerTime;

  static const Duration _eventCooldown = Duration(seconds: 3);

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;

  final List<BehaviorEventModel> _sessionEvents = [];
  int _currentTripKey = -1;

  // Speed limit for "over limit" tracking (km/h). Updated from CameraAlertProvider.
  double? _currentSpeedLimitKmh;

  // ── API ───────────────────────────────────────────────────────────────────

  void startTrip(int tripKey) {
    _currentTripKey = tripKey;
    _tripActive = true;
    harshBrakeCount = 0;
    harshAccelCount = 0;
    sharpCornerCount = 0;
    secondsOverLimit = 0;
    totalSeconds = 0;
    _sessionEvents.clear();
    _lastSpeedMs = null;
    _lastSpeedTime = null;
    _startGyroscope();
    notifyListeners();
  }

  /// [speedKmh] – current GPS speed in km/h.
  /// [speedLimitKmh] – posted limit from camera data (or null = use default).
  void onSpeedUpdate(double speedKmh, {double? speedLimitKmh}) {
    if (!_tripActive) return;

    totalSeconds++;

    final speedMs = speedKmh / 3.6;
    final now = DateTime.now();
    _currentSpeedLimitKmh = speedLimitKmh;

    // ── Harsh braking / acceleration from GPS delta ────────────────────────
    if (_lastSpeedMs != null && _lastSpeedTime != null) {
      final dt = now.difference(_lastSpeedTime!).inMilliseconds / 1000.0;
      if (dt > 0 && dt < 3.0) {
        // only valid short intervals
        final accel = (speedMs - _lastSpeedMs!) / dt;

        if (accel < harshBrakeThreshold) {
          if (_canFire(_lastBrakeTime)) {
            harshBrakeCount++;
            _lastBrakeTime = now;
            _recordEvent('brake', accel.abs());
            notifyListeners();
          }
        } else if (accel > harshAccelThreshold) {
          if (_canFire(_lastAccelTime)) {
            harshAccelCount++;
            _lastAccelTime = now;
            _recordEvent('accel', accel);
            notifyListeners();
          }
        }
      }
    }

    _lastSpeedMs = speedMs;
    _lastSpeedTime = now;

    // ── Speeding check ────────────────────────────────────────────────────
    final limit = speedLimitKmh ?? _currentSpeedLimitKmh ?? 120.0;
    if (speedKmh > limit) {
      secondsOverLimit++;
    }
  }

  TripBehaviorSummary stopTrip() {
    _tripActive = false;
    _gyroSub?.cancel();
    _gyroSub = null;
    _accelSub?.cancel();
    _accelSub = null;

    final pct = totalSeconds > 0
        ? (secondsOverLimit / totalSeconds * 100).clamp(0, 100).toDouble()
        : 0.0;

    final summary = TripBehaviorSummary(
      harshBrakeCount: harshBrakeCount,
      harshAccelCount: harshAccelCount,
      sharpCornerCount: sharpCornerCount,
      timeOverLimitPct: pct,
      events: List.unmodifiable(_sessionEvents),
    );

    notifyListeners();
    return summary;
  }

  Future<void> persistEvents(Box<BehaviorEventModel> box) async {
    for (final e in _sessionEvents) {
      await box.add(e);
    }
  }

  // ── Gyroscope ────────────────────────────────────────────────────────────

  void _startGyroscope() {
    _gyroSub?.cancel();
    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((event) {
      if (!_tripActive) return;
      // Z-axis represents yaw (rotation around vertical) = cornering
      final zAbs = event.z.abs();
      if (zAbs > cornerThreshold) {
        if (_canFire(_lastCornerTime)) {
          sharpCornerCount++;
          _lastCornerTime = DateTime.now();
          _recordEvent('corner', zAbs);
          notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint('[BehaviorProvider] Gyro error: $e');
    });

    _accelSub?.cancel();
    _accelSub = userAccelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((event) {
      if (!_tripActive) return;
      // Magnitude of linear acceleration
      final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      // If magnitude is high, it's a harsh event
      if (mag > 2.5) {
        // Use the sign of Y or Z to guess accel/brake
        // Usually, braking causes a strong negative Y or Z depending on phone orientation.
        // But since we can't be sure, we can also use the recent GPS speed delta if available
        // For a more immediate response without orientation, we assume:
        // Strong positive Z is often braking if phone is flat, but if phone is upright, Y is vertical.
        // Actually, let's just rely on the GPS speed delta which we already lowered to 2.0.
        // We can just use the accelerometer as a backup trigger if we want, or just stick to GPS.
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _canFire(DateTime? last) {
    if (last == null) return true;
    return DateTime.now().difference(last) > _eventCooldown;
  }

  void _recordEvent(String type, double severity) {
    _sessionEvents.add(BehaviorEventModel(
      tripKey: _currentTripKey,
      eventType: type,
      timestamp: DateTime.now(),
      severity: severity,
    ));
  }
}

/// Immutable summary produced by [BehaviorProvider.stopTrip].
class TripBehaviorSummary {
  final int harshBrakeCount;
  final int harshAccelCount;
  final int sharpCornerCount;
  final double timeOverLimitPct;
  final List<BehaviorEventModel> events;

  const TripBehaviorSummary({
    required this.harshBrakeCount,
    required this.harshAccelCount,
    required this.sharpCornerCount,
    required this.timeOverLimitPct,
    required this.events,
  });

  int get driveScore => TripScore.calculate(
        harshBrakeCount: harshBrakeCount,
        harshAccelCount: harshAccelCount,
        sharpCornerCount: sharpCornerCount,
        timeOverLimitPct: timeOverLimitPct,
      );
}
