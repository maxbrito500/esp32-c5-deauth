import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class Settings extends ChangeNotifier {
  static const _defaultPort = 7331;

  int _apiPort = _defaultPort;
  bool _apiEnabled = true;

  int get apiPort => _apiPort;
  bool get apiEnabled => _apiEnabled;

  late final File _file;

  Settings() {
    final home = Platform.environment['HOME'] ?? '.';
    _file = File('$home/.config/deauther/settings.json');
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await _file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      _apiPort = (map['apiPort'] as int?) ?? _defaultPort;
      _apiEnabled = (map['apiEnabled'] as bool?) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
        jsonEncode({'apiPort': _apiPort, 'apiEnabled': _apiEnabled}));
  }

  Future<void> setApiPort(int port) async {
    _apiPort = port;
    notifyListeners();
    await _save();
  }

  Future<void> setApiEnabled(bool enabled) async {
    _apiEnabled = enabled;
    notifyListeners();
    await _save();
  }
}
