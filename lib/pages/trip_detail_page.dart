import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ignite/models/trip_model.dart';

class TripDetailPage extends StatefulWidget {
  final TripModel trip;

  const TripDetailPage({super.key, required this.trip});

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  bool _isSatellite = false;

  List<_SpeedSegment> _segments = [];
  List<LatLng> _allPoints = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _buildSegments();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Build speed-colored segments ───────────────────────────────────────────
  void _buildSegments() {
    final lats = widget.trip.latitudes;
    final lngs = widget.trip.longitudes;
    final speeds = widget.trip.speedReadings;

    if (lats.isEmpty || lngs.isEmpty) return;

    for (int i = 0; i < lats.length; i++) {
      _allPoints.add(LatLng(lats[i], lngs[i]));
    }
    if (_allPoints.length < 2) return;

    for (int i = 0; i < _allPoints.length - 1; i++) {
      double spd = 0;
      if (speeds.isNotEmpty) {
        final idx = (i * speeds.length / _allPoints.length).round();
        spd = speeds[idx.clamp(0, speeds.length - 1)];
      }
      _segments.add(_SpeedSegment(
        points: [_allPoints[i], _allPoints[i + 1]],
        color: _speedColor(spd, widget.trip.maxSpeed),
      ));
    }
  }

  Color _speedColor(double speed, double maxSpeed) {
    if (maxSpeed <= 0) return Colors.greenAccent;
    final ratio = (speed / maxSpeed).clamp(0.0, 1.0);
    if (ratio < 0.5) {
      return Color.lerp(
          const Color(0xFF00E676), const Color(0xFFFFD600), ratio * 2)!;
    } else {
      return Color.lerp(const Color(0xFFFFD600), const Color(0xFFFF1744),
          (ratio - 0.5) * 2)!;
    }
  }

  // ── Fit route to camera ────────────────────────────────────────────────────
  void _fitRoute() {
    if (_allPoints.isEmpty) return;
    double minLat = _allPoints.first.latitude;
    double maxLat = _allPoints.first.latitude;
    double minLng = _allPoints.first.longitude;
    double maxLng = _allPoints.first.longitude;
    for (final p in _allPoints) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final duration = Duration(seconds: trip.durationSeconds);
    final dateStr = DateFormat('dd MMM yyyy • hh:mm a').format(trip.startTime);
    final hasRoute = _allPoints.length >= 2;
    final tripTitle = trip.name.isNotEmpty ? trip.name : 'Untitled Trip';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── Custom AppBar ────────────────────────────────────────────────
            _buildAppBar(context, tripTitle, dateStr),

            // ── Stats row ────────────────────────────────────────────────────
            _buildStatsRow(trip, duration),

            // ── Map ──────────────────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  hasRoute ? _buildMap() : _buildNoRoute(),

                  // Layer toggle
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _mapFab(
                      icon: _isSatellite
                          ? Icons.map_outlined
                          : Icons.satellite_alt,
                      onTap: () =>
                          setState(() => _isSatellite = !_isSatellite),
                      tooltip: 'Toggle satellite',
                    ),
                  ),

