// ignore: library_prefixes
import 'dart:ui' as imageUrl;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:ignite/models/trip_model.dart';
import 'package:ignite/driving_behavior/trip_score.dart';
import 'package:ignite/pages/trip_detail_page.dart';

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  late BannerAd _bannerAd;
  bool _isBannerLoaded = false;

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

class TripCard extends StatelessWidget {
  final TripModel trip;
  final bool isDark;
  final Color cardBgColor;
  final Color textColor;
  final Color secondaryTextColor;

  const TripCard({
    super.key,
    required this.trip,
    required this.isDark,
    required this.cardBgColor,
    required this.textColor,
    required this.secondaryTextColor,
  });

  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: trip.durationSeconds);
    final date = DateFormat('dd MMM yyyy • hh:mm a').format(trip.startTime);

    final gradientColors = isDark
        ? [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.05),
          ]
        : [
            Colors.black.withValues(alpha: 0.05),
            Colors.black.withValues(alpha: 0.02),
          ];

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.10);

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
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
                          color: Colors.orangeAccent.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.route,
                            color: Colors.orangeAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip.name.isNotEmpty
                                  ? trip.name
                                  : 'Untitled Trip',
                              style: GoogleFonts.outfit(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              date,
                              style: GoogleFonts.inter(
                                color: secondaryTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // "Tap to open" indicator
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? Colors.white38 : Colors.black26,
                        size: 24,
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
                        value: trip.distanceKm.toStringAsFixed(2),
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
                        value: trip.maxSpeed.toStringAsFixed(0),
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
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
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
                                color: secondaryTextColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '${trip.driveScore}',
                                  style: GoogleFonts.orbitron(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: _getScoreColor(trip.driveScore),
                                  ),
                                ),
                                Text(
                                  ' / 100',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              TripScore.label(trip.driveScore),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _getScoreColor(trip.driveScore),
                              ),
                            ),
                          ],
                        ),

                        // Mini stats
                        Row(
                          children: [
                            _miniStat(Icons.warning_amber_rounded,
                                trip.harshBrakeCount, Colors.redAccent),
                            const SizedBox(width: 12),
                            _miniStat(Icons.speed, trip.harshAccelCount,
                                Colors.orangeAccent),
                            const SizedBox(width: 12),
                            _miniStat(Icons.turn_right_rounded,
                                trip.sharpCornerCount, Colors.blueAccent),
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
            Icon(icon,
                size: 14,
                color: secondaryTextColor.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: secondaryTextColor.withValues(alpha: 0.7),
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
                  color: textColor,
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
        Icon(icon,
            size: 16,
            color: active
                ? color
                : secondaryTextColor.withValues(alpha: 0.5)),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active
                ? textColor
                : secondaryTextColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
