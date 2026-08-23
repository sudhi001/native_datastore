// On-device self-test entrypoint. Runs the SecureDatastore round-trip in both
// single-process and multi-process modes and prints PASS/FAIL lines that stream
// over `flutter run` stdout (which, unlike the integration_test reporter, is
// reliable in headless CI/emulator environments).
//
//   cd example
//   flutter run -t lib/selftest_main.dart -d <device-id>
//   # grep the console for lines beginning with "SELFTEST"
//
// Exit is left to the caller (Ctrl-C / `q`); the result also renders on screen.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_datastore/native_datastore.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <String>[];
  var passed = 0;
  var failed = 0;

  void check(String name, bool ok, [String detail = '']) {
    (ok ? () => passed++ : () => failed++)();
    final line =
        'SELFTEST ${ok ? "PASS" : "FAIL"}: $name'
        '${detail.isEmpty ? "" : "  ($detail)"}';
    results.add(line);
    // ignore: avoid_print
    print(line);
  }

  Future<void> roundTrip(SecureDatastore secure, String tag) async {
    await secure.clear();
    check('$tag: starts empty', (await secure.getKeys()).isEmpty);

    await secure.setString('token', 'secret-$tag');
    check(
      '$tag: string round-trip',
      await secure.getString('token') == 'secret-$tag',
    );

    final bytes = Uint8List.fromList(
      List.generate(16, (i) => (255 - i) & 0xff),
    );
    await secure.setBytes('key', bytes);
    final got = await secure.getBytes('key');
    check(
      '$tag: bytes round-trip',
      got != null && got.length == 16 && got[0] == 255 && got[15] == 240,
    );

    await secure.setString('mixed', 'as-string');
    await secure.setBytes('mixed', Uint8List.fromList([7, 8, 9]));
    check(
      '$tag: independent string/bytes buckets',
      await secure.getString('mixed') == 'as-string' &&
          (await secure.getBytes('mixed'))?.first == 7,
    );

    check('$tag: containsKey true', await secure.containsKey('token'));
    check('$tag: containsKey false', !await secure.containsKey('nope'));
    check(
      '$tag: getKeys',
      (await secure.getKeys()).toSet().containsAll({'token', 'key', 'mixed'}),
    );

    check('$tag: remove clears both buckets', await secure.remove('mixed'));
    check('$tag: removed is gone', await secure.getString('mixed') == null);
    check('$tag: missing key null', await secure.getString('absent') == null);

    await secure.clear();
    check('$tag: cleared', (await secure.getKeys()).isEmpty);
  }

  try {
    final secure = SecureDatastore();

    // 1) Default single-process store.
    await roundTrip(secure, 'single-process');

    // 2) Multi-process. On Android switches to a MultiProcessDataStore; on iOS
    //    multiProcess is a no-op. We omit appGroupId so iOS doesn't need the
    //    Keychain Sharing entitlement.
    await secure.configure(multiProcess: true);
    await roundTrip(secure, 'multi-process');

    // 3) Revert to default — must stay non-destructive.
    await secure.configure();
    await roundTrip(secure, 'after-revert');
  } catch (e, st) {
    check('unexpected exception', false, '$e');
    // ignore: avoid_print
    print('SELFTEST STACK: $st');
  }

  // ignore: avoid_print
  print(
    'SELFTEST SUMMARY: $passed passed, $failed failed '
    '=> ${failed == 0 ? "ALL PASS" : "FAILURES"}',
  );

  runApp(_ResultApp(results: results, allPass: failed == 0));
}

class _ResultApp extends StatelessWidget {
  const _ResultApp({required this.results, required this.allPass});
  final List<String> results;
  final bool allPass;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: allPass ? Colors.green.shade50 : Colors.red.shade50,
        appBar: AppBar(
          backgroundColor: allPass ? Colors.green : Colors.red,
          foregroundColor: Colors.white,
          title: Text(
            allPass
                ? 'SecureDatastore self-test: ALL PASS'
                : 'SecureDatastore self-test: FAILURES',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final r in results)
              Text(
                r,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: r.contains('FAIL') ? Colors.red : Colors.black87,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
