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
    expect(keys, containsAll(['testKey', 'boolKey', 'boolKeyFalse', 'intKey', 'doubleKey', 'listKey', 'bytesKey', 'dateKey', 'mapKey']));

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
}
