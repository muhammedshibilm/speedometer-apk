// ignore: library_prefixes
import 'dart:ui' as imageUrl;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart' as fl_chart;

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

class TripCard extends StatefulWidget {
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
  State<TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<TripCard> {
  String _selectedGraph = 'speed';

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
                      child: const Icon(Icons.directions_car, color: Colors.blueAccent, size: 20),
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
                      onPressed: () => _showGraphDialog(context),
                      icon: Icon(Icons.show_chart, color: widget.isDark ? Colors.white70 : Colors.black54),
                      tooltip: 'View Graph',
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

  void _showGraphDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor:
                  widget.isDark ? Colors.grey.shade900 : Colors.white,
              title: Text(
                'Trip Graph',
                style: GoogleFonts.inter(color: widget.textColor),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /// Graph Type Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: widget.isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedGraph,
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor:
                            widget.isDark ? Colors.grey.shade800 : Colors.white,
                        items: [
                          DropdownMenuItem(
                            value: 'speed',
                            child: Text(
                              'Speed Over Time',
                              style: GoogleFonts.inter(
                                color: widget.textColor,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'speedavg',
                            child: Text(
                              'Speed vs Average',
                              style: GoogleFonts.inter(
                                color: widget.textColor,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setStateDialog(() {
                            _selectedGraph = val ?? 'speed';
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    /// Graph Display
                    SizedBox(
                      height: 300,
                      width: 350,
                      child: _buildGraph(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGraph() {
    if (widget.trip.speedReadings.isEmpty) {
      return Center(
        child: Text(
          'No speed data available',
          style: GoogleFonts.inter(color: widget.secondaryTextColor),
        ),
      );
    }

    if (_selectedGraph == 'speed') {
      return _buildSpeedGraph();
    } else {
      return _buildSpeedVsAverageGraph();
    }
  }

  Widget _buildSpeedGraph() {
    final speeds = widget.trip.speedReadings;
    final maxSpeed = widget.trip.maxSpeed;

    List<fl_chart.FlSpot> spots = [];
    for (int i = 0; i < speeds.length; i++) {
      spots.add(fl_chart.FlSpot(i.toDouble(), speeds[i]));
    }

    return fl_chart.LineChart(
      fl_chart.LineChartData(
        gridData: fl_chart.FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxSpeed / 4,
          getDrawingHorizontalLine: (value) {
            return fl_chart.FlLine(
              color: widget.isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              strokeWidth: 0.5,
            );
          },
        ),
        titlesData: fl_chart.FlTitlesData(
          show: true,
          rightTitles: fl_chart.AxisTitles(sideTitles: fl_chart.SideTitles(showTitles: false)),
          topTitles: fl_chart.AxisTitles(sideTitles: fl_chart.SideTitles(showTitles: false)),
          leftTitles: fl_chart.AxisTitles(
            sideTitles: fl_chart.SideTitles(
              showTitles: true,
              interval: maxSpeed / 4,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: widget.secondaryTextColor,
                  ),
                );
              },
            ),
          ),
          bottomTitles: fl_chart.AxisTitles(
            sideTitles: fl_chart.SideTitles(
              showTitles: true,
              interval: (speeds.length / 4).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: widget.secondaryTextColor,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: fl_chart.FlBorderData(show: true),
        lineBarsData: [
          fl_chart.LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 2,
            belowBarData: fl_chart.BarAreaData(
              show: true,
              color: Colors.blueAccent.withValues(alpha: 0.3),
            ),
            dotData: fl_chart.FlDotData(show: false),
          ),
        ],
        minY: 0,
        maxY: maxSpeed,
      ),
    );
  }

  Widget _buildSpeedVsAverageGraph() {
    final speeds = widget.trip.speedReadings;
    final avgSpeed = widget.trip.avgSpeed;
    final maxSpeed = widget.trip.maxSpeed;

    List<fl_chart.FlSpot> speedSpots = [];
    List<fl_chart.FlSpot> avgSpots = [];

    for (int i = 0; i < speeds.length; i++) {
      speedSpots.add(fl_chart.FlSpot(i.toDouble(), speeds[i]));
      avgSpots.add(fl_chart.FlSpot(i.toDouble(), avgSpeed));
    }

    return fl_chart.LineChart(
      fl_chart.LineChartData(
        gridData: fl_chart.FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxSpeed / 4,
          getDrawingHorizontalLine: (value) {
            return fl_chart.FlLine(
              color: widget.isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              strokeWidth: 0.5,
            );
          },
        ),
        titlesData: fl_chart.FlTitlesData(
          show: true,
          rightTitles: fl_chart.AxisTitles(sideTitles: fl_chart.SideTitles(showTitles: false)),
          topTitles: fl_chart.AxisTitles(sideTitles: fl_chart.SideTitles(showTitles: false)),
          leftTitles: fl_chart.AxisTitles(
            sideTitles: fl_chart.SideTitles(
              showTitles: true,
              interval: maxSpeed / 4,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: widget.secondaryTextColor,
                  ),
                );
              },
            ),
          ),
          bottomTitles: fl_chart.AxisTitles(
            sideTitles: fl_chart.SideTitles(
              showTitles: true,
              interval: (speeds.length / 4).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: widget.secondaryTextColor,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: fl_chart.FlBorderData(show: true),
        lineBarsData: [
          fl_chart.LineChartBarData(
            spots: speedSpots,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 2,
            belowBarData: fl_chart.BarAreaData(
              show: true,
              color: Colors.blueAccent.withValues(alpha: 0.2),
            ),
            dotData: fl_chart.FlDotData(show: false),
          ),
          fl_chart.LineChartBarData(
            spots: avgSpots,
            isCurved: false,
            color: Colors.orangeAccent,
            barWidth: 2,
            dotData: fl_chart.FlDotData(show: false),
          ),
        ],
        minY: 0,
        maxY: maxSpeed,
      ),
    );
  }
}

