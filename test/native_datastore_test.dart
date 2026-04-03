import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_datastore/native_datastore.dart';
import 'package:native_datastore/src/messages.g.dart';

/// Helper to set up mock handlers on the Pigeon channels.
///
/// Pigeon uses [BasicMessageChannel] with [StandardMessageCodec].
/// Requests are encoded as `[arg1, arg2, ...]` and responses as `[result]`
/// for success or `[code, message, details]` for errors.
class MockDatastoreChannel {
  static const _codec = StandardMessageCodec();
  static const _channelPrefix =
      'dev.flutter.pigeon.native_datastore.DatastoreApi.';

  /// Registers a mock handler for the given [method] that returns [result].
  static void mockMethod(String method, Object? result) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      '$_channelPrefix$method',
      (ByteData? message) async {
        // Return a success response: [result]
        return _codec.encodeMessage(<Object?>[result]);
      },
    );
  }

  /// Registers a mock handler for the given [method] that returns an error.
  static void mockMethodError(
    String method, {
    String code = 'test-error',
    String? errorMessage,
    Object? details,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      '$_channelPrefix$method',
      (ByteData? message) async {
        // Return an error response: [code, message, details]
        return _codec
            .encodeMessage(<Object?>[code, errorMessage, details]);
      },
    );
  }

  /// Clears all mock handlers.
  static void reset() {
    final methods = [
      'getString',
      'getBool',
      'getInt',
      'getDouble',
      'getStringList',
      'setString',
      'setBool',
      'setInt',
      'setDouble',
      'setStringList',
      'remove',
      'clear',
      'getAll',
      'getKeys',
      'containsKey',
    ];
    for (final method in methods) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('$_channelPrefix$method', null);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeDatastore datastore;

  setUp(() {
    datastore = NativeDatastore();
  });

  tearDown(() {
    MockDatastoreChannel.reset();
  });

  // -------------------------------------------------------
  // NativeDatastoreException
  // -------------------------------------------------------
  group('NativeDatastoreException', () {
    test('toString without cause', () {
      const e = NativeDatastoreException('test error');
      expect(e.toString(), 'NativeDatastoreException: test error');
      expect(e.message, 'test error');
      expect(e.cause, isNull);
    });

    test('toString with cause', () {
      final cause = Exception('root');
      final e = NativeDatastoreException('test error', cause: cause);
      expect(e.toString(), contains('test error'));
      expect(e.toString(), contains('root'));
      expect(e.cause, cause);
    });
  });

  // -------------------------------------------------------
  // Key validation
  // -------------------------------------------------------
  group('key validation', () {
    test('getString throws on empty key', () {
      expect(
        () => datastore.getString(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getBool throws on empty key', () {
      expect(
        () => datastore.getBool(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getInt throws on empty key', () {
      expect(
        () => datastore.getInt(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getDouble throws on empty key', () {
      expect(
        () => datastore.getDouble(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getStringList throws on empty key', () {
      expect(
        () => datastore.getStringList(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setString throws on empty key', () {
      expect(
        () => datastore.setString('', 'v'),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setBool throws on empty key', () {
      expect(
        () => datastore.setBool('', true),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setInt throws on empty key', () {
      expect(
        () => datastore.setInt('', 1),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setDouble throws on empty key', () {
      expect(
        () => datastore.setDouble('', 1.0),
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

  // -------------------------------------------------------
  // Successful operations (via mocked platform channels)
  // -------------------------------------------------------
  group('successful operations', () {
    test('getString returns value', () async {
      MockDatastoreChannel.mockMethod('getString', 'hello');
      expect(await datastore.getString('k'), 'hello');
    });

    test('getString returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getString', null);
      expect(await datastore.getString('k'), isNull);
    });

    test('getBool returns value', () async {
      MockDatastoreChannel.mockMethod('getBool', true);
      expect(await datastore.getBool('k'), true);
    });

    test('getBool returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getBool', null);
      expect(await datastore.getBool('k'), isNull);
    });

    test('getInt returns value', () async {
      MockDatastoreChannel.mockMethod('getInt', 42);
      expect(await datastore.getInt('k'), 42);
    });

    test('getInt returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getInt', null);
      expect(await datastore.getInt('k'), isNull);
    });

    test('getDouble returns value', () async {
      MockDatastoreChannel.mockMethod('getDouble', 3.14);
      expect(await datastore.getDouble('k'), 3.14);
    });

    test('getDouble returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getDouble', null);
      expect(await datastore.getDouble('k'), isNull);
    });

    test('getStringList returns value', () async {
      MockDatastoreChannel.mockMethod('getStringList', ['a', 'b']);
      expect(await datastore.getStringList('k'), ['a', 'b']);
    });

    test('getStringList returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getStringList', null);
      expect(await datastore.getStringList('k'), isNull);
    });

    test('setString completes', () async {
      MockDatastoreChannel.mockMethod('setString', null);
      await datastore.setString('k', 'v');
    });

    test('setBool completes', () async {
      MockDatastoreChannel.mockMethod('setBool', null);
      await datastore.setBool('k', false);
    });

    test('setInt completes', () async {
      MockDatastoreChannel.mockMethod('setInt', null);
      await datastore.setInt('k', 99);
    });

    test('setDouble completes', () async {
      MockDatastoreChannel.mockMethod('setDouble', null);
      await datastore.setDouble('k', 2.7);
    });

    test('setStringList completes', () async {
      MockDatastoreChannel.mockMethod('setStringList', null);
      await datastore.setStringList('k', ['x']);
    });

    test('remove returns true', () async {
      MockDatastoreChannel.mockMethod('remove', true);
      expect(await datastore.remove('k'), true);
    });

    test('remove returns false', () async {
      MockDatastoreChannel.mockMethod('remove', false);
      expect(await datastore.remove('k'), false);
    });

    test('clear returns true', () async {
      MockDatastoreChannel.mockMethod('clear', true);
      expect(await datastore.clear(), true);
    });

    test('getAll returns map', () async {
      MockDatastoreChannel.mockMethod('getAll', {'a': 1, 'b': 'two'});
      final result = await datastore.getAll();
      expect(result, {'a': 1, 'b': 'two'});
    });

    test('getKeys returns list', () async {
      MockDatastoreChannel.mockMethod('getKeys', ['a', 'b', 'c']);
      expect(await datastore.getKeys(), ['a', 'b', 'c']);
    });

    test('containsKey returns true', () async {
      MockDatastoreChannel.mockMethod('containsKey', true);
      expect(await datastore.containsKey('k'), true);
    });

    test('containsKey returns false', () async {
      MockDatastoreChannel.mockMethod('containsKey', false);
      expect(await datastore.containsKey('k'), false);
    });
  });

  // -------------------------------------------------------
  // Error handling (_guard wraps PlatformException)
  // -------------------------------------------------------
  group('error handling', () {
    test('getString wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getString',
          errorMessage: 'disk error');
      final e = await _expectException(() => datastore.getString('k'));
      expect(e.message, contains('getString'));
      expect(e.message, contains('disk error'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getBool wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getBool',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getBool('k'));
      expect(e.message, contains('getBool'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getInt wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getInt',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getInt('k'));
      expect(e.message, contains('getInt'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getDouble wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getDouble',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getDouble('k'));
      expect(e.message, contains('getDouble'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getStringList wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getStringList',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getStringList('k'));
      expect(e.message, contains('getStringList'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setString wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setString',
          errorMessage: 'fail');
      final e =
          await _expectException(() => datastore.setString('k', 'v'));
      expect(e.message, contains('setString'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setBool wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setBool',
          errorMessage: 'fail');
      final e =
          await _expectException(() => datastore.setBool('k', true));
      expect(e.message, contains('setBool'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setInt wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setInt',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.setInt('k', 1));
      expect(e.message, contains('setInt'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setDouble wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setDouble',
          errorMessage: 'fail');
      final e =
          await _expectException(() => datastore.setDouble('k', 1.0));
      expect(e.message, contains('setDouble'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setStringList wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setStringList',
          errorMessage: 'fail');
      final e = await _expectException(
          () => datastore.setStringList('k', ['a']));
      expect(e.message, contains('setStringList'));
      expect(e.cause, isA<PlatformException>());
    });

    test('remove wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('remove',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.remove('k'));
      expect(e.message, contains('remove'));
      expect(e.cause, isA<PlatformException>());
    });

    test('clear wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('clear',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.clear());
      expect(e.message, contains('clear'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getAll wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getAll',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getAll());
      expect(e.message, contains('getAll'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getKeys wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getKeys',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getKeys());
      expect(e.message, contains('getKeys'));
      expect(e.cause, isA<PlatformException>());
    });

    test('containsKey wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('containsKey',
          errorMessage: 'fail');
      final e =
          await _expectException(() => datastore.containsKey('k'));
      expect(e.message, contains('containsKey'));
      expect(e.cause, isA<PlatformException>());
    });

    test('error with null message uses code', () async {
      MockDatastoreChannel.mockMethodError('getString', code: 'ERR_CODE');
      final e = await _expectException(() => datastore.getString('k'));
      expect(e.message, contains('ERR_CODE'));
    });
  });

  // -------------------------------------------------------
  // withApi constructor
  // -------------------------------------------------------
  group('withApi constructor', () {
    test('uses injected api', () async {
      MockDatastoreChannel.mockMethod('getString', 'injected');
      final ds = NativeDatastore.withApi(DatastoreApi());
      expect(await ds.getString('k'), 'injected');
    });
  });
}

  // -------------------------------------------------------
  // Generated code edge cases (messages.g.dart coverage)
  // -------------------------------------------------------
  group('generated code edge cases', () {
    test('channel returns null triggers channel-error', () async {
      // Mock handler that returns null bytes (simulating broken channel)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        'dev.flutter.pigeon.native_datastore.DatastoreApi.getString',
        (ByteData? message) async => null,
      );
      expect(
        () => datastore.getString('k'),
        throwsA(isA<NativeDatastoreException>().having(
          (e) => e.cause,
          'cause',
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'channel-error',
          ),
        )),
      );
    });

    test('non-null method receiving null triggers null-error', () async {
      // remove() expects a non-null bool, send back [null]
      const codec = StandardMessageCodec();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        'dev.flutter.pigeon.native_datastore.DatastoreApi.remove',
        (ByteData? message) async {
          return codec.encodeMessage(<Object?>[null]);
        },
      );
      expect(
        () => datastore.remove('k'),
        throwsA(isA<NativeDatastoreException>().having(
          (e) => e.cause,
          'cause',
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'null-error',
          ),
        )),
      );
    });

    test('DatastoreApi with messageChannelSuffix', () {
      // Exercises line 68: messageChannelSuffix.isNotEmpty branch
      final api = DatastoreApi(messageChannelSuffix: 'test');
      expect(api.pigeonVar_messageChannelSuffix, '.test');
    });

    test('DatastoreApi with empty messageChannelSuffix', () {
      final api = DatastoreApi();
      expect(api.pigeonVar_messageChannelSuffix, '');
    });
  });
}

/// Helper that expects a [NativeDatastoreException] to be thrown.
Future<NativeDatastoreException> _expectException(
    Future<Object?> Function() fn) async {
  try {
    await fn();
    fail('Expected NativeDatastoreException to be thrown');
  } on NativeDatastoreException catch (e) {
    return e;
  }
  throw StateError('unreachable');
}
