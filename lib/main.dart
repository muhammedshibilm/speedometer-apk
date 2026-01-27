import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'home_shell.dart';
import 'trip_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ads
  await MobileAds.instance.initialize();

  // Init Hive
  await Hive.initFlutter();
  Hive.registerAdapter(TripModelAdapter());
  await Hive.openBox<TripModel>('trips');

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speedy',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: false,
      ),
      home: const HomeShell(),
    );
  }
}
