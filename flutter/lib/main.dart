import 'package:flutter/material.dart';

import 'screens/scan_screen.dart';

void main() {
  runApp(const DeautherApp());
}

class DeautherApp extends StatelessWidget {
  const DeautherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32-C5 Deauther',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ScanScreen(),
    );
  }
}
