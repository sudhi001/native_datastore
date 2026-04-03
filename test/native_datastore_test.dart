import 'package:flutter_test/flutter_test.dart';
import 'package:native_datastore/native_datastore.dart';

void main() {
  test('NativeDatastore can be instantiated', () {
    final datastore = NativeDatastore();
    expect(datastore, isNotNull);
  });
}
