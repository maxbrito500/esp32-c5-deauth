import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nus_client.dart';

class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key, required this.connection});

  final NusConnection connection;

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final StringBuffer _log = StringBuffer();
  StreamSubscription<String>? _sub;
  bool _busy = false;

  // Quick-command palette mirroring the firmware's CLI verbs.
  static const List<String> _quickCmds = [
    'help',
    'status',
    'scan',
    'ls',
    'stas',
    'mode broadcast',
    'mode unicast',
    'mode disassoc',
    'mode authflood',
    'stop',
    'clear',
    'wl ls',
    'bl ls',
    'reset',
  ];

  @override
  void initState() {
    super.initState();
    _sub = widget.connection.incoming.listen((chunk) {
      if (chunk.isEmpty) return;
      _append(chunk);
    });
    // Greet so the device speaks first.
    Future.microtask(() => _send('help'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.connection.disconnect();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _append(String s) {
    setState(() => _log.write(s));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String cmd) async {
    cmd = cmd.trim();
    if (cmd.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      _append('> $cmd\n');
      await widget.connection.send(cmd);
      _input.clear();
    } catch (e) {
      _append('[send failed: $e]\n');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDisconnect() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect?'),
        content: Text('Disconnect from ${widget.connection.device.platformName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDisconnect() && mounted) {
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.connection.device.platformName.isNotEmpty
              ? widget.connection.device.platformName
              : 'Connected'),
          actions: [
            IconButton(
              tooltip: 'Clear log',
              icon: const Icon(Icons.clear_all),
              onPressed: () => setState(_log.clear),
            ),
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await _confirmDisconnect() && mounted) {
                  nav.pop();
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _logView()),
              _quickBar(),
              const Divider(height: 1),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logView() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          child: SelectableText(
            _log.toString(),
            style: const TextStyle(
              color: Color(0xFF8FFF8F),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickBar() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _quickCmds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final cmd = _quickCmds[i];
          return ActionChip(
            label: Text(cmd),
            onPressed: () => _send(cmd),
          );
        },
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'type a command (e.g. scan, t24 0, start 30)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _busy ? null : () => _send(_input.text),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
