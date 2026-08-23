// Memory + scaling profile. Complements benchmark_main.dart, which measures
// single-op latency only.
//
//   cd example
//   flutter run --profile -t lib/profile_main.dart -d <device-id>
//
// Emits a PROFILE_START/PROFILE_END block. RSS is process-wide resident set
// (Dart VM + engine + native store), sampled via ProcessInfo.currentRss.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_datastore/native_datastore.dart';

final StringBuffer _out = StringBuffer();
void _log(String s) {
  _out.writeln(s);
  // ignore: avoid_print
  print(s);
}

int _rss() => ProcessInfo.currentRss;
String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);

Future<double> _timeAvg(int n, Future<void> Function(int) op) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await op(i);
  }
  sw.stop();
  return sw.elapsedMicroseconds / n;
}

/// Settle the heap so RSS deltas reflect retention, not in-flight garbage.
Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ds = NativeDatastore();
  await ds.clear();
  await _settle();

  _log('PROFILE_START');
  _log(
    'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
  _log('baseline RSS: ${_mb(_rss())} MB');
  _log('');

  // ---- 1. Read scaling: N single-key reads vs one getAll ----
  _log('## 1. Read scaling — N keys');
  _log('| keys | N x getString (ms) | 1 x getAll (ms) | getAll speedup |');
  _log('| ---: | ---: | ---: | ---: |');
  for (final n in <int>[1, 10, 50, 200]) {
    await ds.clear();
    for (var i = 0; i < n; i++) {
      await ds.setString('key_$i', 'value_$i');
    }
    // Warm.
    await ds.getString('key_0');
    await ds.getAll();

    final sw1 = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      await ds.getString('key_$i');
    }
    sw1.stop();

    final sw2 = Stopwatch()..start();
    await ds.getAll();
    sw2.stop();

    final indiv = sw1.elapsedMicroseconds / 1000.0;
    final all = sw2.elapsedMicroseconds / 1000.0;
    _log(
      '| $n | ${indiv.toStringAsFixed(2)} | ${all.toStringAsFixed(2)} '
      '| ${(indiv / (all == 0 ? 1 : all)).toStringAsFixed(1)}x |',
    );
  }
  _log('');

  // ---- 1b. Batch API vs individual calls ----
  _log('## 1b. Batch API');
  _log(
    '| keys | N x getString (ms) | getMany (ms) | N x setString (ms) | setMany (ms) |',
  );
  _log('| ---: | ---: | ---: | ---: | ---: |');
  for (final n in <int>[10, 50, 200]) {
    await ds.clear();
    final keys = <String>[for (var i = 0; i < n; i++) 'key_$i'];
    final entries = <String, Object>{for (final k in keys) k: 'value_$k'};
    await ds.setMany(entries);
    await ds.getMany(keys);

    final swR1 = Stopwatch()..start();
    for (final k in keys) {
      await ds.getString(k);
    }
    swR1.stop();

    final swR2 = Stopwatch()..start();
    await ds.getMany(keys);
    swR2.stop();

    await ds.clear();
    final swW1 = Stopwatch()..start();
    for (final entry in entries.entries) {
      await ds.setString(entry.key, entry.value as String);
    }
    swW1.stop();

    await ds.clear();
    final swW2 = Stopwatch()..start();
    await ds.setMany(entries);
    swW2.stop();

    _log(
      '| $n | ${(swR1.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
      '| ${(swR2.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
      '| ${(swW1.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
      '| ${(swW2.elapsedMicroseconds / 1000).toStringAsFixed(2)} |',
    );
  }
  _log('');

  // Correctness spot-check of the batch path.
  await ds.clear();
  await ds.setMany(<String, Object>{
    's': 'text',
    'b': true,
    'i': 42,
    'd': 1.5,
    'l': <String>['x', 'y'],
  });
  final round = await ds.getMany(<String>['s', 'b', 'i', 'd', 'l', 'absent']);
  _log('batch round-trip: $round');
  final removedCount = await ds.removeMany(<String>['s', 'b', 'absent']);
  _log('removeMany removed: $removedCount (expected 2)');
  _log('');

  // ---- 2. Write cost vs store size (does a write scale with key count?) ----
  _log('## 2. Write cost vs store size');
  _log('| existing keys | setString (us/op) |');
  _log('| ---: | ---: |');
  for (final n in <int>[0, 50, 200, 500]) {
    await ds.clear();
    for (var i = 0; i < n; i++) {
      await ds.setString('pad_$i', 'v$i');
    }
    await ds.setString('hot', 'warm');
    final us = await _timeAvg(60, (i) => ds.setString('hot', 'v$i'));
    _log('| $n | ${us.toStringAsFixed(1)} |');
  }
  _log('');

  // ---- 3. Bytes round-trip: base64 amplification ----
  _log('## 3. setBytes/getBytes vs payload size');
  _log('| payload | setBytes (ms) | getBytes (ms) | RSS delta (MB) |');
  _log('| ---: | ---: | ---: | ---: |');
  await ds.clear();
  for (final size in <int>[1024, 64 * 1024, 512 * 1024, 1024 * 1024]) {
    final blob = Uint8List(size);
    for (var i = 0; i < size; i++) {
      blob[i] = i & 0xff;
    }
    await _settle();
    final before = _rss();
    final swW = Stopwatch()..start();
    await ds.setBytes('blob', blob);
    swW.stop();
    final swR = Stopwatch()..start();
    final read = await ds.getBytes('blob');
    swR.stop();
    if (read == null || read.length != size) {
      _log('  !! round-trip mismatch at $size');
    }
    await _settle();
    final after = _rss();
    _log(
      '| ${(size / 1024).round()} KB | ${(swW.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
      '| ${(swR.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
      '| ${_mb(after - before)} |',
    );
  }
  _log('');

  // ---- 4. Watcher overhead: does a write get slower with watchers attached? ----
  _log('## 4. Watcher overhead on writes');
  _log('| watchers | setString (us/op) |');
  _log('| ---: | ---: |');
  await ds.clear();
  for (var i = 0; i < 100; i++) {
    await ds.setString('pad_$i', 'v');
  }
  final subs = <StreamSubscription<dynamic>>[];
  for (final w in <int>[0, 1, 5, 20]) {
    while (subs.length < w) {
      subs.add(ds.watchString('pad_${subs.length}').listen((_) {}));
    }
    await _settle();
    final us = await _timeAvg(60, (i) => ds.setString('hot', 'v$i'));
    _log('| $w | ${us.toStringAsFixed(1)} |');
  }
  _log('');

  // ---- 5. Watcher retention: RSS after attach/detach churn ----
  _log('## 5. Watcher attach/detach retention');
  await _settle();
  final rssBeforeChurn = _rss();
  for (var round = 0; round < 200; round++) {
    final s = ds.watchString('pad_1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await s.cancel();
  }
  await _settle();
  final rssAfterChurn = _rss();
  _log('RSS before 200 attach/detach cycles: ${_mb(rssBeforeChurn)} MB');
  _log('RSS after:                           ${_mb(rssAfterChurn)} MB');
  _log(
    'delta:                               ${_mb(rssAfterChurn - rssBeforeChurn)} MB',
  );
  _log('');

  for (final s in subs) {
    await s.cancel();
  }

  // ---- 6. Large-store retention ----
  _log('## 6. Large store retention');
  await ds.clear();
  await _settle();
  final rssEmpty = _rss();
  final bigValue = base64Encode(List<int>.filled(512, 7));
  for (var i = 0; i < 1000; i++) {
    await ds.setString('big_$i', '$bigValue$i');
  }
  await _settle();
  final rssFull = _rss();
  final all = await ds.getAll();
  await _settle();
  final rssAfterGetAll = _rss();
  _log('RSS empty store:            ${_mb(rssEmpty)} MB');
  _log(
    'RSS after 1000 x ~700B set: ${_mb(rssFull)} MB (delta ${_mb(rssFull - rssEmpty)} MB)',
  );
  _log(
    'RSS after getAll (${all.length} keys): ${_mb(rssAfterGetAll)} MB '
    '(delta ${_mb(rssAfterGetAll - rssFull)} MB)',
  );
  _log('on-disk payload was ~${_mb(1000 * 700)} MB');
  _log('');

  await ds.clear();
  _log('PROFILE_END');

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Text(
              _out.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
      ),
    ),
  );
}
