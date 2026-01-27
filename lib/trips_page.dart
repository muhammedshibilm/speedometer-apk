import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'trip_model.dart';

class TripsPage extends StatelessWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<TripModel>('trips');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'Trips',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (_, Box<TripModel> box, __) {
          if (box.isEmpty) {
            return Center(
              child: Text(
                'No trips yet',
                style: GoogleFonts.inter(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: box.length,
            itemBuilder: (_, index) {
              // Latest trip first
              final reverseIndex = box.length - 1 - index;
              final trip = box.getAt(reverseIndex)!;

              return Dismissible(
                key: ValueKey(trip.key),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.redAccent,
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                confirmDismiss: (_) async {
                  // Soft confirmation (no dialog)
                  return true;
                },
                onDismissed: (_) async {
                  final deletedTrip = trip;
                  final deletedIndex = reverseIndex;

                  await trip.delete();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Trip deleted'),
                      action: SnackBarAction(
                        label: 'UNDO',
                        onPressed: () async {
                          await box.putAt(deletedIndex, deletedTrip);
                        },
                      ),
                    ),
                  );
                },
                child: _TripTile(trip: trip),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- TRIP TILE ----------------

class _TripTile extends StatelessWidget {
  final TripModel trip;

  const _TripTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: trip.durationSeconds);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // LEFT
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${trip.distanceKm.toStringAsFixed(2)} km',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${duration.inMinutes} min • AVG ${trip.avgSpeed.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          // RIGHT
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'MAX',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: 10,
                ),
              ),
              Text(
                trip.maxSpeed.toStringAsFixed(0),
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
