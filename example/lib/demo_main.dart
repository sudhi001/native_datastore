// Self-driving demo entrypoint used to record doc/assets/secure-demo.gif.
//
// It performs REAL SecureDatastore operations (configure, set, get, clear)
// against the platform Keychain / AndroidKeyStore and auto-plays them through a
// Secure-tab-styled screen at a watchable pace, looping. Launch it and screen
// record the device:
//
//   flutter run -t lib/demo_main.dart -d <device-id>
//
// See tool/record_secure_demo.sh for the full mov -> gif pipeline.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_datastore/native_datastore.dart';

void main() {
  runApp(const _DemoApp());
}

class _DemoApp extends StatelessWidget {
  const _DemoApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const _SecureDemo(),
    );
  }
}

class _SecureDemo extends StatefulWidget {
  const _SecureDemo();
  @override
  State<_SecureDemo> createState() => _SecureDemoState();
}

class _SecureDemoState extends State<_SecureDemo> {
  final _secure = SecureDatastore();

  bool _multiProcess = false;
  String _typedKey = '';
  String _status = 'SecureDatastore — encrypted at rest';
  String? _activeButton;
  List<String> _keys = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _beat([int ms = 1200]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _refresh() async {
    final k = await _secure.getKeys();
    if (mounted) setState(() => _keys = k..sort());
  }

  Future<void> _run() async {
    // Loop the walkthrough so a screen recording always catches a full cycle.
    while (mounted) {
      await _secure.clear();
      setState(() {
        _multiProcess = false;
        _typedKey = '';
        _activeButton = null;
        _keys = const [];
        _status = 'SecureDatastore — encrypted at rest';
      });
      await _beat(1400);

      // 1) Turn on multi-process access.
      setState(() => _status = 'configure(multiProcess: true)');
      await _secure.configure(multiProcess: true);
      if (mounted) setState(() => _multiProcess = true);
      await _beat();

      // 2) Save a set of sample secrets.
      setState(() {
        _activeButton = 'sample';
        _status = 'Encrypting & storing 3 secrets…';
      });
      await _secure.setString(
        'refresh_token',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo.sig',
      );
      await _secure.setString('api_secret', 'sk_live_demo_abc123');
      await _secure.setBytes(
        'symmetric_key',
        Uint8List.fromList(List.generate(32, (i) => i)),
      );
      await _refresh();
      await _beat(1300);

      // 3) Type and store one more secret.
      setState(() {
        _activeButton = null;
        _status = 'Add another secret';
      });
      for (final ch in 'session_id'.split('')) {
        if (!mounted) return;
        setState(() => _typedKey += ch);
        await _beat(70);
      }
      await _beat(400);
      setState(() {
        _activeButton = 'set';
        _status = "setString('session_id', …)";
      });
      await _secure.setString('session_id', 'sess_9f3ac107e2');
      await _refresh();
      await _beat(1300);

      // 4) Emphasise: stored keys, values encrypted at rest.
      setState(() {
        _activeButton = 'refresh';
        _typedKey = '';
        _status = 'Keys stored — values encrypted at rest';
      });
      await _refresh();
      await _beat(1900);

      // 5) Clear everything.
      setState(() {
        _activeButton = 'clear';
        _status = 'clear() — wipes every secret';
      });
      await _secure.clear();
      await _refresh();
      await _beat(1700);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Storage')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: cs.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'iOS Keychain · Android Keystore + AES-256-GCM',
                      style: TextStyle(
                        color: cs.onSecondaryContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.dynamic_feed_outlined),
              title: const Text('Multi-process access'),
              subtitle: Text(
                _multiProcess
                    ? 'ON — Android uses a separate MultiProcessDataStore'
                    : 'OFF — default single-process store',
                style: const TextStyle(fontSize: 12),
              ),
              value: _multiProcess,
              onChanged: (_) {},
            ),
            const SizedBox(height: 4),
            // Status chip.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Container(
                key: ValueKey(_status),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Faux key/value inputs.
            _fakeField('Key', _typedKey.isEmpty ? null : _typedKey),
            const SizedBox(height: 8),
            _fakeField(
              'Value',
              _typedKey.isEmpty ? null : 'sess_9f3ac107e2',
              obscure: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _btn('set', 'Set String', filled: true),
                _btn('refresh', 'Refresh Keys'),
                _btn('clear', 'Clear All'),
                _btn('sample', 'Save Sample Secrets', filled: true),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Stored Secure Keys:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _keys.isEmpty
                    ? Text(
                        'Secure store is empty',
                        style: TextStyle(color: cs.outline),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'values are encrypted at rest:',
                            style: TextStyle(color: cs.outline, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          for (final k in _keys)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.vpn_key,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    k,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(Icons.lock, size: 14, color: cs.outline),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fakeField(String label, String? value, {bool obscure = false}) {
    final cs = Theme.of(context).colorScheme;
    final shown = value == null ? '' : (obscure ? '•' * value.length : value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text('$label   ', style: TextStyle(color: cs.outline, fontSize: 13)),
          Text(shown, style: const TextStyle(fontSize: 14)),
          if (value != null)
            Container(
              width: 2,
              height: 16,
              margin: const EdgeInsets.only(left: 1),
              color: cs.primary,
            ),
        ],
      ),
    );
  }

  Widget _btn(String id, String label, {bool filled = false}) {
    final active = _activeButton == id;
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: active
                ? Theme.of(context).colorScheme.tertiary
                : null,
          )
        : OutlinedButton.styleFrom(
            side: active
                ? BorderSide(
                    color: Theme.of(context).colorScheme.tertiary,
                    width: 2,
                  )
                : null,
          );
    final child = Text(label);
    return filled
        ? FilledButton(onPressed: () {}, style: style, child: child)
        : OutlinedButton(onPressed: () {}, style: style, child: child);
  }
}
