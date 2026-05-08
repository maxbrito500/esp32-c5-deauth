import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/scan_screen.dart';
import 'services/api_server.dart';
import 'services/settings.dart';

void main() {
  final settings = Settings();
  final api = ApiServer(settings);
  runApp(DeautherApp(settings: settings, api: api));
}

class DeautherApp extends StatelessWidget {
  const DeautherApp({super.key, required this.settings, required this.api});

  final Settings settings;
  final ApiServer api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        Provider.value(value: api),
      ],
      child: MaterialApp(
        title: 'ESP32-C5 Deauther',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.tealAccent,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const ScanScreen(),
      ),
    );
  }
}
