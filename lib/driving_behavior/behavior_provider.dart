import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'behavior_event_model.dart';
import 'trip_score.dart';

/// Detects harsh driving events using a single-source-per-signal architecture.
/// - Speeding: GPS (filtered speed)
/// - Braking/Accel: Accelerometer (magnitude + GPS trend for direction)
/// - Cornering: Gyroscope (Z-axis + speed gated)
class BehaviorProvider extends ChangeNotifier {
  // ── Thresholds (configurable) ─────────────────────────────────────────────
  /// Accelerometer magnitude threshold for harsh events (m/s²).
  double harshAccelBrakeMagThreshold = 2.5;

  /// Gyroscope Z-axis threshold for sharp corners (rad/s).
  double cornerThreshold = 0.6;

  /// Minimum speed required to register a corner (km/h) to avoid parking lot false positives.
  double minCornerSpeedKmh = 10.0;

  // ── Live state ────────────────────────────────────────────────────────────
  int harshBrakeCount = 0;
  int harshAccelCount = 0;
  int sharpCornerCount = 0;
  
  double _timeOverLimitSeconds = 0.0;
  double _totalTripSeconds = 0.0;

  bool _tripActive = false;
  bool get tripActive => _tripActive;

  // ── Private ───────────────────────────────────────────────────────────────
  double _currentSpeedKmh = 0.0;
  double _currentGpsAccel = 0.0; // derived from GPS to give direction to accelerometer
  DateTime? _lastSpeedTime;

  // Debounce: ignore repeated events within a cooldown window
  DateTime? _lastBrakeTime;
  DateTime? _lastAccelTime;
  DateTime? _lastCornerTime;

  static const Duration _eventCooldown = Duration(seconds: 2);

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;

  final List<BehaviorEventModel> _sessionEvents = [];
  int _currentTripKey = -1;

  double? _currentSpeedLimitKmh;

  // ── API ───────────────────────────────────────────────────────────────────

  void startTrip(int tripKey) {
    _currentTripKey = tripKey;
    _tripActive = true;
    harshBrakeCount = 0;
    harshAccelCount = 0;
    sharpCornerCount = 0;
    _timeOverLimitSeconds = 0.0;
    _totalTripSeconds = 0.0;
    _sessionEvents.clear();
    
    _currentSpeedKmh = 0.0;
    _currentGpsAccel = 0.0;
    _lastSpeedTime = DateTime.now();
    
    _startSensors();
    notifyListeners();
  }

  /// [speedKmh] – current FILTERED GPS speed in km/h.
  /// [speedLimitKmh] – posted limit from UI/Theme (or camera data).
  void onSpeedUpdate(double speedKmh, {double? speedLimitKmh}) {
    if (!_tripActive) return;

    final now = DateTime.now();
    if (_lastSpeedTime != null) {
      final dt = now.difference(_lastSpeedTime!).inMilliseconds / 1000.0;
      if (dt > 0) {
        _totalTripSeconds += dt;
        
        // Calculate macro trend for acceleration direction (m/s²)
        final speedMs = speedKmh / 3.6;
        final lastMs = _currentSpeedKmh / 3.6;
        if (dt < 3.0) {
          _currentGpsAccel = (speedMs - lastMs) / dt;
        }
        
        // Speeding check
        final limit = speedLimitKmh ?? _currentSpeedLimitKmh ?? 120.0;
        if (speedKmh > limit) {
          _timeOverLimitSeconds += dt;
        }
      }
    }

    _currentSpeedKmh = speedKmh;
    _currentSpeedLimitKmh = speedLimitKmh;
    _lastSpeedTime = now;
  }

  TripBehaviorSummary stopTrip() {
    _tripActive = false;
    _gyroSub?.cancel();
    _gyroSub = null;
    _accelSub?.cancel();
    _accelSub = null;

    final pct = _totalTripSeconds > 0
        ? (_timeOverLimitSeconds / _totalTripSeconds * 100).clamp(0, 100).toDouble()
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

  // ── Sensors ──────────────────────────────────────────────────────────────

  void _startSensors() {
    _gyroSub?.cancel();
    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((event) {
      if (!_tripActive) return;
      
      // Speed gate: ignore corners at very low speeds (e.g. parking)
      if (_currentSpeedKmh < minCornerSpeedKmh) return;

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
    }, onError: (e) => debugPrint('[BehaviorProvider] Gyro error: $e'));

    _accelSub?.cancel();
    _accelSub = userAccelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
        .listen((event) {
      if (!_tripActive) return;
      
      // Magnitude of linear acceleration
      final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      if (mag > harshAccelBrakeMagThreshold) {
        // Use the macro GPS trend to determine if it's a brake or an acceleration
        if (_currentGpsAccel < -0.2) {
          if (_canFire(_lastBrakeTime)) {
            harshBrakeCount++;
            _lastBrakeTime = DateTime.now();
            _recordEvent('brake', mag);
            notifyListeners();
          }
        } else if (_currentGpsAccel > 0.2) {
          if (_canFire(_lastAccelTime)) {
            harshAccelCount++;
            _lastAccelTime = DateTime.now();
            _recordEvent('accel', mag);
            notifyListeners();
          }
        } else {
          // If GPS hasn't updated yet (trend is 0), use speed fallback
          if (_currentSpeedKmh < 5.0) {
            // Sudden jolt from stationary is almost always acceleration
            if (_canFire(_lastAccelTime)) {
              harshAccelCount++;
              _lastAccelTime = DateTime.now();
              _recordEvent('accel', mag);
              notifyListeners();
            }
          }
        }
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