                  // Fit-route
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: _mapFab(
                      icon: Icons.my_location,
                      onTap: _fitRoute,
                      tooltip: 'Fit route',
                    ),
                  ),

                  // Speed legend
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: _buildSpeedLegend(),
                  ),
                ],
              ),
            ),

            // ── Speed graph ──────────────────────────────────────────────────
            if (trip.speedReadings.isNotEmpty) _buildSpeedGraph(trip),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context, String title, String date) {
    return Container(
      color: const Color(0xFF0A0A0C),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 8,
        right: 16,
        bottom: 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Trip Path',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$title  ·  $date',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  Widget _buildStatsRow(TripModel trip, Duration duration) {
    final mm = duration.inMinutes.toString().padLeft(2, '0');
    final ss = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      color: const Color(0xFF111114),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _statChip(
            icon: Icons.route,
            label: 'DISTANCE',
            value: '${trip.distanceKm.toStringAsFixed(1)} km',
            color: const Color(0xFF00C9FF),
          ),
          _vDivider(),
          _statChip(
            icon: Icons.timer_outlined,
            label: 'DURATION',
            value: '$mm:$ss',
            color: const Color(0xFFFFB347),
          ),
          _vDivider(),
          _statChip(
            icon: Icons.speed,
            label: 'MAX SPEED',
            value: '${trip.maxSpeed.toStringAsFixed(0)} km/h',
            color: const Color(0xFFFF6B6B),
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              color: Colors.white38,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.orbitron(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() =>
      Container(height: 36, width: 1, color: Colors.white12);

  // ── Map ────────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    final startPoint = _allPoints.first;
    final endPoint = _allPoints.last;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: startPoint,
        initialZoom: 14,
        onMapReady: () =>
            Future.delayed(const Duration(milliseconds: 350), _fitRoute),
      ),
      children: [
        TileLayer(
          urlTemplate: _isSatellite
              ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'tech.muhammedshibilm.ignite',
        ),

        // Speed-colored polyline segments
        for (final seg in _segments)
          PolylineLayer(
            polylines: [
              Polyline(
                points: seg.points,
                strokeWidth: 5,
                color: seg.color,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),

        MarkerLayer(
          markers: [
            // Start – green glow circle
            Marker(
              point: startPoint,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child:
                    const Icon(Icons.circle, color: Colors.white, size: 8),
              ),
            ),
            // End – red flag circle
            Marker(
              point: endPoint,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFFFF1744).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: const Icon(Icons.flag_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoRoute() {
    return Container(
      color: const Color(0xFF111114),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, color: Colors.white24, size: 64),
            const SizedBox(height: 12),
            Text('No route data for this trip',
                style:
                    GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Map FAB button ─────────────────────────────────────────────────────────
  Widget _mapFab({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xCC1A1A1E),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // ── Speed legend ───────────────────────────────────────────────────────────
  Widget _buildSpeedLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendDot(const Color(0xFF00E676)),
          const SizedBox(width: 3),
          Text('Slow',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 10)),
          const SizedBox(width: 8),
          _legendDot(const Color(0xFFFFD600)),
          const SizedBox(width: 3),
          Text('Med',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 10)),
          const SizedBox(width: 8),
          _legendDot(const Color(0xFFFF1744)),
          const SizedBox(width: 3),
          Text('Fast',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  // ── Speed graph ────────────────────────────────────────────────────────────
  Widget _buildSpeedGraph(TripModel trip) {
    final speeds = trip.speedReadings;
    final maxSpd = speeds.reduce(math.max);
    final duration = Duration(seconds: trip.durationSeconds);
    final totalMin = duration.inMinutes.toDouble();

    final step = math.max(1, (speeds.length / 300).ceil());
    final spots = <FlSpot>[];
    for (int i = 0; i < speeds.length; i += step) {
      final t = totalMin > 0
          ? (i / speeds.length) * totalMin
          : i.toDouble();
      spots.add(FlSpot(t, speeds[i].clamp(0, double.infinity)));
    }

    final bottomInterval = totalMin <= 10
        ? 2.0
        : totalMin <= 30
            ? 5.0
            : 10.0;

    return Container(
      color: const Color(0xFF0D0D10),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.speed, color: Color(0xFFFF6B35), size: 18),
              const SizedBox(width: 8),
              Text(
                'Speed Graph',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'max ${maxSpd.toStringAsFixed(0)} km/h',
                style:
                    GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Chart
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: totalMin > 0 ? totalMin : spots.length.toDouble(),
                minY: 0,
                maxY: maxSpd * 1.15,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval:
                      (maxSpd / 3).clamp(1, double.infinity),
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: Color(0x22FFFFFF),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: bottomInterval,
                      getTitlesWidget: (value, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${value.toInt()} min',
                          style: GoogleFonts.inter(
                              color: Colors.white38, fontSize: 9),
                        ),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: const Color(0xFFFF6B35),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFFF6B35).withValues(alpha: 0.5),
                          const Color(0xFFFF6B35).withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper ─────────────────────────────────────────────────────────────────
class _SpeedSegment {
  final List<LatLng> points;
  final Color color;
  const _SpeedSegment({required this.points, required this.color});
}
