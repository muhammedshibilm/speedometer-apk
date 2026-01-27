import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({super.key});

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  StreamSubscription<Position>? _positionStream;

  double _speed = 0.0;
  double _lastSpeed = 0.0;
  double _distance = 0.0;
  double _accuracy = 999;

  final List<double> _recentSpeeds = [];
  static const int _stabilityWindow = 8;

  Position? _lastPosition;
  bool _tracking = false;

  @override
  void dispose() {
    _stopTrip();
    super.dispose();
  }

  // -------------------- TRIP CONTROL --------------------

  Future<void> _startTrip() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    setState(() {
      _tracking = true;
      _distance = 0;
      _recentSpeeds.clear();
      _lastSpeed = 0;
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen(_onPosition);
  }

  void _stopTrip() {
    _positionStream?.cancel();
    _positionStream = null;
    setState(() => _tracking = false);
  }

  // -------------------- GPS HANDLING --------------------

  void _onPosition(Position position) {
    if (position.accuracy > 30) return;

    final currentSpeed = (position.speed * 3.6).clamp(0, 200).toDouble();
    final delta = (currentSpeed - _lastSpeed).abs();

    if (delta > 20) return; // spike filter

    if (_lastPosition != null) {
      final meters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (meters < 50) {
        _distance += meters;
      }
    }

    _lastPosition = position;

    _recentSpeeds.add(currentSpeed);
    if (_recentSpeeds.length > _stabilityWindow) {
      _recentSpeeds.removeAt(0);
    }

    setState(() {
      _speed = currentSpeed;
      _lastSpeed = currentSpeed;
      _accuracy = position.accuracy;
    });
  }

  // -------------------- UI LOGIC --------------------

  Color get _speedRingColor {
    if (_speed <= 30) return Colors.green;
    if (_speed <= 70) return Colors.orange;
    return Colors.red;
  }

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

  // -------------------- BUILD --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // TOP INFO
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoBlock(
                    'DIST',
                    '${(_distance / 1000).toStringAsFixed(2)} km',
                  ),
                  _infoBlock('±', '${_accuracy.toStringAsFixed(0)} m'),
                ],
              ),
            ),

            // SPEED + RING
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: _SpeedRingPainter(_speedRingColor),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      _speed.toStringAsFixed(0),
                      style: GoogleFonts.inter(
                        fontSize: 96,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'km/h',
                      style: GoogleFonts.inter(
                        color: Colors.grey,
                        fontSize: 18,
                      ),
                    ),

                    // STABILITY BAR
                    const SizedBox(height: 10),
                    Container(
                      width: 80,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _stabilityColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // BUTTON
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _tracking ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 14,
                  ),
                ),
                onPressed: _tracking ? _stopTrip : _startTrip,
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
    );
  }

  Widget _infoBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.grey)),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// -------------------- RING PAINTER --------------------

class _SpeedRingPainter extends CustomPainter {
  final Color color;

  _SpeedRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
