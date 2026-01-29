import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'trip_model.dart';
import 'theme_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Settings',
          style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
              ),
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
                SnackBar(
                  content: Text('Trip history cleared',
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black)),
                  backgroundColor: isDark
                      ? Colors.grey.shade900
                      : Colors.grey.shade200,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              );
            },
          ),
          const Divider(color: Colors.grey),
          _sectionTitle('THEME'),
          ListTile(
            title: Text(
              'Theme Mode',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              'Choose your preferred theme',
              style: GoogleFonts.inter(color: Colors.grey),
            ),
            trailing: DropdownButton<String>(
              value: themeProvider.useSystemTheme
                  ? 'system'
                  : (themeProvider.isDarkMode ? 'dark' : 'light'),
              underline: const SizedBox(),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text('System',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black,
                      )),
                ),
                DropdownMenuItem(
                  value: 'light',
                  child: Text('Light',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black,
                      )),
                ),
                DropdownMenuItem(
                  value: 'dark',
                  child: Text('Dark',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black,
                      )),
                ),
              ],
              onChanged: (value) {
                if (value == 'system') {
                  if (!themeProvider.useSystemTheme) {
                    themeProvider.toggleUseSystemTheme();
                  }
                } else if (value == 'light') {
                  if (themeProvider.useSystemTheme) {
                    themeProvider.toggleUseSystemTheme();
                  }
                  themeProvider.setTheme('light');
                } else if (value == 'dark') {
                  if (themeProvider.useSystemTheme) {
                    themeProvider.toggleUseSystemTheme();
                  }
                  themeProvider.setTheme('dark');
                }
              },
            ),
          ),
          const Divider(color: Colors.grey),
          _sectionTitle('ABOUT'),
          ListTile(
            title: Text(
              'Speedometer',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              'Offline GPS speed tracking',
              style: GoogleFonts.inter(color: Colors.grey),
            ),
          ),
          ListTile(
            title: Text(
              'Version',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
              ),
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
