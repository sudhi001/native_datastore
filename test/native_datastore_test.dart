import 'package:flutter_test/flutter_test.dart';
import 'package:native_datastore/native_datastore.dart';

void main() {
  test('NativeDatastore can be instantiated', () {
    final datastore = NativeDatastore();
    expect(datastore, isNotNull);
  });

  group('key validation', () {
    late NativeDatastore datastore;

    setUp(() {
      datastore = NativeDatastore();
    });

    test('getString throws on empty key', () {
      expect(
        () => datastore.getString(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setString throws on empty key', () {
      expect(
        () => datastore.setString('', 'value'),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getBool throws on empty key', () {
      expect(
        () => datastore.getBool(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setBool throws on empty key', () {
      expect(
        () => datastore.setBool('', true),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getInt throws on empty key', () {
      expect(
        () => datastore.getInt(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setInt throws on empty key', () {
      expect(
        () => datastore.setInt('', 42),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getDouble throws on empty key', () {
      expect(
        () => datastore.getDouble(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setDouble throws on empty key', () {
      expect(
        () => datastore.setDouble('', 3.14),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getStringList throws on empty key', () {
      expect(
        () => datastore.getStringList(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setStringList throws on empty key', () {
      expect(
        () => datastore.setStringList('', ['a']),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('remove throws on empty key', () {
      expect(
        () => datastore.remove(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('containsKey throws on empty key', () {
      expect(
        () => datastore.containsKey(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });
  });

  group('NativeDatastoreException', () {
    test('toString without cause', () {
      const exception = NativeDatastoreException('test error');
      expect(exception.toString(), 'NativeDatastoreException: test error');
    });

    test('toString with cause', () {
      final cause = Exception('root cause');
      final exception = NativeDatastoreException('test error', cause: cause);
      expect(
        exception.toString(),
        contains('NativeDatastoreException: test error'),
      );
      expect(exception.toString(), contains('root cause'));
    });

    test('message is accessible', () {
      const exception = NativeDatastoreException('msg');
      expect(exception.message, 'msg');
    });

    test('cause is accessible', () {
      final cause = Exception('x');
      final exception = NativeDatastoreException('msg', cause: cause);
      expect(exception.cause, cause);
    });
  });
}
