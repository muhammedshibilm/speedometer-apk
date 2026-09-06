import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:ignite/pages/drive_page.dart';
import 'package:ignite/pages/trips_page.dart';
import 'package:ignite/pages/settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

 
  final List<Widget> _pages = const [
    DrivePage(),
    TripsPage(),
    SettingsPage(),
  ];

 


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    if (isWide && !isIOS) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              selectedIconTheme: const IconThemeData(color: Color(0xFFFF5722)),
              unselectedIconTheme: const IconThemeData(color: Colors.grey),
              selectedLabelTextStyle: const TextStyle(
                color: Color(0xFFFF5722),
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.speed),
                  label: Text('Drive'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('Trips'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),
            ),
          ],
        ),
      );
    }

    if (isIOS) {
      return CupertinoTabScaffold(
        tabBar: CupertinoTabBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.speedometer),
              label: 'Drive',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.clock_fill),
              label: 'Trips',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.settings),
              label: 'Settings',
            ),
          ],
        ),
        tabBuilder: (context, index) {
          return CupertinoPageScaffold(
            child: _pages[index],
          );
        },
      );
    }

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        color: Theme.of(context).brightness == Brightness.dark 
            ? const Color(0xFF0A0A0C) 
            : Colors.white,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(
              context: context,
              index: 0,
              icon: Icons.speed_rounded, // or CupertinoIcons.speedometer
              label: 'DRIVE',
            ),
            _buildNavItem(
              context: context,
              index: 1,
              icon: Icons.alt_route_rounded, // or Icons.history
              label: 'TRIPS',
            ),
            _buildNavItem(
              context: context,
              index: 2,
              icon: Icons.settings_outlined,
              label: 'SETTINGS',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Ignite Speedometer active color — Flame Orange
    const activeColor = Color(0xFFFF5722);
    final inactiveColor = isDark ? Colors.white38 : Colors.black38;
    
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Indicator Line
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isSelected ? 1.0 : 0.0,
              child: Container(
                width: 40,
                height: 3,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFAB00), Color(0xFFFF5722), Color(0xFFFF2A00)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x88FF5722),
                      blurRadius: 6,
                      spreadRadius: 2,
                    )
                  ],
                ),
              ),
            ),
            Icon(
              icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
