import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ignite/models/trip_model.dart';
import 'package:ignite/providers/theme_provider.dart';
import 'package:ignite/driving_behavior/behavior_provider.dart';
import 'package:ignite/driving_behavior/behavior_event_model.dart';
import 'package:ignite/driving_behavior/trip_score.dart';
import 'package:home_widget/home_widget.dart';
import 'package:sensors_plus/sensors_plus.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({super.key});

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  final GlobalKey _signalKey = GlobalKey();
  final GlobalKey _gaugeKey = GlobalKey();
  final GlobalKey _hudKey = GlobalKey();
  final GlobalKey _startBtnKey = GlobalKey();
  final GlobalKey _limitKey = GlobalKey();
  final GlobalKey _themeKey = GlobalKey();

  StreamSubscription<Position>? _positionStream;
  Timer? _tripTimer;
  Timer? _alertTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Behavior summary from last completed trip
  TripBehaviorSummary? _lastBehaviorSummary;

  double _speed = 0;
  double _fusedSpeed = 0; // Accelerometer-fused speed for higher responsiveness
  DateTime _lastFusedUpdate = DateTime.now();
  StreamSubscription<UserAccelerometerEvent>? _accelSpeedSub;
  double _distance = 0;
  double _accuracy = 999;

  Duration _tripDuration = Duration.zero;

  final List<double> _recentSpeeds = [];
  final List<double> _allSpeeds = [];
  final List<double> _allLatitudes = [];
  final List<double> _allLongitudes = [];

  static const int _stabilityWindow = 8;
  static const double _maxSpeed = 160;

  // GPS filtering thresholds
  static const double _minDistanceMeters = 2.0; // Higher sensitivity
  static const double _minSpeedKmh =
      1.0; // Lower cutoff for better slow-speed detection

  Position? _lastPosition;
  bool _tracking = false;
  bool _hudMode = false;

  // Realtime Session Metrics
  double _sessionMaxSpeed = 0;
  double _sessionAvgSpeed = 0;

  // Kalman Filter for Speed
  late SimpleKalmanFilter _speedFilter;

  bool _isOverLimit = false;

  @override
  void initState() {
    super.initState();
    _speedFilter =
        SimpleKalmanFilter(decisionNoise: 2.0, measurementNoise: 1.0);
  }

  final TextEditingController _controller = TextEditingController();

  // ---------------- TRIP CONTROL ----------------

  Future<void> _startTrip() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    setState(() {
      _tracking = true;
      _speed = 0;
      _fusedSpeed = 0;
      _distance = 0;
      _accuracy = 999;
      _tripDuration = Duration.zero;
      _recentSpeeds.clear();
      _allSpeeds.clear();
      _sessionMaxSpeed = 0;
      _sessionAvgSpeed = 0;
      _allLatitudes.clear();
      _allLongitudes.clear();
      _speedFilter = SimpleKalmanFilter(
          decisionNoise: 2.0,
          measurementNoise: 1.0,
          estimateError: 1); // Reset filter
      _lastPosition = null;
    });

    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_tracking) {
        setState(() => _tripDuration += const Duration(seconds: 1));
      }
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(_onPosition);

    // ── High-Frequency Speedometer Sensor Fusion ────────────────────────
    _accelSpeedSub?.cancel();
    _accelSpeedSub =
        userAccelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen((event) {
      if (!_tracking || _lastPosition == null) return;

      final now = DateTime.now();
      final dt = now.difference(_lastFusedUpdate).inMilliseconds / 1000.0;
      _lastFusedUpdate = now;

      // Safety bounds for integration
      if (dt <= 0 || dt > 1.0) return;

      // Accelerometer magnitude
      final mag =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      // Determine direction of acceleration based on recent GPS trends
      double accelSign = 0;
      if (_recentSpeeds.length >= 2) {
        final delta =
            _recentSpeeds.last - _recentSpeeds[_recentSpeeds.length - 2];
        if (delta > 0.5)
          accelSign = 1;
        else if (delta < -0.5) accelSign = -1;
      }

      // If there's meaningful acceleration matching our macro GPS trend, fuse it!
      if (mag > 0.3 && accelSign != 0) {
        // Convert m/s^2 to km/h per second
        final speedChangeKmh = (mag * accelSign) * 3.6 * dt;

        setState(() {
          _fusedSpeed += speedChangeKmh;

          // Do not allow fused speed to go below 0
          if (_fusedSpeed < 0) _fusedSpeed = 0;

          // Constrain drift (max 10% or 10 km/h deviation from true GPS)
          if ((_fusedSpeed - _speed).abs() > max(10.0, _speed * 0.1)) {
            _fusedSpeed = _fusedSpeed > _speed ? _speed + 10.0 : _speed - 10.0;
          }
        });
      }
    });

    // ── New: start behavior tracker & trigger camera sync ─────────────────
    final behaviorProvider =
        Provider.of<BehaviorProvider>(context, listen: false);
    final tripKey = DateTime.now().millisecondsSinceEpoch; // temp key
    behaviorProvider.startTrip(tripKey);
  }

  void _stopTrackingOnly() {
    _positionStream?.cancel();
    _accelSpeedSub?.cancel();
    _tripTimer?.cancel();
    _stopAlertLoop();
    _positionStream = null;
    _accelSpeedSub = null;
    _tripTimer = null;
    setState(() => _tracking = false);

    // Collect behavior summary (stored temporarily for _saveTrip)
    final behaviorProvider =
        Provider.of<BehaviorProvider>(context, listen: false);
    _lastBehaviorSummary = behaviorProvider.stopTrip();
  }

  // ---------------- GPS CORE ----------------

  void _onPosition(Position p) {
    setState(() {
      _accuracy = p.accuracy;
    });

    // Ignore positions with very low accuracy (weak signal / indoor)
    if (p.accuracy > 25) {
      if (_speed > 0) {
        setState(() {
          _speed = 0;
          _fusedSpeed = 0;
        });
        _checkSpeedLimit();
      }
      return;
    }

    double rawSpeedKmh = (p.speed < 0) ? 0 : p.speed * 3.6;

    if (_lastPosition != null) {
      final distanceMeters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        p.latitude,
        p.longitude,
      );

      // Filter out minimal movements that are likely GPS jitter
      // Use Kalman Filter on Speed
      double filteredSpeed = _speedFilter.filter(rawSpeedKmh);

      // Post-filtering noise gate
      if (filteredSpeed < 1.0) filteredSpeed = 0;

      if (distanceMeters < _minDistanceMeters && rawSpeedKmh < _minSpeedKmh) {
        // Force zero if practically stationary
        filteredSpeed = 0;
      }

      setState(() {
        _speed = filteredSpeed;

        // ── Sensor Fusion ──────────────────────────────────────────
        // Hard reset the fused speed to the exact GPS speed to eliminate drift
        _fusedSpeed = _speed;
        _lastFusedUpdate = DateTime.now();

        _distance += distanceMeters;

        // Update Session Metrics
        if (_speed > _sessionMaxSpeed) {
          _sessionMaxSpeed = _speed;
        }

        _allSpeeds.add(_speed);
        _recentSpeeds.add(_speed);

        if (_allSpeeds.isNotEmpty) {
          _sessionAvgSpeed =
              _allSpeeds.reduce((a, b) => a + b) / _allSpeeds.length;
        }

        if (_recentSpeeds.length > _stabilityWindow) {
          _recentSpeeds.removeAt(0);
        }

        // Record coordinates for path mapping
        _allLatitudes.add(p.latitude);
        _allLongitudes.add(p.longitude);
      });
    } else {
      // First position
      setState(() {
        _speed = rawSpeedKmh;
        _fusedSpeed = _speed;
        _lastFusedUpdate = DateTime.now();
      });
    }

    _lastPosition = p;
    _checkSpeedLimit();

    // ── Feed behavior tracker ─────────────────────────────────────────────
    final behaviorProvider =
        Provider.of<BehaviorProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    // Fix: pass the filtered _speed instead of raw noisy GPS speed
    // Fix: pass the real speed limit instead of null
    behaviorProvider.onSpeedUpdate(
      _speed,
      speedLimitKmh: themeProvider.speedLimit,
    );
  }

  void _checkSpeedLimit() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final limit = themeProvider.speedLimit;

    if (_speed >= limit) {
      if (!_isOverLimit) {
        _isOverLimit = true;
        _startAlertLoop();
      }
    } else {
      if (_isOverLimit) {
        _isOverLimit = false;
        _stopAlertLoop();
      }
    }
  }

  void _startAlertLoop() {
    if (_alertTimer != null) return;

    // Initial alert
    _triggerAlertsOnce();

    // Repeat every 2 seconds
    _alertTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _triggerAlertsOnce();
    });
  }

  void _stopAlertLoop() {
    _alertTimer?.cancel();
    _alertTimer = null;
    Vibration.cancel();
    _audioPlayer.stop();
  }

  Future<void> _triggerAlertsOnce() async {
    final provider = Provider.of<ThemeProvider>(context, listen: false);

    if (provider.enableVibrationAlert) {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(duration: 500, amplitude: 128);
      }
    }

    if (provider.enableSoundAlert) {
      try {
        await _audioPlayer.play(AssetSource('audio/over_limit.mp3'));
      } catch (e) {
        debugPrint('Custom sound failed: $e');
      }
    }
  }

  // ---------------- SAVE TRIP ----------------

  void _saveTrip() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _tripDuration.inSeconds < 1) return;

    final avgSpeed = _allSpeeds.isEmpty
        ? 0
        : _allSpeeds.reduce((a, b) => a + b) / _allSpeeds.length;

    final maxSpeed = _allSpeeds.isEmpty ? 0 : _allSpeeds.reduce(max);

    final summary = _lastBehaviorSummary;

    final trip = TripModel(
      name: name,
      startTime: DateTime.now().subtract(_tripDuration),
      durationSeconds: _tripDuration.inSeconds,
      distanceKm: _distance / 1000,
      avgSpeed: avgSpeed.toDouble(),
      maxSpeed: maxSpeed.toDouble(),
      speedReadings: List<double>.from(_allSpeeds),
      latitudes: List<double>.from(_allLatitudes),
      longitudes: List<double>.from(_allLongitudes),
      // Behavior fields
      harshBrakeCount: summary?.harshBrakeCount ?? 0,
      harshAccelCount: summary?.harshAccelCount ?? 0,
      sharpCornerCount: summary?.sharpCornerCount ?? 0,
      timeOverLimitPct: summary?.timeOverLimitPct ?? 0.0,
      driveScore: summary?.driveScore ?? 100,
    );

    final box = Hive.box<TripModel>('trips');
    await box.add(trip);

    // Persist behavior events linked to the new trip key
    if (summary != null && summary.events.isNotEmpty) {
      final eventBox = Hive.box<BehaviorEventModel>('behavior_events');
      final newKey = box.keys.last as int;
      for (final ev in summary.events) {
        await eventBox.add(BehaviorEventModel(
          tripKey: newKey,
          eventType: ev.eventType,
          timestamp: ev.timestamp,
          severity: ev.severity,
        ));
      }
    }

    // Update Home Widget
    try {
      final score = summary?.driveScore ?? 100;
      final label = TripScore.label(score);

      await HomeWidget.saveWidgetData<String>('trip_score', score.toString());
      await HomeWidget.saveWidgetData<String>('score_label', label);
      await HomeWidget.saveWidgetData<String>(
          'max_speed', maxSpeed.toStringAsFixed(0));
      await HomeWidget.saveWidgetData<String>(
          'distance', (_distance / 1000).toStringAsFixed(2));
      await HomeWidget.saveWidgetData<String>(
          'duration', _formatDuration(_tripDuration));
      await HomeWidget.updateWidget(androidName: 'SpeedyWidgetProvider');
    } catch (e) {
      debugPrint('Error updating home widget: $e');
    }

    _lastBehaviorSummary = null;
  }

  // ---------------- UI HELPERS ----------------

  void _resetTripState() {
    setState(() {
      _speed = 0;
      _fusedSpeed = 0;
      _distance = 0;
      _accuracy = 999;
      _tripDuration = Duration.zero;
      _recentSpeeds.clear();
      _allSpeeds.clear();
      _lastPosition = null;
      _tracking = false;
      _isOverLimit = false;
      _stopAlertLoop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _positionStream?.cancel();
    _accelSpeedSub?.cancel();
    _tripTimer?.cancel();
    _stopAlertLoop();
    super.dispose();
  }

  // ---------------- BUILD ----------------

  Color _getSpeedColor(double speed, double limit) {
    if (speed >= limit) return const Color(0xFFFF2A00); // Ignite Red
    if (speed < 40) return const Color(0xFFFFAB00); // Amber Gold
    if (speed < 80) return const Color(0xFFFF5722); // Flame Orange
    if (speed < 120) return const Color(0xFFFF3D00); // Deep Orange
    return const Color(0xFFFF2A00); // Ignite Red
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey : Colors.grey.shade600;

    // Calculate dynamic size for responsiveness
    final size = MediaQuery.of(context).size;
    final gaugeSize = min(size.width * 0.75, 300.0);

    final themeProvider = Provider.of<ThemeProvider>(context);
    final limit = themeProvider.speedLimit;
    final accentColor = _getSpeedColor(_fusedSpeed, limit);

    final behaviorProvider = Provider.of<BehaviorProvider>(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A0C) : const Color(0xFFF7F8FA),
      body: Container(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              top: 36.0, // Increased proper top spacing
              bottom: 10.0,
            ),
            child: Column(
              children: [
                // TOP BAR: SIGNAL & SPEED LIMIT
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SignalBars(
                        key: _signalKey, accuracy: _accuracy, isDark: isDark),
                    
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.satellite_alt,
                                size: 14,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '±${_accuracy.toStringAsFixed(0)}m',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          if (_accuracy > 40)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  'INDOOR / POOR GPS',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    _speedLimitSign(
                        key: _limitKey,
                        limit: limit,
                        isDark: isDark,
                        isOver: _speed >= limit),
                  ],
                ),

                Expanded(
                  flex: 3,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final gaugeSize =
                        min(constraints.maxWidth, constraints.maxHeight) * 0.95;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // ── GAUGE ──────────────────────────────────────────
                        Center(
                          child: Transform(
                            key: _gaugeKey,
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(_hudMode ? pi : 0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // HUD high-tech frame/glow
                                if (_hudMode)
                                  Container(
                                    width: gaugeSize * 1.05,
                                    height: gaugeSize * 1.05,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            accentColor.withValues(alpha: 0.1),
                                        width: 1,
                                      ),
                                    ),
                                  ),

                                // Glow Background (Reactive)
                                if (isDark)
                                  TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                        begin: 0, end: _fusedSpeed),
                                    duration: const Duration(milliseconds: 100),
                                    builder: (context, value, child) {
                                      return Container(
                                        width: gaugeSize * 0.8,
                                        height: gaugeSize * 0.8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  _getSpeedColor(value, limit)
                                                      .withValues(alpha: 0.2),
                                              blurRadius: 60,
                                              spreadRadius: 15,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                TweenAnimationBuilder<double>(
                                  tween:
                                      Tween<double>(begin: 0, end: _fusedSpeed),
                                  duration: const Duration(milliseconds: 100),
                                  builder: (context, value, child) {
                                    return CustomPaint(
                                      size: Size(gaugeSize, gaugeSize),
                                      painter: _FuturisticGaugePainter(
                                        speed: value,
                                        maxSpeed: _maxSpeed,
                                        isDark: isDark,
                                        accentColor:
                                            _getSpeedColor(value, limit),
                                      ),
                                    );
                                  },
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'KM/H',
                                      style: GoogleFonts.orbitron(
                                        fontSize: gaugeSize * 0.06,
                                        letterSpacing: 3,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TweenAnimationBuilder<double>(
                                      tween: Tween<double>(
                                          begin: 0, end: _fusedSpeed),
                                      duration:
                                          const Duration(milliseconds: 100),
                                      builder: (context, value, child) {
                                        return Text(
                                          value.toStringAsFixed(0),
                                          style: GoogleFonts.orbitron(
                                            fontSize: gaugeSize * 0.35,
                                            fontWeight: FontWeight.w900,
                                            color: textColor,
                                            letterSpacing: -3,
                                            height: 1.0,
                                            shadows: isDark
                                                ? [
                                                    Shadow(
                                                        color: _getSpeedColor(
                                                                value, limit)
                                                            .withValues(
                                                                alpha: 0.6),
                                                        blurRadius: 25),
                                                  ]
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                    Text(
                                      'CURRENT SPEED',
                                      style: GoogleFonts.inter(
                                        fontSize: gaugeSize * 0.035,
                                        letterSpacing: 2,
                                        color: secondaryTextColor.withValues(
                                            alpha: 0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),

                                // HUD Scanlines Effect
                                if (_hudMode)
                                  IgnorePointer(
                                    child: SizedBox(
                                      width: gaugeSize,
                                      height: gaugeSize,
                                      child: CustomPaint(
                                        painter: _HUDScannerPainter(
                                            color: accentColor),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // ── ENGINE START/STOP BUTTON — center bottom of gauge area ──
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _SpeedZoneBadge(speed: _fusedSpeed, limit: limit),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _EngineStartStopButton(
                                  key: _startBtnKey,
                                  isTracking: _tracking,
                                  onTap: _tracking
                                      ? () {
                                          _stopTrackingOnly();
                                          _confirmSaveTrip();
                                        }
                                      : _startTrip,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 8),

                // SLIM HORIZONTAL STAT BAR
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _slimStat(
                        icon: Icons.map_outlined,
                        label: 'Distance',
                        value: '${(_distance / 1000).toStringAsFixed(1)} km',
                        isDark: isDark,
                      ),
                      _slimDivider(isDark),
                      _slimStat(
                        icon: Icons.timer_outlined,
                        label: 'Duration',
                        value: _formatDuration(_tripDuration),
                        isDark: isDark,
                      ),
                      _slimDivider(isDark),
                      GestureDetector(
                        onTap: () => setState(() => _hudMode = !_hudMode),
                        child: _slimStat(
                          icon: Icons.flip,
                          label: 'HUD',
                          value: _hudMode ? 'ON' : 'OFF',
                          isDark: isDark,
                          valueColor: _hudMode ? const Color(0xFFFF5722) : null,
                        ),
                      ),
                      _slimDivider(isDark),
                      _slimStat(
                        icon: Icons.bolt,
                        label: 'Max',
                        value:
                            '${_allSpeeds.isEmpty ? 0 : (_allSpeeds.reduce(max)).toStringAsFixed(0)}',
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── BEHAVIOR LIVE COUNTERS ────────────────────────────────────
                if (_tracking) ...[
                  _BehaviorLiveRow(
                    brakes: behaviorProvider.harshBrakeCount,
                    accels: behaviorProvider.harshAccelCount,
                    corners: behaviorProvider.sharpCornerCount,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _slimStat({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12, color: isDark ? Colors.white54 : Colors.black54),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.orbitron(
            color: valueColor ?? (isDark ? Colors.white : Colors.black),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _slimDivider(bool isDark) {
    return Container(
      height: 32,
      width: 1,
      color: isDark ? Colors.white24 : Colors.black12,
    );
  }

  // ---------------- DIALOG BUTTON ----------------

  Widget _dialogButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ---------------- SAVE DIALOG ----------------

  Future<void> _confirmSaveTrip() async {
    _controller.clear();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    if (isIOS) {
      return showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Save Trip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('Give your trip a name to save it'),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _controller,
                placeholder: 'Trip name',
                placeholderStyle: TextStyle(
                    color: isDark ? Colors.grey : Colors.grey.shade400),
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                _controller.clear();
                Navigator.pop(context);
                _resetTripState();
              },
              child: const Text('Discard'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                if (_controller.text.trim().isEmpty) return;
                _saveTrip();
                _controller.clear();
                Navigator.pop(context);
                _resetTripState();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF141418), const Color(0xFF0A0A0C)]
                      : [Colors.white, Colors.grey.shade100],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? const Color(0x33FF5722) : Colors.black12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? const Color(0x22FF5722)
                        : Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                          ),
                          child: Icon(
                            Icons.bookmark_add_rounded,
                            color: isDark ? Colors.white : Colors.black87,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Save Trip',
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Give your trip a name to save it',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: isDark
                                      ? Colors.grey
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _tripStatPill(
                          label: 'Distance',
                          value: '${(_distance / 1000).toStringAsFixed(2)} km',
                          isDark: isDark,
                        ),
                        _tripStatPill(
                          label: 'Duration',
                          value: _formatDuration(_tripDuration),
                          isDark: isDark,
                        ),
                        _tripStatPill(
                          label: 'Avg',
                          value: '${_sessionAvgSpeed.toStringAsFixed(0)} km/h',
                          isDark: isDark,
                        ),
                        _tripStatPill(
                          label: 'Max',
                          value: '${_sessionMaxSpeed.toStringAsFixed(0)} km/h',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Input
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      cursorColor: isDark ? Colors.white : Colors.blueAccent,
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Trip name',
                        hintStyle: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFFF5722),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: _dialogButton(
                            label: 'DISCARD',
                            color: Colors.redAccent,
                            onTap: () {
                              _controller.clear();
                              Navigator.pop(context);
                              _resetTripState();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dialogButton(
                            label: 'SAVE',
                            color: Colors.green,
                            onTap: () {
                              if (_controller.text.trim().isEmpty) return;

                              _saveTrip();
                              _controller.clear();
                              Navigator.pop(context);
                              _resetTripState();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tripStatPill({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black12,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              letterSpacing: 0.8,
              color: isDark ? Colors.white54 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- SPEED ZONE BADGE ----------------

class _SpeedZoneBadge extends StatefulWidget {
  final double speed;
  final double limit;
  const _SpeedZoneBadge({required this.speed, required this.limit});

  @override
  State<_SpeedZoneBadge> createState() => _SpeedZoneBadgeState();
}

class _SpeedZoneBadgeState extends State<_SpeedZoneBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speed = widget.speed;
    final limit = widget.limit;
    final bool isOver = speed >= limit;

    String label;
    Color color;

    if (isOver) {
      label = 'LIMIT EXCEEDED';
      color = const Color(0xFFFF2A00);
    } else if (speed >= 80) {
      label = 'FAST';
      color = const Color(0xFFFF3D00);
    } else if (speed >= 40) {
      label = 'MODERATE';
      color = const Color(0xFFFF5722);
    } else {
      label = 'SAFE';
      color = const Color(0xFFFFAB00);
    }

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isOver ? 0.35 : 0.15),
            blurRadius: isOver ? 16 : 8,
            spreadRadius: isOver ? 2 : 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (isOver) {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: _pulseAnim.value, child: child),
        child: badge,
      );
    }
    return badge;
  }
}

// ---------------- BEHAVIOR LIVE ROW ----------------

class _BehaviorLiveRow extends StatelessWidget {
  final int brakes;
  final int accels;
  final int corners;
  final bool isDark;

  const _BehaviorLiveRow({
    required this.brakes,
    required this.accels,
    required this.corners,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.05)
                ]
              : [
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.02)
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _counter(Icons.speed, 'Accel', accels),
          _counter(Icons.warning_amber_rounded, 'Brake', brakes),
          _counter(Icons.turn_right_rounded, 'Corner', corners),
        ],
      ),
    );
  }

  Widget _counter(IconData icon, String label, int count) {
    final hasEvents = count > 0;
    final color = hasEvents
        ? Colors.redAccent
        : (isDark ? Colors.white54 : Colors.black54);

    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          hasEvents ? '$count' : '0',
          style: GoogleFonts.orbitron(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------- ARC PAINTER ----------------

class _FuturisticGaugePainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final bool isDark;
  final Color accentColor;

  _FuturisticGaugePainter({
    required this.speed,
    required this.maxSpeed,
    required this.isDark,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = size.width * 0.04; // Adaptive stroke width

    // Background Track
    final trackPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -1.2 * pi,
      1.4 * pi,
      false,
      trackPaint,
    );

    // Tick Marks
    final tickPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final int tickCount = 40;
    final double tickRadius = radius - strokeWidth * 1.5;
    // final double totalAngle = 1.4 * pi + 1.2 * pi; // Start to end angle span

    for (int i = 0; i <= tickCount; i++) {
      final double tickAngle = -1.2 * pi + (i / tickCount) * 2.6 * pi;
      final p1 = Offset(
        center.dx + tickRadius * cos(tickAngle),
        center.dy + tickRadius * sin(tickAngle),
      );
      final p2 = Offset(
        center.dx + (tickRadius - 5) * cos(tickAngle),
        center.dy + (tickRadius - 5) * sin(tickAngle),
      );
      // Only draw ticks that are "active" if we want, or all of them.
      // Let's draw all faintly
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Speed Progress with Glow
    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          accentColor.withValues(alpha: 0.1),
          accentColor,
          Colors.white,
        ],
        stops: [0.0, 0.9, 1.0],
        startAngle: -1.2 * pi,
        endAngle: 0.2 * pi,
        transform: GradientRotation(0),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.solid, 4); // Soft glow

    final sweepAngle = (speed / maxSpeed) * 1.4 * pi; // Match background span

    // Outer Glow
    if (isDark) {
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        -1.2 * pi,
        sweepAngle,
        false,
        glowPaint,
      );
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -1.2 * pi,
      sweepAngle,
      false,
      progressPaint,
    );

    // Ticks
    final majorTickPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black26
      ..strokeWidth = 2;

    for (var i = 0; i <= 10; i++) {
      final angle = -1.2 * pi + (i / 10) * 1.4 * pi;
      final start = Offset(
        center.dx + (radius - 25) * cos(angle),
        center.dy + (radius - 25) * sin(angle),
      );
      final end = Offset(
        center.dx + (radius - 15) * cos(angle),
        center.dy + (radius - 15) * sin(angle),
      );
      canvas.drawLine(start, end, majorTickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FuturisticGaugePainter old) =>
      old.speed != speed || old.isDark != isDark;
}

class _SignalBars extends StatelessWidget {
  final double accuracy;
  final bool isDark;
  const _SignalBars({super.key, required this.accuracy, required this.isDark});

  @override
  Widget build(BuildContext context) {
    int bars = 0;
    if (accuracy <= 10) {
      bars = 4;
    } else if (accuracy <= 25) {
      bars = 3;
    } else if (accuracy <= 50) {
      bars = 2;
    } else if (accuracy <= 100) {
      bars = 1;
    }

    Color barColor;
    if (accuracy <= 25) {
      barColor = const Color(0xFFFFAB00); // Amber Gold — good GPS
    } else if (accuracy <= 60) {
      barColor = const Color(0xFFFF5722); // Flame Orange — moderate
    } else {
      barColor = const Color(0xFFFF2A00); // Ignite Red — poor
    }
    if (!isDark && accuracy <= 25) barColor = const Color(0xFFFFAB00);
    if (!isDark && accuracy > 25) barColor = const Color(0xFFFF5722);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: barColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "GPS",
            style: GoogleFonts.inter(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (index) {
              bool active = index < bars;
              return Container(
                margin: const EdgeInsets.only(left: 2),
                width: 3,
                height: 4.0 + (index * 2.5),
                decoration: BoxDecoration(
                  color: active
                      ? barColor
                      : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

Widget _speedLimitSign(
    {Key? key,
    required double limit,
    required bool isDark,
    required bool isOver}) {
  final limitText = limit.toStringAsFixed(0);
  final isThreeDigits = limitText.length >= 3;

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        key: key,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD32F2F), width: 5.0),
          boxShadow: [
            BoxShadow(
              color: isOver
                  ? Colors.red.withValues(alpha: 0.8)
                  : Colors.black.withValues(alpha: 0.2),
              blurRadius: isOver ? 16 : 6,
              spreadRadius: isOver ? 4 : 1,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Center(
          child: Text(
            limitText,
            style: GoogleFonts.inter(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: isThreeDigits ? 18 : 22,
              height: 1.0,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'LIMIT KM/H',
        style: GoogleFonts.inter(
          color: isDark ? Colors.white54 : Colors.black54,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      ),
    ],
  );
}

class _ThemeToggle extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggle;
  const _ThemeToggle({super.key, required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          border: Border.all(
            color: isDark
                ? Colors.orangeAccent.withValues(alpha: 0.3)
                : Colors.indigoAccent.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            if (isDark)
              BoxShadow(
                color: Colors.orangeAccent.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 1,
              )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return RotationTransition(
                    turns: animation,
                    child: FadeTransition(opacity: animation, child: child));
              },
              child: Icon(
                isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                key: ValueKey<bool>(isDark),
                size: 18,
                color: isDark ? Colors.orangeAccent : Colors.indigoAccent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isDark ? 'LIGHT' : 'DARK',
              style: GoogleFonts.orbitron(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HUDScannerPainter extends CustomPainter {
  final Color color;
  _HUDScannerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Subtle horizontal scanlines
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Outer corner accents
    final accentPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final l = 20.0; // corner length

    // Top Left
    canvas.drawLine(Offset.zero, Offset(l, 0), accentPaint);
    canvas.drawLine(Offset.zero, Offset(0, l), accentPaint);

    // Top Right
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width - l, 0), accentPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, l), accentPaint);

    // Bottom Left
    canvas.drawLine(
        Offset(0, size.height), Offset(l, size.height), accentPaint);
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - l), accentPaint);

    // Bottom Right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - l, size.height), accentPaint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - l), accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
// ---------------- KALMAN FILTER ----------------

class SimpleKalmanFilter {
  final double _errMeasure;
  double _errEstimate;
  final double _q;
  double _currentEstimate = 0;
  double _lastEstimate = 0;
  double _kalmanGain = 0;

  SimpleKalmanFilter({
    required double measurementNoise,
    required double decisionNoise,
    double estimateError = 1,
  })  : _errMeasure = measurementNoise,
        _q = decisionNoise,
        _errEstimate = estimateError;

  double filter(double text) {
    // Prediction
    _currentEstimate = _lastEstimate;
    _errEstimate = _errEstimate + _q;

    // Update
    _kalmanGain = _errEstimate / (_errEstimate + _errMeasure);
    _currentEstimate =
        _currentEstimate + _kalmanGain * (text - _currentEstimate);
    _errEstimate = (1.0 - _kalmanGain) * _errEstimate;

    _lastEstimate = _currentEstimate;
    return _currentEstimate;
  }
}

// ---------------- ENGINE START/STOP BUTTON ----------------

class _EngineStartStopButton extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onTap;

  const _EngineStartStopButton({
    super.key,
    required this.isTracking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        isTracking ? const Color(0xFFFF2A00) : const Color(0xFFFF5722);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF141418) : Colors.white,
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isTracking
                  ? color.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.2),
              blurRadius: isTracking ? 16 : 8,
              spreadRadius: isTracking ? 4 : 0,
              offset: const Offset(0, 4),
            ),
            // Inner rim highlight
            BoxShadow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              spreadRadius: -2,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Indicator Light
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: isTracking
                    ? color
                    : (isDark ? Colors.white24 : Colors.black26),
                boxShadow: isTracking
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.8),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ENGINE',
              style: GoogleFonts.inter(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 2),
            if (!isTracking)
              Text(
                'START',
                style: GoogleFonts.orbitron(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              )
            else
              Text(
                'STOP',
                style: GoogleFonts.orbitron(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  height: 1.0,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
