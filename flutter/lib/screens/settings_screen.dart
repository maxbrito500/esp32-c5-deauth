import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_server.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _portCtrl;

  @override
  void initState() {
    super.initState();
    _portCtrl =
        TextEditingController(text: '${context.read<Settings>().apiPort}');
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyPort() async {
    final settings = context.read<Settings>();
    final api = context.read<ApiServer>();
    final port = int.tryParse(_portCtrl.text);
    if (port == null || port < 1024 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be 1024–65535')),
      );
      return;
    }
    await settings.setApiPort(port);
    if (settings.apiEnabled) await api.start(port);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final api = context.read<ApiServer>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── API server ─────────────────────────────────────────────
          const Text('HTTP API',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable API server'),
            subtitle: Text(settings.apiEnabled
                ? 'Listening on 127.0.0.1:${settings.apiPort}'
                : 'Disabled'),
            value: settings.apiEnabled,
            onChanged: (v) async {
              await settings.setApiEnabled(v);
              if (v) {
                await api.start(settings.apiPort);
              } else {
                await api.stop();
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portCtrl,
                  enabled: !settings.apiEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    helperText: 'Disable the server to change the port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: settings.apiEnabled ? null : _applyPort,
                child: const Text('Apply'),
              ),
            ],
          ),

          // ── Endpoint reference ──────────────────────────────────────
          if (settings.apiEnabled) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Endpoints',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ep('GET', '/', 'Health check / connected status'),
            _ep('GET', '/device', 'Full device state (JSON)'),
            _ep('GET', '/aps', 'Scanned access points'),
            _ep('GET', '/log', 'Raw firmware log'),
            _ep('POST', '/scan', 'Start Wi-Fi scan'),
            _ep('POST', '/attack/start', 'Body: {"secs": 30}'),
            _ep('POST', '/attack/stop', 'Stop current attack'),
            _ep('POST', '/cmd', 'Body: {"cmd": "help"}'),
          ],
        ],
      ),
    );
  }

  Widget _ep(String method, String path, String desc) {
    final color = method == 'GET' ? Colors.teal : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withAlpha(120)),
          ),
          child: Text(method,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Text(path,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(desc,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 12))),
      ]),
    );
  }
}
