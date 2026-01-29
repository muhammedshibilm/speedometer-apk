import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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
  static const double _maxSpeedJump = 35;

  // GPS filtering thresholds
  static const double _minDistanceMeters = 5;  // ignore GPS jitter
  static const double _minSpeedKmh = 1.5;      // stationary cutoff (walking speed)


  Position? _lastPosition;
  bool _tracking = false;

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

  // Stricter accuracy threshold for better precision
  if (p.accuracy > 25) return;

  if (_lastPosition != null) {
    final distanceMeters = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      p.latitude,
      p.longitude,
    );

    final timeDiff =
        p.timestamp.difference(_lastPosition!.timestamp).inMilliseconds / 1000;

 
    if (timeDiff > 0 && distanceMeters >= _minDistanceMeters) {
      final rawSpeed = (distanceMeters / timeDiff) * 3.6;
      final clampedSpeed = rawSpeed.clamp(0, _maxSpeed);

      final delta = clampedSpeed - _speed;
      final adjustedSpeed = delta.abs() > _maxSpeedJump
          ? _speed + _maxSpeedJump * delta.sign
          : clampedSpeed;

      final smoothedSpeed = _speed == 0
          ? adjustedSpeed
          : (_emaAlpha * adjustedSpeed) + ((1 - _emaAlpha) * _speed);

   
      if (smoothedSpeed < _minSpeedKmh) {
        // Still add distance for slow movement, just set speed to 0
        _distance += distanceMeters;
        _speed = 0;
      } else {
        _speed = smoothedSpeed.toDouble();
        _distance += distanceMeters;

        _recentSpeeds.add(_speed);
        _allSpeeds.add(_speed);

        if (_recentSpeeds.length > _stabilityWindow) {
          _recentSpeeds.removeAt(0);
        }
      }

      setState(() {});
    }
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
    );

    await Hive.box<TripModel>('trips').add(trip);
  }

  // ---------------- UI HELPERS ----------------

  Color get _stabilityColor {
    if (_recentSpeeds.length < 2) return Colors.green;

    final avg = _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;
    final variance =
        _recentSpeeds.map((s) => pow(s - avg, 2)).reduce((a, b) => a + b) /
            _recentSpeeds.length;

    if (variance < 4) return Colors.green;
    if (variance < 15) return Colors.orange;
    return Colors.red;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _gpsSignalWidget(bool isDark) {
    int bars;
    Color color;

    if (_accuracy <= 8) {
      bars = 4;
      color = Colors.green;
    } else if (_accuracy <= 20) {
      bars = 3;
      color = Colors.orange;
    } else if (_accuracy <= 40) {
      bars = 2;
      color = Colors.redAccent;
    } else {
      bars = 1;
      color = Colors.red;
    }

    return Column(
      children: [
        Text('SIGNAL',
            style: GoogleFonts.inter(
                color: isDark ? Colors.grey : Colors.grey.shade600,
                fontSize: 11)),
        const SizedBox(height: 6),
        Row(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(4, (i) {
                return Container(
                  width: 4,
                  height: 6 + i * 4,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: i < bars
                        ? color
                        : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
            const SizedBox(width: 6),
            Text(
              '±${_accuracy.toStringAsFixed(0)} m',
              style: GoogleFonts.inter(
                  color: isDark ? Colors.grey : Colors.grey.shade600,
                  fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CustomPaint(
                        painter: _SegmentedArcPainter(
                          speed: _speed,
                          maxSpeed: _maxSpeed,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          _speed.toStringAsFixed(0),
                          style: GoogleFonts.inter(
                            fontSize: 88,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        Text('km/h',
                            style: GoogleFonts.inter(
                                fontSize: 16, color: secondaryTextColor)),
                        const SizedBox(height: 8),
                        Container(
                          width: 72,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _stabilityColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _infoBlock(
                            'DISTANCE',
                            '${(_distance / 1000).toStringAsFixed(2)} km',
                            isDark,
                          ),
                          _gpsSignalWidget(isDark),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          Text('TIMER',
                              style: GoogleFonts.inter(
                                  color: secondaryTextColor, fontSize: 11)),
                          const SizedBox(height: 6),
                          Text(
                            _formatDuration(_tripDuration),
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tracking ? Colors.red : Colors.green,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 44, vertical: 12),
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
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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

  Widget _infoBlock(String label, String value, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey : Colors.grey.shade600;

    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(
                color: secondaryTextColor, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
        ),
      ],
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

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(18),
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
                // Title
                Text(
                  'Save Trip',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Give your trip a name to save it',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? Colors.grey : Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 18),

                // Input
                TextField(
                  controller: _controller,
                  autofocus: true,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black),
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

                const SizedBox(height: 22),

                // Actions
                Row(
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
              ],
            ),
          ),
        ),
      );
    },
  );
}




}
// ---------------- ARC PAINTER ----------------

class _SegmentedArcPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final bool isDark;

  static const int segments = 32;
  static const double startAngle = -5 * pi / 4;
  static const double sweepAngle = 3 * pi / 2;

  _SegmentedArcPainter({
    required this.speed,
    required this.maxSpeed,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final active = ((speed / maxSpeed) * segments).round();

    for (int i = 0; i < segments; i++) {
      final t = i / segments;
      final angle = startAngle + sweepAngle * t;
      final color = i < active
          ? Color.lerp(Colors.green, Colors.red, t)!
          : (isDark ? Colors.grey.shade800 : Colors.grey.shade300);

      final paint = Paint()
        ..color = color
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;

      final p1 = Offset(
        center.dx + (radius - 12) * cos(angle),
        center.dy + (radius - 12) * sin(angle),
      );
      final p2 = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedArcPainter old) =>
      old.speed != speed || old.isDark != isDark;
}






