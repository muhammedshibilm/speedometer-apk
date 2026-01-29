import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';

import 'trip_model.dart';

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

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: trip.durationSeconds);
    final date =
        DateFormat('dd MMM yyyy • hh:mm a').format(trip.startTime);

    /// simple derived min speed (you don’t store it)
    final minSpeed = (trip.avgSpeed * 0.5).clamp(0, trip.maxSpeed);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// HEADER
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trip.name.trim(),
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                date,
                style: GoogleFonts.inter(
                  color: secondaryTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          /// PRIMARY METRICS
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _bigMetric(
                icon: Icons.route,
                label: 'Distance',
                value: '${trip.distanceKm.toStringAsFixed(2)} km',
                color: Colors.blueAccent,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
              ),
              _bigMetric(
                icon: Icons.timer,
                label: 'Duration',
                value: '${duration.inMinutes} min',
                color: Colors.orangeAccent,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
              ),
            ],
          ),

          const SizedBox(height: 20),

          /// SPEED METRICS
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _smallMetric(
                icon: Icons.trending_up,
                label: 'MAX',
                value: trip.maxSpeed.toStringAsFixed(0),
                color: Colors.redAccent,
                secondaryTextColor: secondaryTextColor,
              ),
              _smallMetric(
                icon: Icons.speed,
                label: 'AVG',
                value: trip.avgSpeed.toStringAsFixed(0),
                color: Colors.greenAccent,
                secondaryTextColor: secondaryTextColor,
              ),
              _smallMetric(
                icon: Icons.trending_down,
                label: 'MIN',
                value: minSpeed.toStringAsFixed(0),
                color: Colors.blueGrey,
                secondaryTextColor: secondaryTextColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ---------------- METRIC WIDGETS ----------------

Widget _bigMetric({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
  required Color textColor,
  required Color secondaryTextColor,
}) {
  return Column(
    children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(height: 6),
      Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, color: secondaryTextColor),
      ),
    ],
  );
}

Widget _smallMetric({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
  required Color secondaryTextColor,
}) {
  return Column(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 4),
      Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.inter(fontSize: 11, color: secondaryTextColor),
      ),
    ],
  );
}
