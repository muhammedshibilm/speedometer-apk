import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'trip_model.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({super.key});

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  StreamSubscription<Position>? _positionStream;
  Timer? _tripTimer;

  double _speed = 0;
  double _distance = 0;
  double _accuracy = 999;

  Duration _tripDuration = Duration.zero;

  final List<double> _recentSpeeds = [];
  final List<double> _allSpeeds = [];

  static const int _stabilityWindow = 8;
  static const double _maxSpeed = 160;

  // Speed tuning (Google-Maps-like)
  static const double _emaAlpha = 0.35;

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

  @override
  void initState() {
    super.initState();
    _speedFilter = SimpleKalmanFilter(decisionNoise: 0.1, measurementNoise: 3.0);
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
      _speedFilter = SimpleKalmanFilter(decisionNoise: 0.1, measurementNoise: 3, estimateError: 1); // Reset filter
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
  }

  void _stopTrackingOnly() {
    _positionStream?.cancel();
    _tripTimer?.cancel();
    _positionStream = null;
    _tripTimer = null;
    setState(() => _tracking = false);
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
      });
    }
  
    _lastPosition = p;
  }

  // ---------------- SAVE TRIP ----------------

  void _saveTrip() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _tripDuration.inSeconds < 1) return;

    final avgSpeed = _allSpeeds.isEmpty
        ? 0
        : _allSpeeds.reduce((a, b) => a + b) / _allSpeeds.length;

    final maxSpeed = _allSpeeds.isEmpty ? 0 : _allSpeeds.reduce(max);

    final trip = TripModel(
      name: name,
      startTime: DateTime.now().subtract(_tripDuration),
      durationSeconds: _tripDuration.inSeconds,
      distanceKm: _distance / 1000,
      avgSpeed: avgSpeed.toDouble(),
      maxSpeed: maxSpeed.toDouble(),
      speedReadings: List<double>.from(_allSpeeds),
    );

    await Hive.box<TripModel>('trips').add(trip);
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
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _positionStream?.cancel();
    _tripTimer?.cancel();
    super.dispose();
  }

  // ---------------- BUILD ----------------

  Color _getSpeedColor(double speed) {
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
    final accentColor = _getSpeedColor(_speed);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Transform(
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
                                    color: _getSpeedColor(value).withOpacity(0.15),
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
                              accentColor: _getSpeedColor(value),
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
                                              color: _getSpeedColor(value)
                                                  .withOpacity(0.5),
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
                              color: secondaryTextColor.withOpacity(0.7),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      // HUD Scanlines Effect
                      if (_hudMode)
                        IgnorePointer(
                          child: Container(
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
                const SizedBox(height: 32),

                // GLASS BLOCKS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _glassBlock(
                          label: 'DISTANCE',
                          value: '${(_distance / 1000).toStringAsFixed(2)}',
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
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _glassBlock(
                          label: 'SIGNAL',
                          value: '±${_accuracy.toStringAsFixed(0)}',
                          unit: 'METERS',
                          icon: Icons.gps_fixed,
                          isDark: isDark,
                          accent:
                              _accuracy <= 10 ? Colors.greenAccent : Colors.orangeAccent,
                          extraChild: _PulseSignal(accuracy: _accuracy),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _actionBlock(
                          label: 'HUD MODE',
                          value: _hudMode ? 'ON' : 'OFF',
                          icon: Icons.flip,
                          isActive: _hudMode,
                          onTap: () => setState(() => _hudMode = !_hudMode),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tracking ? Colors.redAccent : Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 44, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      shadowColor: _tracking ? Colors.redAccent.withOpacity(0.5) : Colors.greenAccent.withOpacity(0.5),
                    ),
                    onPressed: _tracking
                        ? () {
                            _stopTrackingOnly();
                            _confirmSaveTrip();
                          }
                        : _startTrip,
                    child: Text(
                      _tracking ? 'END TRIP' : 'START TRIP',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
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
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ]
              : [
                  Colors.black.withOpacity(0.05),
                  Colors.black.withOpacity(0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          width: 1.5,
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
    required String label,
    required String value,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isActive
                  ? [accent.withOpacity(0.2), accent.withOpacity(0.05)]
                  : (isDark
                      ? [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05)
                        ]
                      : [
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.02)
                        ])),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            width: 1.5,
            color: isActive
                ? accent.withOpacity(0.5)
                : (isDark
                    ? Colors.white.withOpacity(0.15)
                    : Colors.black.withOpacity(0.1)),
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? accent.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
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
          color: color.withOpacity(0.15),
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
                    color: Colors.black.withOpacity(0.3),
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
                                ? Colors.white.withOpacity(0.08)
                                : Colors.black.withOpacity(0.06),
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
                      style:
                          TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Trip name',
                        hintStyle: TextStyle(
                            color: isDark ? Colors.grey : Colors.grey.shade400),
                        filled: true,
                        fillColor: isDark ? Colors.black : Colors.grey.shade200,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
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
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black12,
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
          ? Colors.white.withOpacity(0.05)
          : Colors.black.withOpacity(0.05)
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
      ..color = isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final int tickCount = 40;
    final double tickRadius = radius - strokeWidth * 1.5;
    final double totalAngle = 1.4 * pi + 1.2 * pi; // Start to end angle span

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
         accentColor.withOpacity(0.1),
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
        ..color = accentColor.withOpacity(0.3)
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

class _PulseSignal extends StatefulWidget {
  final double accuracy;
  const _PulseSignal({required this.accuracy});

  @override
  State<_PulseSignal> createState() => _PulseSignalState();
}

class _PulseSignalState extends State<_PulseSignal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGood = widget.accuracy <= 10;
    final color = isGood ? Colors.greenAccent : Colors.orangeAccent;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final lag = index * 0.2;
            final t = (_controller.value - lag).clamp(0.0, 1.0);
            final scale = (sin(t * pi * 2) + 1.2) / 2.2;
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 12 * scale * (index == 1 ? 1.5 : 1),
              decoration: BoxDecoration(
                color: color.withOpacity(0.4 + (0.6 * scale)),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

class _HUDScannerPainter extends CustomPainter {
  final Color color;
  _HUDScannerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Subtle horizontal scanlines
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Outer corner accents
    final accentPaint = Paint()
      ..color = color.withOpacity(0.3)
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
