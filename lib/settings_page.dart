import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'trip_model.dart';
import 'theme_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Gradient Background
    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black, Color(0xFF1A1A1A)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF5F5F5)],
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Settings',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _sectionHeader('DATA MANAGEMENT', isDark),
                  _glassSettingsTile(
                    context,
                    icon: Icons.delete_outline,
                    title: 'Clear Trip History',
                    subtitle: 'Delete all stored trips permanently',
                    isDestructive: true,
                    onTap: () => _showClearDialog(context, isDark, false),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),
                  _sectionHeader('APPEARANCE', isDark),
                  _glassSettingsTile(
                    context,
                    icon: Icons.palette_outlined,
                    title: 'Theme Mode',
                    subtitle: themeProvider.useSystemTheme
                        ? 'System Default'
                        : (themeProvider.isDarkMode ? 'Dark Mode' : 'Light Mode'),
                    trailing: Icon(Icons.chevron_right,
                        color: isDark ? Colors.white54 : Colors.black54),
                    onTap: () => _showThemePicker(context, themeProvider, isDark),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),
                  _sectionHeader('ABOUT', isDark),
                  _glassSettingsTile(
                    context,
                    icon: Icons.info_outline,
                    title: 'Version',
                    subtitle: '1.0.0 (Build 100)',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _sectionHeader("Privacy Policy", isDark),
                  _glassSettingsTile(
                    context,
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    subtitle: 'Read our privacy policy',
                    trailing: Icon(Icons.chevron_right,
                        color: isDark ? Colors.white54 : Colors.black54),
                    onTap: () async {
                      final uri = Uri.parse(
                          'https://speedy.muhammedshibilm.tech');

                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Make your drive smarter.',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 12,
                      ),
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

  Widget _sectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: isDark ? Colors.blueAccent : Colors.blueGrey,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _glassSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? Colors.redAccent.withValues(alpha: 0.1)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.blueAccent.withValues(alpha: 0.05)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive
                        ? Colors.redAccent
                        : (isDark ? Colors.white : Colors.blueAccent),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDestructive
                              ? Colors.redAccent
                              : (isDark ? Colors.white : Colors.black),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context, bool isDark, bool isIOS) async {
    // Reusing existing logic but with better styling if needed
    // For now, keep the dialog logic but maybe style the dialogs in a separate pass if requested.
    // The previous implementation was fine, just wrapping it here.

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear History',
            style: GoogleFonts.outfit(
                color: isDark ? Colors.white : Colors.black)),
        content: Text(
          'Are you sure you want to delete all trips? This action cannot be undone.',
          style: GoogleFonts.inter(
              color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            child: Text('CANCEL',
                style: GoogleFonts.inter(
                    color: isDark ? Colors.white54 : Colors.grey)),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('CLEAR',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final box = Hive.box<TripModel>('trips');
      await box.clear();
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Trip history cleared',
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: Colors.redAccent.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showThemePicker(
      BuildContext context, ThemeProvider themeProvider, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Theme',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            _themeOption(
                context, themeProvider, 'System Default', 'system', isDark),
            _themeOption(context, themeProvider, 'Light Mode', 'light', isDark),
            _themeOption(context, themeProvider, 'Dark Mode', 'dark', isDark),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(BuildContext context, ThemeProvider provider,
      String label, String value, bool isDark) {
    bool isSelected = false;
    if (value == 'system') isSelected = provider.useSystemTheme;
    if (value == 'light'){
      isSelected = !provider.useSystemTheme && !provider.isDarkMode;
    }
    if (value == 'dark'){
      isSelected = !provider.useSystemTheme && provider.isDarkMode;
      }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: isSelected
              ? Colors.blueAccent
              : (isDark ? Colors.white : Colors.black),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blueAccent)
          : null,
      onTap: () {
        if (value == 'system') {
          if (!provider.useSystemTheme) provider.toggleUseSystemTheme();
        } else if (value == 'light') {
          if (provider.useSystemTheme) provider.toggleUseSystemTheme();
          provider.setTheme('light');
        } else if (value == 'dark') {
          if (provider.useSystemTheme) provider.toggleUseSystemTheme();
          provider.setTheme('dark');
        }
        Navigator.pop(context);
      },
    );
  }
}
