import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/scan_screen.dart';
import 'services/api_server.dart';
import 'services/settings.dart';

void main() {
  runApp(const DeautherApp());
}

class DeautherApp extends StatelessWidget {
  const DeautherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Settings()),
        ProxyProvider<Settings, ApiServer>(
          create: (ctx) => ApiServer(ctx.read<Settings>()),
          update: (_, settings, server) => server!,
          dispose: (_, server) => server.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'ESP32-C5 Deauther',
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
