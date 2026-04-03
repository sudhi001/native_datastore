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

    // Test containsKey
    final exists = await datastore.containsKey('testKey');
    expect(exists, true);

    // Test getKeys
    final keys = await datastore.getKeys();
    expect(keys, contains('testKey'));

    // Test remove
    final removed = await datastore.remove('testKey');
    expect(removed, true);

    final afterRemove = await datastore.getString('testKey');
    expect(afterRemove, isNull);

    // Test clear
    await datastore.setString('a', '1');
    await datastore.setString('b', '2');
    await datastore.clear();
    final all = await datastore.getAll();
    expect(all, isEmpty);
  });
}
