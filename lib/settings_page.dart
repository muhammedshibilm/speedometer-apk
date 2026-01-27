import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'trip_model.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'Settings',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        children: [
          _sectionTitle('DATA'),
          ListTile(
            title: Text(
              'Clear trip history',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            subtitle: Text(
              'Delete all stored trips',
              style: GoogleFonts.inter(color: Colors.grey),
            ),
            trailing: const Icon(Icons.delete, color: Colors.redAccent),
            onTap: () async {
              final box = Hive.box<TripModel>('trips');
              await box.clear();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trip history cleared')),
              );
            },
          ),
          const Divider(color: Colors.grey),
          _sectionTitle('ABOUT'),
          ListTile(
            title: Text(
              'Speedometer',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            subtitle: Text(
              'Offline GPS speed tracking',
              style: GoogleFonts.inter(color: Colors.grey),
            ),
          ),
          ListTile(
            title: Text(
              'Version',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            subtitle: Text(
              '1.0.0',
              style: GoogleFonts.inter(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.grey,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
