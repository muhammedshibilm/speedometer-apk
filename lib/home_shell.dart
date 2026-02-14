import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'drive_page.dart';
import 'trips_page.dart';
import 'settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  InterstitialAd? _exitAd;
  bool _exitAdShown = false;

  final List<Widget> _pages = const [
    DrivePage(),
    TripsPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _loadExitAd();
  }

  // adUnitId: 'ca-app-pub-9959004005442539~1964369963',

  void _loadExitAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-9959004005442539/4910097509',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _exitAd = ad;
          _exitAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              // Exit the app when ad is dismissed
              SystemNavigator.pop();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              // Exit the app if ad fails to show
              SystemNavigator.pop();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _exitAd = null;
        },
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_exitAd != null && !_exitAdShown) {
      _exitAdShown = true;
      _exitAd!.show();
      _exitAd = null;
      return false; // prevent immediate exit, wait for callback
    }
    // If no ad, or ad already shown, just exit
    return true; 
  }

  @override
  void dispose() {
    _exitAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

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

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.speed),
              label: 'Drive',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Trips',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
