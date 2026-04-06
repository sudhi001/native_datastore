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
}
