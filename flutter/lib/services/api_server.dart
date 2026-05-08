import 'dart:convert';
import 'dart:io';

import 'device_controller.dart';
import 'settings.dart';

class ApiServer {
  ApiServer(this._settings) {
    _settings.addListener(_onSettingsChanged);
    // Apply persisted settings once the async load resolves.
    Future.microtask(() {
      if (_settings.apiEnabled) start(_settings.apiPort);
    });
  }

  final Settings _settings;
  DeviceController? _ctrl;
  HttpServer? _server;

  bool get isRunning => _server != null;
  int get port => _settings.apiPort;

  void attach(DeviceController ctrl) => _ctrl = ctrl;
  void detach() => _ctrl = null;

  Future<void> start(int port) async {
    await stop();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _onSettingsChanged() {
    if (_settings.apiEnabled) {
      start(_settings.apiPort);
    } else {
      stop();
    }
  }

  Future<void> _handle(HttpRequest req) async {
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('Access-Control-Allow-Origin', '*');

    final ctrl = _ctrl;
    final path = req.uri.path;
    final method = req.method;

    try {
      if (path == '/' && method == 'GET') {
        _ok(req, {'status': 'ok', 'connected': ctrl != null});
        return;
      }
      if (ctrl == null) {
        _err(req, 503, 'no device connected');
        return;
      }
      switch ('$method $path') {
        case 'GET /device':
          _ok(req, _deviceJson(ctrl));
        case 'GET /aps':
          _ok(req, {
            'aps': ctrl.aps
                .map((a) => {
                      'idx': a.idx,
                      'channel': a.channel,
                      'band': a.is5ghz ? '5GHz' : '2.4GHz',
                      'rssi': a.rssi,
                      'bssid': a.bssid,
                      'ssid': a.ssid,
                    })
                .toList()
          });
        case 'GET /log':
          _ok(req, {'log': ctrl.rawLog});
        case 'POST /scan':
          await ctrl.scanWifi();
          _ok(req, {'ok': true});
        case 'POST /attack/start':
          final body = jsonDecode(await _readBody(req)) as Map<String, dynamic>;
          await ctrl.startAttack((body['secs'] as int?) ?? 30);
          _ok(req, {'ok': true});
        case 'POST /attack/stop':
          await ctrl.stopAttack();
          _ok(req, {'ok': true});
        case 'POST /cmd':
          final body = jsonDecode(await _readBody(req)) as Map<String, dynamic>;
          final cmd = body['cmd'] as String?;
          if (cmd == null || cmd.isEmpty) {
            _err(req, 400, 'missing cmd');
          } else {
            await ctrl.conn.send(cmd);
            _ok(req, {'ok': true});
          }
        default:
          _err(req, 404, 'not found');
      }
    } catch (e) {
      _err(req, 500, '$e');
    }
  }

  Map<String, dynamic> _deviceJson(DeviceController ctrl) => {
        'connected': true,
        'attacking': ctrl.attacking,
        'attackMode': ctrl.attackMode,
        'scanning': ctrl.scanning,
        'selected24': ctrl.selected24Idx,
        'selected5': ctrl.selected5Idx,
        'apCount': ctrl.aps.length,
      };

  Future<String> _readBody(HttpRequest req) async {
    final bytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
    return utf8.decode(bytes);
  }

  void _ok(HttpRequest req, Map<String, dynamic> data) {
    req.response
      ..statusCode = 200
      ..write(jsonEncode(data));
    req.response.close();
  }

  void _err(HttpRequest req, int code, String msg) {
    req.response
      ..statusCode = code
      ..write(jsonEncode({'error': msg}));
    req.response.close();
  }

  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    stop();
  }
}
