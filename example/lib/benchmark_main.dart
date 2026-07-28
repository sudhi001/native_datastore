// Benchmark entrypoint. Measures per-operation latency for the regular and
// secure stores on a real device/simulator and prints a Markdown table.
//
//   cd example
//   flutter run -t lib/benchmark_main.dart -d <device-id>
//   # read the BENCHMARK_TABLE_START / _END block from the console
//
// Numbers are wall-clock over the Pigeon channel and depend heavily on the
// host (debug vs release, simulator vs device). Treat them as relative
// (secure vs regular, read vs write), not absolute.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_datastore/native_datastore.dart';

/// Timed operations per case. Bump for steadier numbers.
const int _iterations = 300;

/// Discarded warm-up ops (first calls pay channel/JIT/keystore setup).
const int _warmup = 30;

class _Result {
  _Result(this.label, this.micros);
  final String label;
  final double micros;
}

Future<_Result> _time(String label, Future<void> Function(int i) op) async {
  for (var i = 0; i < _warmup; i++) {
    await op(i);
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < _iterations; i++) {
    await op(i);
  }
  sw.stop();
  return _Result(label, sw.elapsedMicroseconds / _iterations);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final regular = NativeDatastore();
  final secure = SecureDatastore();
  await regular.clear();
  await secure.clear();

  const value = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.benchmark.payload';
  final bytes = Uint8List.fromList(List.generate(64, (i) => i & 0xff));

  // Seed the keys the read cases measure.
  await regular.setString('k', value);
  await regular.setInt('n', 0);
  await secure.setString('k', value);
  await secure.setBytes('b', bytes);

  // Writes use a value that changes every iteration so each call is a real
  // write (no dedupe on the same value), keeping set* cases comparable.
  final results = <_Result>[
    await _time('regular setString', (i) => regular.setString('k', '$value$i')),
    await _time('regular getString', (i) => regular.getString('k')),
    await _time('regular setInt', (i) => regular.setInt('n', i)),
    await _time('regular getInt', (i) => regular.getInt('n')),
    await _time('secure setString', (i) => secure.setString('k', '$value$i')),
    await _time('secure getString', (i) => secure.getString('k')),
    await _time('secure setBytes',
        (i) => secure.setBytes('b', Uint8List.fromList([i & 0xff, ...bytes]))),
    await _time('secure getBytes', (i) => secure.getBytes('b')),
  ];

  final buffer = StringBuffer()
    ..writeln('BENCHMARK_TABLE_START')
    ..writeln('| Operation | Mean per op (µs) | Ops/sec |')
    ..writeln('| --- | ---: | ---: |');
  for (final r in results) {
    buffer.writeln('| ${r.label} | ${r.micros.toStringAsFixed(1)} '
        '| ${(1000000 / r.micros).round()} |');
  }
  buffer.writeln('BENCHMARK_TABLE_END');
  // ignore: avoid_print
  print(buffer.toString());

  await regular.clear();
  await secure.clear();

  runApp(_BenchApp(results: results));
}

class _BenchApp extends StatelessWidget {
  const _BenchApp({required this.results});
  final List<_Result> results;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('native_datastore benchmark')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final r in results)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${r.label}: ${r.micros.toStringAsFixed(1)} µs/op',
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
          ],
        ),
      ),
    );
  }
}
