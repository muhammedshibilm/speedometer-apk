import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'trip_model.dart';
import 'theme_provider.dart';
import 'camera_alerts/camera_alert_provider.dart';
import 'camera_alerts/camera_model.dart';
import 'camera_alerts/overpass_service.dart';
import 'camera_alerts/proximity_detector.dart';
import 'driving_behavior/behavior_provider.dart';
import 'driving_behavior/behavior_event_model.dart';
import 'driving_behavior/trip_score.dart';

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
  
  late TutorialCoachMark tutorialCoachMark;
  List<TargetFocus> targets = [];

  StreamSubscription<Position>? _positionStream;
  Timer? _tripTimer;
  Timer? _alertTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Behavior summary from last completed trip
  TripBehaviorSummary? _lastBehaviorSummary;

  double _speed = 0;
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
    _speedFilter = SimpleKalmanFilter(decisionNoise: 2.0, measurementNoise: 1.0);
    
    Future.delayed(const Duration(milliseconds: 500), () {
      _checkAndShowTutorial();
    });
  }

  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('coach_mark_shown') ?? false;
    if (!shown) {
      _showTutorial();
      await prefs.setBool('coach_mark_shown', true);
    }
  }

  void _showTutorial() {
    _initTargets();
    tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      paddingFocus: 10,
      textSkip: "SKIP",
      onFinish: () => debugPrint("Tutorial Finished"),
      onClickTarget: (target) => debugPrint("Clicked target"),
      onSkip: () {
        debugPrint("Tutorial Skipped");
        return true;
      },
    )..show(context: context);
  }

  void _initTargets() {
    targets.clear();
    
    // GPS Signal
    targets.add(
      TargetFocus(
        identify: "signal",
        keyTarget: _signalKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    "GPS Connectivity",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                   Text(
                    "Watch these bars to ensure a strong GPS lock. Green means you're ready to go!",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("NEXT"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Speed Gauge
    targets.add(
      TargetFocus(
        identify: "gauge",
        keyTarget: _gaugeKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    "Speed Gauge",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                   Text(
                    "This high-precision display shows your current speed. It glows red if you exceed the limit!",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("NEXT"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // HUD Mode
    targets.add(
      TargetFocus(
        identify: "hud",
        keyTarget: _hudKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    "HUD Mode",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                   Text(
                    "Tap here to flip the display. Perfect for projecting your speed onto the windshield at night.",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("NEXT"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Speed Limit
    targets.add(
      TargetFocus(
        identify: "limit",
        keyTarget: _limitKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    "Speed Limit",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                   Text(
                    "Set your maximum speed in settings. This indicator turns red and alerts you if you go too fast!",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("NEXT"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Theme Toggle
    targets.add(
      TargetFocus(
        identify: "theme",
        keyTarget: _themeKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    "Appearance Control",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                   Text(
                    "Switch between Light and Dark mode instantly to suit your driving conditions.",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("NEXT"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // Start Button
    targets.add(
      TargetFocus(
        identify: "start",
        keyTarget: _startBtnKey,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                   Text(
                    "Begin Your Journey",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                   Text(
                    "Tap START TRIP to begin tracking your route and stats.",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("FINISH"),
                  ),
                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ],
      ),
    );
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
      _distance = 0;
      _accuracy = 999;
      _tripDuration = Duration.zero;
      _recentSpeeds.clear();
      _allSpeeds.clear();
      _sessionMaxSpeed = 0;
      _sessionAvgSpeed = 0;
      _allLatitudes.clear();
      _allLongitudes.clear();
      _speedFilter = SimpleKalmanFilter(decisionNoise: 2.0, measurementNoise: 1.0, estimateError: 1); // Reset filter
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

    // ── New: start behavior tracker & trigger camera sync ─────────────────
    final behaviorProvider = Provider.of<BehaviorProvider>(context, listen: false);
    final tripKey = DateTime.now().millisecondsSinceEpoch; // temp key
    behaviorProvider.startTrip(tripKey);
  }

  void _stopTrackingOnly() {
    _positionStream?.cancel();
    _tripTimer?.cancel();
    _stopAlertLoop();
    _positionStream = null;
    _tripTimer = null;
    setState(() => _tracking = false);

    // Collect behavior summary (stored temporarily for _saveTrip)
    final behaviorProvider = Provider.of<BehaviorProvider>(context, listen: false);
    _lastBehaviorSummary = behaviorProvider.stopTrip();
  }

  // ---------------- GPS CORE ----------------

  void _onPosition(Position p) {
    setState(() {
      _accuracy = p.accuracy;
    });

    // Ignore positions with very low accuracy (weak signal)
    if (p.accuracy > 25) return;

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
        _distance += distanceMeters;
        
        // Update Session Metrics
        if (_speed > _sessionMaxSpeed) {
          _sessionMaxSpeed = _speed;
        }
        
        _allSpeeds.add(_speed);
        _recentSpeeds.add(_speed);
        
        if (_allSpeeds.isNotEmpty) {
           _sessionAvgSpeed = _allSpeeds.reduce((a, b) => a + b) / _allSpeeds.length;
        }

        if (_recentSpeeds.length > _stabilityWindow) {
          _recentSpeeds.removeAt(0);
        }

        // Record coordinates for path mapping
        _allLatitudes.add(p.latitude);
        _allLongitudes.add(p.longitude);
      });
    }
  
    _lastPosition = p;
    _checkSpeedLimit();

    // ── Feed camera alerts ────────────────────────────────────────────────
    final cameraProvider = Provider.of<CameraAlertProvider>(context, listen: false);
    cameraProvider.onPositionUpdate(p);

    // ── Feed behavior tracker ─────────────────────────────────────────────
    final behaviorProvider = Provider.of<BehaviorProvider>(context, listen: false);
    final nearestCamera = cameraProvider.nearestCamera;
    behaviorProvider.onSpeedUpdate(
      rawSpeedKmh,
      speedLimitKmh: nearestCamera?.camera.maxspeed?.toDouble(),
    );

    // ── Trigger camera sync on first good fix ─────────────────────────────
    if (_allLatitudes.length == 1) {
      cameraProvider.syncForLocation(p.latitude, p.longitude);
    }
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
    _lastBehaviorSummary = null;
  }

  // ---------------- UI HELPERS ----------------

  void _resetTripState() {
    setState(() {
      _speed = 0;
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
    _tripTimer?.cancel();
    _stopAlertLoop();
    super.dispose();
  }

  // ---------------- BUILD ----------------

  Color _getSpeedColor(double speed, double limit) {
    if (speed >= limit) return Colors.redAccent;
    if (speed < 40) return Colors.cyanAccent;
    if (speed < 80) return Colors.orangeAccent;
    if (speed < 120) return Colors.deepOrangeAccent;
    return Colors.redAccent;
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
    final accentColor = _getSpeedColor(_speed, limit);

    // Camera alert provider
    final cameraProvider = Provider.of<CameraAlertProvider>(context);
    final behaviorProvider = Provider.of<BehaviorProvider>(context);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [

              // ── CAMERA ALERT BANNER ───────────────────────────────────
              if (cameraProvider.isAlertActive)
                _CameraAlertBanner(
                  result: cameraProvider.nearestCamera!,
                  isDark: isDark,
                ),

              // TOP BAR: SIGNAL & SPEED LIMIT
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   _SignalBars(key: _signalKey, accuracy: _accuracy, isDark: isDark),
                   _ThemeToggle(
                    key: _themeKey,
                    isDark: isDark,
                    onToggle: () {
                      if (themeProvider.useSystemTheme) {
                        themeProvider.toggleUseSystemTheme();
                      }
                      themeProvider.setTheme(isDark ? 'light' : 'dark');
                    },
                   ),
                   _speedLimitSign(key: _limitKey, limit: limit, isDark: isDark, isOver: _speed >= limit),
                ],
              ),
              const SizedBox(height: 10),
              
              // GAUGE AREA
              Transform(
                key: _gaugeKey,
                alignment: Alignment.center,
                transform: Matrix4.rotationY(_hudMode ? pi : 0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // HUD high-tech frame/glow
                    if (_hudMode)
                      Container(
                        width: gaugeSize * 1.2,
                        height: gaugeSize * 1.2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                    
                    // Glow Background (Reactive)
                    if (isDark)
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: _speed),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, child) {
                          return Container(
                            width: gaugeSize * 0.8,
                            height: gaugeSize * 0.8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _getSpeedColor(value, limit).withValues(alpha: 0.15),
                                  blurRadius: 50,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: _speed),
                      duration: const Duration(milliseconds: 300),
                      builder: (context, value, child) {
                        return CustomPaint(
                          size: Size(gaugeSize, gaugeSize),
                          painter: _FuturisticGaugePainter(
                            speed: value,
                            maxSpeed: _maxSpeed,
                            isDark: isDark,
                            accentColor: _getSpeedColor(value, limit),
                          ),
                        );
                      },
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: _speed),
                          duration: const Duration(milliseconds: 300),
                          builder: (context, value, child) {
                            return Text(
                              value.toStringAsFixed(0),
                              style: GoogleFonts.orbitron(
                                fontSize: gaugeSize * 0.3,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                letterSpacing: -2,
                                shadows: isDark
                                    ? [
                                        Shadow(
                                            color: _getSpeedColor(value, limit)
                                                .withValues(alpha: 0.5),
                                            blurRadius: 20),
                                      ]
                                    : null,
                              ),
                            );
                          },
                        ),
                        Text(
                          'KM/H',
                          style: GoogleFonts.orbitron(
                            fontSize: gaugeSize * 0.05,
                            letterSpacing: 4,
                            color: secondaryTextColor.withValues(alpha: 0.7),
                            fontWeight: FontWeight.bold,
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
                            painter: _HUDScannerPainter(color: accentColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // TRIP DATA GRID
              Row(
                children: [
                  Expanded(
                    child: _glassBlock(
                      label: 'DISTANCE',
                      value: (_distance / 1000).toStringAsFixed(2),
                      unit: 'KM',
                      icon: Icons.map_outlined,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _glassBlock(
                      label: 'DURATION',
                      value: _formatDuration(_tripDuration),
                      unit: 'MIN',
                      icon: Icons.timer_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                   Expanded(
                    child: _actionBlock(
                      key: _hudKey,
                      label: 'HUD MODE',
                      value: _hudMode ? 'ON' : 'OFF',
                      icon: Icons.flip,
                      isActive: _hudMode,
                      onTap: () => setState(() => _hudMode = !_hudMode),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                         padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.1),
                                      Colors.white.withValues(alpha: 0.05),
                                    ],
                                  )
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.05),
                                      Colors.black.withValues(alpha: 0.02),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              width: 1.5,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.bolt, size: 20, color: secondaryTextColor),
                              const SizedBox(height: 12),
                              Text(
                                '${_allSpeeds.isEmpty ? 0 : (_allSpeeds.reduce(max)).toStringAsFixed(0)}',
                                style: GoogleFonts.orbitron(
                                  color: textColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                               Text(
                                'MAX SPEED',
                                style: GoogleFonts.inter(
                                  color: secondaryTextColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),

              // ── BEHAVIOR LIVE COUNTERS ────────────────────────────────────
              if (_tracking)
                _BehaviorLiveRow(
                  brakes: behaviorProvider.harshBrakeCount,
                  accels: behaviorProvider.harshAccelCount,
                  corners: behaviorProvider.sharpCornerCount,
                  isDark: isDark,
                ),

              if (_tracking) const SizedBox(height: 12),

              // START/END TRIP BUTTON

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _tracking ? Colors.redAccent : Colors.greenAccent.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: _tracking ? Colors.redAccent.withValues(alpha: 0.5) : Colors.greenAccent.withValues(alpha: 0.5),
                ),
                onPressed: _tracking
                    ? () {
                        _stopTrackingOnly();
                        _confirmSaveTrip();
                      }
                    : _startTrip,
                key: _startBtnKey,
                child: Text(
                  _tracking ? 'END TRIP' : 'START TRIP',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _glassBlock({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required bool isDark,
    Color? accent,
    Widget? extraChild,
  }) {
    final color = isDark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.05),
                ]
              : [
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          width: 1.5,
          color: isDark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon,
                  size: 20,
                  color: accent ?? (isDark ? Colors.white54 : Colors.black45)),
              if (extraChild != null) extraChild,
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.orbitron(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBlock({
    Key? key,
    required String label,
    required String value,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isActive
                  ? [accent.withValues(alpha: 0.2), accent.withValues(alpha: 0.05)]
                  : (isDark
                      ? [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.white.withValues(alpha: 0.05)
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.02)
                        ])),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            width: 1.5,
            color: isActive
                ? accent.withValues(alpha: 0.5)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.1)),
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? accent.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: isActive
                    ? accent
                    : (isDark ? Colors.white54 : Colors.black45)),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.orbitron(
                color:
                    isActive ? accent : (isDark ? Colors.white : Colors.black),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
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
                      ? [const Color(0xFF1A1A1A), const Color(0xFF0F0F0F)]
                      : [Colors.white, Colors.grey.shade100],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
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
                                  color:
                                      isDark ? Colors.grey : Colors.grey.shade600,
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
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
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
                          borderSide: BorderSide(
                            color: isDark ? Colors.blueAccent : Colors.blueAccent,
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

// ---------------- CAMERA ALERT BANNER ----------------

class _CameraAlertBanner extends StatelessWidget {
  final ProximityResult result;
  final bool isDark;

  const _CameraAlertBanner({
    required this.result,
    required this.isDark,
  });

  /// Returns an icon appropriate for the camera type.
  IconData _iconFor(String type) {
    switch (type) {
      case CameraType.police:
      case CameraType.anpr:
        return Icons.local_police_outlined;
      case CameraType.redLight:
        return Icons.traffic_outlined;
      case CameraType.averageSpeed:
        return Icons.speed_outlined;
      default:
        return Icons.camera_alt_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = result.camera.typeLabel.toUpperCase();
    final limit = result.camera.maxspeed != null
        ? ' · ${result.camera.maxspeed} KM/H'
        : '';
    final alertColor =
        result.isCritical ? Colors.redAccent : Colors.orangeAccent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: isDark ? 0.18 : 0.1),
        border: Border.all(color: alertColor, width: 2),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (result.isCritical)
            BoxShadow(
              color: Colors.redAccent.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 3,
            ),
        ],
      ),
      child: Row(
        children: [
          Icon(_iconFor(result.camera.type), color: alertColor, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label AHEAD$limit',
                  style: GoogleFonts.orbitron(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.distanceText,
                  style: GoogleFonts.inter(
                    color: alertColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          // Pulse dot
          if (result.isCritical)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.7),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
            ),
        ],
      ),
    );
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
    final color = hasEvents ? Colors.redAccent : (isDark ? Colors.white54 : Colors.black54);

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
      ..color = isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.3)
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

    Color barColor = accuracy <= 25 ? Colors.greenAccent : (accuracy <= 60 ? Colors.orangeAccent : Colors.redAccent);
    if (!isDark && accuracy > 25) barColor = Colors.orange.shade700;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(Icons.gps_fixed, size: 14, color: isDark ? Colors.white38 : Colors.black38),
        const SizedBox(width: 6),
        ...List.generate(4, (index) {
          bool active = index < bars;
          return Container(
            margin: const EdgeInsets.only(left: 2),
            width: 4,
            height: 4.0 + (index * 3),
            decoration: BoxDecoration(
              color: active ? barColor : (isDark ? Colors.white12 : Colors.black12),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ],
    );
  }
}

Widget _speedLimitSign({Key? key, required double limit, required bool isDark, required bool isOver}) {
  final limitText = limit.toStringAsFixed(0);
  final isThreeDigits = limitText.length >= 3;
  
  return Container(
    key: key,
    padding: const EdgeInsets.all(2),
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      border: Border.all(color: Colors.red, width: 3.5),
      boxShadow: isOver ? [
        BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)
      ] : null,
    ),
    child: Center(
      child: Text(
        limitText,
        style: GoogleFonts.inter(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: isThreeDigits ? 14 : 16,
        ),
      ),
    ),
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
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          border: Border.all(
            color: isDark ? Colors.orangeAccent.withValues(alpha: 0.3) : Colors.indigoAccent.withValues(alpha: 0.3),
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
                return RotationTransition(turns: animation, child: FadeTransition(opacity: animation, child: child));
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
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - l, 0), accentPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, l), accentPaint);
    
    // Bottom Left
    canvas.drawLine(Offset(0, size.height), Offset(l, size.height), accentPaint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - l), accentPaint);
    
    // Bottom Right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - l, size.height), accentPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - l), accentPaint);
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
    _currentEstimate = _currentEstimate + _kalmanGain * (text - _currentEstimate);
    _errEstimate = (1.0 - _kalmanGain) * _errEstimate;
    
    _lastEstimate = _currentEstimate;
    return _currentEstimate;
  }
}
