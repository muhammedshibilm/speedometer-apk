// ignore: library_prefixes
import 'dart:ui' as imageUrl;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedy/models/trip_model.dart';
import 'package:speedy/driving_behavior/trip_score.dart';

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  late BannerAd _bannerAd;
  bool _isBannerLoaded = false;
  final GlobalKey _mapIconKey = GlobalKey();
  late TutorialCoachMark tutorialCoachMark;
  List<TargetFocus> targets = [];

  @override
  void initState() {
    super.initState();

    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-9959004005442539/2521212661',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();

    Future.delayed(const Duration(milliseconds: 1000), () {
      _checkAndShowTutorial();
    });
  }

  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('trips_tutorial_shown') ?? false;
    
    // Only show if there's at least one trip and tutorial not shown
    final box = Hive.box<TripModel>('trips');
    if (!shown && box.isNotEmpty) {
      _showTutorial();
      await prefs.setBool('trips_tutorial_shown', true);
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
      onFinish: () => debugPrint("Trips Tutorial Finished"),
      onClickTarget: (target) => debugPrint("Clicked target"),
    )..show(context: context);
  }

  void _initTargets() {
    targets.clear();
    targets.add(
      TargetFocus(
        identify: "map_icon",
        keyTarget: _mapIconKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "View Trip Path",
                    style: GoogleFonts.orbitron(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Tap this map icon to view your recorded trip path and locations on the map.",
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => controller.next(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("GOT IT"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<TripModel>('trips');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey : Colors.grey.shade600;
    final cardBgColor = isDark ? Colors.grey.shade900 : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Trips History',
          style: GoogleFonts.inter(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
    
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (_, Box<TripModel> box, __) {
                if (box.isEmpty) {
                  return Center(
                    child: Text(
                      'No trips yet',
                      style: GoogleFonts.inter(color: secondaryTextColor),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: box.length,
                  itemBuilder: (_, index) {
                    final reverseIndex = box.length - 1 - index;
                    final trip = box.getAt(reverseIndex)!;

                    return Dismissible(
                      key: ValueKey(trip.key),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.redAccent,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        final deletedTrip = trip;
                        final deletedKey = trip.key;

                        await box.deleteAt(reverseIndex);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: isDark
                                  ? Colors.grey.shade900
                                  : Colors.grey.shade200,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              content: Text('Trip deleted',
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black)),
                              action: SnackBarAction(
                                label: 'UNDO',
                                textColor: Colors.yellow,
                                onPressed: () async {
                                  await box.put(deletedKey, deletedTrip);
                                },
                              ),
                            ),
                          );
                        }
                      },
                      child: TripCard(
                        trip: trip,
                        isDark: isDark,
                        cardBgColor: cardBgColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                        mapIconKey: index == 0 ? _mapIconKey : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          /// BANNER AD
          if (_isBannerLoaded)
            SizedBox(
              width: _bannerAd.size.width.toDouble(),
              height: _bannerAd.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd),
            ),
        ],
      ),
    );
  }
}

/// ---------------- TRIP CARD ----------------

class TripCard extends StatefulWidget {
  final TripModel trip;
  final bool isDark;
  final Color cardBgColor;
  final Color textColor;
  final Color secondaryTextColor;
  final GlobalKey? mapIconKey;

  const TripCard({
    super.key,
    required this.trip,
    required this.isDark,
    required this.cardBgColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.mapIconKey,
  });

  @override
  State<TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<TripCard> {


  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: widget.trip.durationSeconds);
    final date =
        DateFormat('dd MMM yyyy • hh:mm a').format(widget.trip.startTime);


    // Premium Colors & Gradients
    final gradientColors = widget.isDark
        ? [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.05)]
        : [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.02)];
    
    final borderColor = widget.isDark 
        ? Colors.white.withValues(alpha: 0.15) 
        : Colors.black.withValues(alpha: 0.1);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: imageUrl.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 /// HEADER SECTION
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.route, color: Colors.blueAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.trip.name.isNotEmpty ? widget.trip.name : 'Untitled Trip',
                            style: GoogleFonts.outfit(
                              color: widget.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            date,
                            style: GoogleFonts.inter(
                              color: widget.secondaryTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: widget.mapIconKey,
                      onPressed: () => _showMapDialog(context),
                      icon: Icon(Icons.map_outlined, color: widget.isDark ? Colors.white70 : Colors.black54),
                      tooltip: 'View Map',
                    ),
                  ],
                ),

                const Divider(height: 30, thickness: 0.5),

                 /// INFO GRID
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _premiumMetric(
                      label: 'DISTANCE',
                      value: widget.trip.distanceKm.toStringAsFixed(2),
                      unit: 'km',
                      icon: Icons.map,
                      color: Colors.cyanAccent,
                    ),
                    _premiumMetric(
                      label: 'DURATION',
                      value: '${duration.inMinutes}',
                      unit: 'min',
                      icon: Icons.timer,
                      color: Colors.orangeAccent,
                    ),
                    _premiumMetric(
                      label: 'MAX SPEED',
                      value: widget.trip.maxSpeed.toStringAsFixed(0),
                      unit: 'km/h',
                      icon: Icons.speed,
                      color: Colors.redAccent,
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                
                // ── DRIVING SCORE & BEHAVIOR ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DRIVE SCORE',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: widget.secondaryTextColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${widget.trip.driveScore}',
                                style: GoogleFonts.orbitron(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _getScoreColor(widget.trip.driveScore),
                                ),
                              ),
                              Text(
                                ' / 100',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: widget.secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            TripScore.label(widget.trip.driveScore),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getScoreColor(widget.trip.driveScore),
                            ),
                          ),
                        ],
                      ),
                      
                      // Mini stats
                      Row(
                        children: [
                          _miniStat(Icons.warning_amber_rounded, widget.trip.harshBrakeCount, Colors.redAccent),
                          const SizedBox(width: 12),
                          _miniStat(Icons.speed, widget.trip.harshAccelCount, Colors.orangeAccent),
                          const SizedBox(width: 12),
                          _miniStat(Icons.turn_right_rounded, widget.trip.sharpCornerCount, Colors.blueAccent),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _premiumMetric({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: widget.secondaryTextColor.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: widget.secondaryTextColor.withValues(alpha: 0.7),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: GoogleFonts.orbitron(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.textColor,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    final sc = TripScore.scoreColor(score);
    return Color.fromARGB(255, sc.r, sc.g, sc.b);
  }

  Widget _miniStat(IconData icon, int count, Color color) {
    final active = count > 0;
    return Column(
      children: [
        Icon(icon, size: 16, color: active ? color : widget.secondaryTextColor.withValues(alpha: 0.5)),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? widget.textColor : widget.secondaryTextColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  void _showMapDialog(BuildContext context) {
    if (widget.trip.latitudes.isEmpty || widget.trip.longitudes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location data available for this trip')),
      );
      return;
    }

    final points = <LatLng>[];
    for (int i = 0; i < widget.trip.latitudes.length; i++) {
        points.add(LatLng(widget.trip.latitudes[i], widget.trip.longitudes[i]));
    }

    if (points.isEmpty) return;

    final startPoint = points.first;
    final endPoint = points.last;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: widget.isDark ? Colors.grey.shade900 : Colors.white,
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text(
                'Trip Path',
                style: GoogleFonts.inter(color: widget.textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))
            ],
          ),
          content: SizedBox(
            height: 400,
            width: double.maxFinite,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: startPoint,
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.speedy',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        strokeWidth: 4,
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: startPoint,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.green, size: 30),
                      ),
                      Marker(
                        point: endPoint,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.flag, color: Colors.red, size: 30),
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

