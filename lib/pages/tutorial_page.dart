import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ignite/pages/home_shell.dart';

class TutorialPage extends StatefulWidget {
  final bool isOnboarding;
  const TutorialPage({super.key, this.isOnboarding = false});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  Future<void> _completeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_completed', true);
    
    if (widget.isOnboarding && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeShell()),
      );
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  final List<TutorialStep> _steps = [
    TutorialStep(
      title: 'Welcome to Ignite Speedometer',
      description: 'Your premium companion for every journey. Track your speed with unmatched precision and style.',
      icon: Icons.speed_rounded,
      color: const Color(0xFFFF5722),
    ),
    TutorialStep(
      title: 'Real-time Precision',
      description: 'Using advanced GPS filtering, we provide smooth and accurate speed readings even at low speeds.',
      icon: Icons.gps_fixed_rounded,
      color: Colors.cyanAccent,
    ),
    TutorialStep(
      title: 'HUD Mode',
      description: 'Driving at night? Use HUD mode to mirror the display and project it onto your windshield.',
      icon: Icons.flip_rounded,
      color: Colors.orangeAccent,
    ),
    TutorialStep(
      title: 'Smart Alerts',
      description: 'Set your speed limit and get instant vibration or sound alerts when you exceed it.',
      icon: Icons.notification_important_rounded,
      color: Colors.redAccent,
    ),
    TutorialStep(
      title: 'Trip History',
      description: 'Automatically save your routes, duration, and speed metrics. Review your performance anytime.',
      icon: Icons.history_rounded,
      color: Colors.greenAccent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _currentPage = page;
              });
            },
            itemCount: _steps.length,
            itemBuilder: (context, index) {
              return _buildPage(_steps[index], isDark);
            },
          ),
          
          // Navigation controls
          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Dots indicator
                Row(
                  children: List.generate(
                    _steps.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index 
                            ? _steps[_currentPage].color 
                            : (isDark ? Colors.white24 : Colors.black12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                
                // Next / Finish Button
                ElevatedButton(
                  onPressed: () {
                    if (_currentPage < _steps.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      _completeTutorial();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _steps[_currentPage].color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: Text(
                    _currentPage == _steps.length - 1 ? 'GET STARTED' : 'NEXT',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Skip button
          Positioned(
            top: 50,
            right: 20,
            child: TextButton(
              onPressed: _completeTutorial,
              child: Text(
                'SKIP',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(TutorialStep step, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with glow
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: step.color.withValues(alpha: 0.1),
              boxShadow: [
                BoxShadow(
                  color: step.color.withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Icon(
              step.icon,
              size: 100,
              color: step.color,
            ),
          ),
          const SizedBox(height: 60),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.orbitron(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
