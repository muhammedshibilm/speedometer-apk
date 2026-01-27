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
  double _lastSpeed = 0;
  double _distance = 0;
  double _accuracy = 999;

  Duration _tripDuration = Duration.zero;

  final List<double> _recentSpeeds = [];
  static const int _stabilityWindow = 8;
  static const double _maxSpeed = 160;

  Position? _lastPosition;
  bool _tracking = false;

  // ---------------- TRIP CONTROL ----------------

  Future<void> _startTrip() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;

    setState(() {
      _tracking = true;
      _speed = 0;
      _lastSpeed = 0;
      _distance = 0;
      _accuracy = 999;
      _tripDuration = Duration.zero;
      _recentSpeeds.clear();
      _lastPosition = null;
    });

    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_tracking) {
        setState(() {
          _tripDuration += const Duration(seconds: 1);
        });
      }
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen(_onPosition);
  }

  void _stopTrackingOnly() {
    _positionStream?.cancel();
    _tripTimer?.cancel();
    _positionStream = null;
    _tripTimer = null;

    setState(() {
      _tracking = false;
    });
  }

  // ---------------- GPS ----------------

  void _onPosition(Position p) {
    if (p.accuracy > 40) return;

    final speed = (p.speed * 3.6).clamp(0, _maxSpeed).toDouble();
    if ((speed - _lastSpeed).abs() > 20) return;

    if (_lastPosition != null) {
      final meters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        p.latitude,
        p.longitude,
      );
      if (meters < 50) _distance += meters;
    }

    _lastPosition = p;

    _recentSpeeds.add(speed);
    if (_recentSpeeds.length > _stabilityWindow) {
      _recentSpeeds.removeAt(0);
    }

    setState(() {
      _speed = speed;
      _lastSpeed = speed;
      _accuracy = p.accuracy;
    });
  }

  // ---------------- SAVE TRIP ----------------

  void _saveTrip() async {
    if (_tripDuration.inSeconds < 5 || _distance < 10) return;

    final avgSpeed = _recentSpeeds.isEmpty
        ? 0.0
        : _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;

    final maxSpeed =
        _recentSpeeds.isEmpty ? 0.0 : _recentSpeeds.reduce(max).toDouble();

    final trip = TripModel(
      startTime: DateTime.now().subtract(_tripDuration),
      durationSeconds: _tripDuration.inSeconds,
      distanceKm: _distance / 1000,
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
    );

    final box = Hive.box<TripModel>('trips');
    await box.add(trip);
  }

  Future<void> _confirmSaveTrip() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Save this trip?',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    _saveTrip();
                    Navigator.pop(context);
                  },
                  child: const Text('SAVE TRIP'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    'DISCARD',
                    style: GoogleFonts.inter(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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

  Widget _gpsSignalWidget() {
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

    return Row(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            return Container(
              width: 4,
              height: 6 + i * 4,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < bars ? color : Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(width: 6),
        Text(
          '±${_accuracy.toStringAsFixed(0)} m',
          style: GoogleFonts.inter(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // TOP
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoBlock(
                    'DIST',
                    '${(_distance / 1000).toStringAsFixed(2)} km',
                  ),
                  _gpsSignalWidget()
                ],
              ),
            ),

            // SPEED
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
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'km/h',
                      style: GoogleFonts.inter(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
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

            // TIMER + BUTTON
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  Text(
                    _formatDuration(_tripDuration),
                    style: GoogleFonts.inter(
                      color: Colors.grey,
                      fontSize: 14,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _tracking ? Colors.red : Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 44,
                          vertical: 12,
                        )),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.grey, fontSize: 11)),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// ---------------- SEGMENTED ARC ----------------

class _SegmentedArcPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  static const int segments = 32;
  static const double startAngle = -5 * pi / 4;
  static const double sweepAngle = 3 * pi / 2;

  _SegmentedArcPainter({required this.speed, required this.maxSpeed});

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
          : Colors.grey.shade800;

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
  bool shouldRepaint(covariant _SegmentedArcPainter old) => old.speed != speed;
}
