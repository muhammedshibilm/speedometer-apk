import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:speedy/pages/home_shell.dart';

import 'package:speedy/models/trip_model.dart';
import 'package:speedy/providers/theme_provider.dart';
import 'package:speedy/pages/tutorial_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

// New feature imports
import 'driving_behavior/behavior_event_model.dart';
import 'driving_behavior/behavior_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ads
  await MobileAds.instance.initialize();

  // Init Hive – register ALL adapters before opening boxes
  await Hive.initFlutter();
  Hive.registerAdapter(TripModelAdapter());
  Hive.registerAdapter(BehaviorEventModelAdapter());

  await Hive.openBox<TripModel>('trips');
  await Hive.openBox<BehaviorEventModel>('behavior_events');

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => BehaviorProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late ThemeProvider _themeProvider;
  bool _isLoading = true;
  bool _isFirstTime = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _checkFirstTime();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFirstTime = !(prefs.getBool('tutorial_completed') ?? false);
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Listen for system theme changes
  @override
  void didChangePlatformBrightness() {
    final brightness = MediaQuery.of(context).platformBrightness;
    _themeProvider.updateSystemTheme(brightness == Brightness.dark);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speedy',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.light().textTheme,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.black,
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
        ),
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode,
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_isFirstTime
              ? const TutorialPage(isOnboarding: true)
              : const HomeShell()),
    );
  }
}
