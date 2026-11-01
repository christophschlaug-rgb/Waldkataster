import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Der Kompass ist auf Hochformat ausgelegt.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const WaldkatasterApp());
}

class WaldkatasterApp extends StatelessWidget {
  const WaldkatasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waldkataster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5A38), // Waldgrün
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
