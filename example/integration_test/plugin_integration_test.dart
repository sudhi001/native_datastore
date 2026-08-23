import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:native_datastore/native_datastore.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NativeDatastore basic operations', (WidgetTester tester) async {
    final datastore = NativeDatastore();

    // Clear any existing data
    await datastore.clear();

    // Test setString and getString
    await datastore.setString('testKey', 'testValue');
    final value = await datastore.getString('testKey');
    expect(value, 'testValue');

    // Test setBool and getBool
    await datastore.setBool('boolKey', true);
    final boolVal = await datastore.getBool('boolKey');
    expect(boolVal, true);

    await datastore.setBool('boolKeyFalse', false);
    final boolValFalse = await datastore.getBool('boolKeyFalse');
    expect(boolValFalse, false);

    // Test setInt and getInt
    await datastore.setInt('intKey', 42);
    final intVal = await datastore.getInt('intKey');
    expect(intVal, 42);

    // Test setDouble and getDouble
    await datastore.setDouble('doubleKey', 3.14);
    final doubleVal = await datastore.getDouble('doubleKey');
    expect(doubleVal, closeTo(3.14, 0.001));

    // Test setStringList and getStringList
    await datastore.setStringList('listKey', ['a', 'b', 'c']);
    final listVal = await datastore.getStringList('listKey');
    expect(listVal, ['a', 'b', 'c']);

    // Test setBytes and getBytes
    final bytes = Uint8List.fromList([0, 1, 2, 255]);
    await datastore.setBytes('bytesKey', bytes);
    final bytesVal = await datastore.getBytes('bytesKey');
    expect(bytesVal, bytes);

    // Test setDateTime and getDateTime
    final dt = DateTime.utc(2024, 6, 15, 10, 30, 0);
    await datastore.setDateTime('dateKey', dt);
    final dateVal = await datastore.getDateTime('dateKey');
    expect(dateVal, dt);

    // Test setMap and getMap
    final map = {'name': 'sudhi', 'age': 30, 'active': true};
    await datastore.setMap('mapKey', map);
    final mapVal = await datastore.getMap('mapKey');
    expect(mapVal, map);

    // Test containsKey
    final exists = await datastore.containsKey('testKey');
    expect(exists, true);

    // Test getKeys
    final keys = await datastore.getKeys();
    expect(
      keys,
      containsAll([
        'testKey',
        'boolKey',
        'boolKeyFalse',
        'intKey',
        'doubleKey',
        'listKey',
        'bytesKey',
        'dateKey',
        'mapKey',
      ]),
    );

    // Test getAll
    final allData = await datastore.getAll();
    expect(allData['testKey'], 'testValue');
    expect(allData['boolKey'], true);
    expect(allData['intKey'], 42);
    expect(allData['doubleKey'], closeTo(3.14, 0.001));
    expect(allData['listKey'], ['a', 'b', 'c']);

    // Test remove
    final removed = await datastore.remove('testKey');
    expect(removed, true);

    final afterRemove = await datastore.getString('testKey');
    expect(afterRemove, isNull);

    // Test getting missing keys returns null
    expect(await datastore.getString('nonexistent'), isNull);
    expect(await datastore.getBool('nonexistent'), isNull);
    expect(await datastore.getInt('nonexistent'), isNull);
    expect(await datastore.getDouble('nonexistent'), isNull);
    expect(await datastore.getStringList('nonexistent'), isNull);
    expect(await datastore.getBytes('nonexistent'), isNull);
    expect(await datastore.getDateTime('nonexistent'), isNull);
    expect(await datastore.getMap('nonexistent'), isNull);

    // Test clear
    await datastore.clear();
    final all = await datastore.getAll();
    expect(all, isEmpty);
  });

  testWidgets('SecureDatastore basic operations', (WidgetTester tester) async {
    final secure = SecureDatastore();

    await secure.clear();

    // String round-trip
    await secure.setString('refresh_token', 'jwt.payload.signature');
    expect(await secure.getString('refresh_token'), 'jwt.payload.signature');

    // Bytes round-trip
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    await secure.setBytes('symmetric_key', key);
    expect(await secure.getBytes('symmetric_key'), key);

    // String and bytes under the same user-key are independent buckets
    await secure.setString('mixed', 'as-string');
    await secure.setBytes('mixed', Uint8List.fromList([9, 9, 9]));
    expect(await secure.getString('mixed'), 'as-string');
    expect(await secure.getBytes('mixed'), Uint8List.fromList([9, 9, 9]));

    // Missing keys return null
    expect(await secure.getString('nonexistent'), isNull);
    expect(await secure.getBytes('nonexistent'), isNull);

    // containsKey / getKeys
    expect(await secure.containsKey('refresh_token'), true);
    expect(await secure.containsKey('nonexistent'), false);
    final keys = await secure.getKeys();
    expect(keys, containsAll(['refresh_token', 'symmetric_key', 'mixed']));

    // remove deletes both buckets for the same user-key
    expect(await secure.remove('mixed'), true);
    expect(await secure.getString('mixed'), isNull);
    expect(await secure.getBytes('mixed'), isNull);
    expect(await secure.remove('nonexistent'), false);

    // clear wipes everything
    await secure.clear();
    expect(await secure.getKeys(), isEmpty);
  });

  // Exercises the full SecureDatastore surface under a given configuration so
  // both single-process (default) and multi-process modes get identical
  // coverage. On Android `multiProcess: true` switches to a
  // MultiProcessDataStore in a separate file; on iOS `multiProcess` is a no-op
  // (cross-process sharing there uses a Keychain access group instead). Either
  // way every operation must behave the same.
  Future<void> runSecureRoundTrip(SecureDatastore secure, String tag) async {
    await secure.clear();
    expect(await secure.getKeys(), isEmpty, reason: '$tag: starts empty');

    // String round-trip.
    await secure.setString('token', 'secret-$tag');
    expect(await secure.getString('token'), 'secret-$tag', reason: tag);

    // Bytes round-trip.
    final key = Uint8List.fromList(List.generate(16, (i) => (255 - i) & 0xff));
    await secure.setBytes('key', key);
    expect(await secure.getBytes('key'), key, reason: tag);

    // String and bytes under one user-key are independent buckets.
    await secure.setString('mixed', 'as-string');
    await secure.setBytes('mixed', Uint8List.fromList([7, 8, 9]));
    expect(await secure.getString('mixed'), 'as-string', reason: tag);
    expect(
      await secure.getBytes('mixed'),
      Uint8List.fromList([7, 8, 9]),
      reason: tag,
    );

    // Introspection.
    expect(await secure.containsKey('token'), true, reason: tag);
    expect(await secure.containsKey('nope'), false, reason: tag);
    expect(
      await secure.getKeys(),
      containsAll(['token', 'key', 'mixed']),
      reason: tag,
    );

    // remove clears both buckets for a user-key.
    expect(await secure.remove('mixed'), true, reason: tag);
    expect(await secure.getString('mixed'), isNull, reason: tag);
    expect(await secure.getBytes('mixed'), isNull, reason: tag);
    expect(await secure.remove('nope'), false, reason: tag);

    // Missing keys read back null.
    expect(await secure.getString('absent'), isNull, reason: tag);
    expect(await secure.getBytes('absent'), isNull, reason: tag);

    await secure.clear();
    expect(await secure.getKeys(), isEmpty, reason: '$tag: cleared');
  }

  testWidgets('SecureDatastore single-process (default) round-trip', (
    WidgetTester tester,
  ) async {
    final secure = SecureDatastore();
    // Default: no configure() call — the standard single-process store.
    await runSecureRoundTrip(secure, 'single-process');
  });

  testWidgets('SecureDatastore multi-process configure round-trip', (
    WidgetTester tester,
  ) async {
    final secure = SecureDatastore();

    // Opt into multi-process. Must be safe to call before any read/write. We
    // deliberately do NOT pass an appGroupId: on iOS that sets a Keychain
    // access group requiring the Keychain Sharing entitlement, which this bare
    // example app does not declare.
    await secure.configure(multiProcess: true);
    await runSecureRoundTrip(secure, 'multi-process');

    // Reverting to the default store must also be non-destructive.
    await secure.configure();
    await runSecureRoundTrip(secure, 'after-revert');
  });

  testWidgets('atomic operations', (WidgetTester tester) async {
    final datastore = NativeDatastore();
    await datastore.clear();

    // incrementInt treats a missing value as 0 and returns the new value.
    expect(await datastore.incrementInt('count'), 1);
    expect(await datastore.incrementInt('count', 4), 5);
    expect(await datastore.decrementInt('count', 2), 3);
    expect(await datastore.getInt('count'), 3);

    // incrementDouble
    expect(await datastore.incrementDouble('rating', 0.5), 0.5);
    expect(await datastore.incrementDouble('rating', 0.25), 0.75);

    // toggleBool: missing -> true -> false
    expect(await datastore.toggleBool('flag'), true);
    expect(await datastore.toggleBool('flag'), false);

    // compareAndSet: swap only when the current value matches expected.
    await datastore.setString('token', 'a');
    expect(
      await datastore.compareAndSetString('token', expected: 'a', value: 'b'),
      true,
    );
    expect(await datastore.getString('token'), 'b');
    expect(
      await datastore.compareAndSetString('token', expected: 'a', value: 'c'),
      false,
    );
    expect(await datastore.getString('token'), 'b');

    await datastore.clear();
  });

  testWidgets('watch emits initial value and reacts to changes', (
    WidgetTester tester,
  ) async {
    final datastore = NativeDatastore();
    await datastore.clear();
    await datastore.setInt('counter', 10);

    final seen = <int?>[];
    final sub = datastore.watchInt('counter').listen(seen.add);

    // Real wall-clock delays: EventChannel notifications arrive on the actual
    // event loop, so `tester.pump` (which advances the fake frame clock) is
    // not enough — we must yield real time for the platform to deliver them.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await datastore.setInt('counter', 11);
    await datastore.incrementInt('counter'); // -> 12
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // A change to an unrelated key must not surface on this stream.
    await datastore.setString('unrelated', 'x');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await sub.cancel();

    expect(seen.first, 10);
    expect(seen.last, 12);
    expect(seen.contains(11), true);

    await datastore.clear();
  });
}
