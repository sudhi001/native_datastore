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
      'getBytes',
      'setBytes',
      'getDateTime',
      'setDateTime',
      'getMap',
      'setMap',
      'incrementInt',
      'incrementDouble',
      'toggleBool',
      'compareAndSetString',
      'compareAndSetInt',
      'compareAndSetDouble',
      'compareAndSetBool',
      'migrateFromSharedPreferences',
      'configure',
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

  tearDown(MockDatastoreChannel.reset);

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

    test('getBytes throws on empty key', () {
      expect(
        () => datastore.getBytes(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setBytes throws on empty key', () {
      expect(
        () => datastore.setBytes('', Uint8List(0)),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getDateTime throws on empty key', () {
      expect(
        () => datastore.getDateTime(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setDateTime throws on empty key', () {
      expect(
        () => datastore.setDateTime('', DateTime.now()),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getMap throws on empty key', () {
      expect(
        () => datastore.getMap(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setMap throws on empty key', () {
      expect(
        () => datastore.setMap('', {}),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('rejects keys starting with reserved __list__ prefix', () {
      expect(
        () => datastore.setString('__list__:foo', 'v'),
        throwsA(isA<NativeDatastoreException>().having(
          (e) => e.message,
          'message',
          contains('reserved prefix'),
        )),
      );
    });

    test('rejects keys starting with reserved __bytes__ prefix', () {
      expect(
        () => datastore.getBytes('__bytes__:foo'),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('rejects keys starting with reserved __datetime__ prefix', () {
      expect(
        () => datastore.setDateTime('__datetime__:foo', DateTime.now()),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('rejects keys starting with reserved __map__ prefix', () {
      expect(
        () => datastore.getMap('__map__:foo'),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('accepts keys that merely contain the prefix but do not start with it',
        () async {
      MockDatastoreChannel.mockMethod('setString', null);
      await datastore.setString('user__list__:foo', 'v');
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

    test('clear completes', () async {
      MockDatastoreChannel.mockMethod('clear', null);
      await datastore.clear();
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

    test('getBytes returns value', () async {
      MockDatastoreChannel.mockMethod('getBytes', Uint8List.fromList([1, 2, 3]));
      final result = await datastore.getBytes('k');
      expect(result, Uint8List.fromList([1, 2, 3]));
    });

    test('getBytes returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getBytes', null);
      expect(await datastore.getBytes('k'), isNull);
    });

    test('setBytes completes', () async {
      MockDatastoreChannel.mockMethod('setBytes', null);
      await datastore.setBytes('k', Uint8List.fromList([1, 2]));
    });

    test('getDateTime returns value', () async {
      MockDatastoreChannel.mockMethod('getDateTime', 1700000000000);
      final result = await datastore.getDateTime('k');
      expect(result, DateTime.utc(2023, 11, 14, 22, 13, 20));
    });

    test('getDateTime returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getDateTime', null);
      expect(await datastore.getDateTime('k'), isNull);
    });

    test('setDateTime completes', () async {
      MockDatastoreChannel.mockMethod('setDateTime', null);
      await datastore.setDateTime('k', DateTime.utc(2023));
    });

    test('getMap returns value', () async {
      MockDatastoreChannel.mockMethod('getMap', '{"a":1,"b":"two"}');
      final result = await datastore.getMap('k');
      expect(result, {'a': 1, 'b': 'two'});
    });

    test('getMap returns null for missing key', () async {
      MockDatastoreChannel.mockMethod('getMap', null);
      expect(await datastore.getMap('k'), isNull);
    });

    test('setMap completes', () async {
      MockDatastoreChannel.mockMethod('setMap', null);
      await datastore.setMap('k', {'x': 1});
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

    test('getBytes wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getBytes',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getBytes('k'));
      expect(e.message, contains('getBytes'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setBytes wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setBytes',
          errorMessage: 'fail');
      final e = await _expectException(
          () => datastore.setBytes('k', Uint8List(0)));
      expect(e.message, contains('setBytes'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getDateTime wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getDateTime',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getDateTime('k'));
      expect(e.message, contains('getDateTime'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setDateTime wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setDateTime',
          errorMessage: 'fail');
      final e = await _expectException(
          () => datastore.setDateTime('k', DateTime.now()));
      expect(e.message, contains('setDateTime'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getMap wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('getMap',
          errorMessage: 'fail');
      final e = await _expectException(() => datastore.getMap('k'));
      expect(e.message, contains('getMap'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setMap wraps PlatformException', () async {
      MockDatastoreChannel.mockMethodError('setMap',
          errorMessage: 'fail');
      final e = await _expectException(
          () => datastore.setMap('k', {'a': 1}));
      expect(e.message, contains('setMap'));
      expect(e.cause, isA<PlatformException>());
    });

    test('getMap wraps corrupt JSON as NativeDatastoreException', () async {
      MockDatastoreChannel.mockMethod('getMap', 'not valid json');
      final e = await _expectException(() => datastore.getMap('k'));
      expect(e.message, contains('getMap'));
      expect(e.cause, isA<FormatException>());
    });

    test('getMap wraps non-object JSON as NativeDatastoreException', () async {
      // Top-level JSON array can't be cast to Map<String, dynamic>.
      MockDatastoreChannel.mockMethod('getMap', '[1,2,3]');
      final e = await _expectException(() => datastore.getMap('k'));
      expect(e.message, contains('getMap'));
    });

    test('setMap wraps non-encodable value as NativeDatastoreException',
        () async {
      MockDatastoreChannel.mockMethod('setMap', null);
      // A Dart object that jsonEncode can't serialize.
      final e = await _expectException(
        () => datastore.setMap('k', {'bad': Object()}),
      );
      expect(e.message, contains('setMap'));
    });

    test('setBytes rejects payloads over 1 MiB', () async {
      // Just over 1 MiB; should be rejected without touching the channel.
      final tooLarge = Uint8List(1024 * 1024 + 1);
      final e =
          await _expectException(() => datastore.setBytes('k', tooLarge));
      expect(e.message, contains('too large'));
    });

    test('setMap rejects encoded JSON over 1 MiB', () async {
      MockDatastoreChannel.mockMethod('setMap', null);
      final huge = {'x': 'a' * (1024 * 1024 + 1)};
      final e = await _expectException(() => datastore.setMap('k', huge));
      expect(e.message, contains('too large'));
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

  // -------------------------------------------------------
  // SecureDatastore
  // -------------------------------------------------------
  group('SecureDatastore', () {
    const secureChannelPrefix =
        'dev.flutter.pigeon.native_datastore.SecureDatastoreApi.';
    const codec = StandardMessageCodec();

    void mockSecure(String method, Object? result) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        '$secureChannelPrefix$method',
        (ByteData? message) async => codec.encodeMessage(<Object?>[result]),
      );
    }

    void mockSecureError(String method, {String code = 'test-error', String? errorMessage}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        '$secureChannelPrefix$method',
        (ByteData? message) async =>
            codec.encodeMessage(<Object?>[code, errorMessage, null]),
      );
    }

    late SecureDatastore secure;

    setUp(() {
      secure = SecureDatastore();
    });

    tearDown(() {
      for (final method in [
        'getString',
        'setString',
        'getBytes',
        'setBytes',
        'remove',
        'clear',
        'getKeys',
        'containsKey',
        'configure',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('$secureChannelPrefix$method', null);
      }
    });

    test('getString throws on empty key', () {
      expect(
        () => secure.getString(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setString throws on empty key', () {
      expect(
        () => secure.setString('', 'v'),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getBytes throws on empty key', () {
      expect(
        () => secure.getBytes(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('setBytes throws on empty key', () {
      expect(
        () => secure.setBytes('', Uint8List(0)),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('remove throws on empty key', () {
      expect(
        () => secure.remove(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('containsKey throws on empty key', () {
      expect(
        () => secure.containsKey(''),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('rejects keys starting with reserved __str__ prefix', () {
      expect(
        () => secure.setString('__str__:foo', 'v'),
        throwsA(isA<NativeDatastoreException>().having(
          (e) => e.message,
          'message',
          contains('reserved prefix'),
        )),
      );
    });

    test('rejects keys starting with reserved __bytes__ prefix', () {
      expect(
        () => secure.getBytes('__bytes__:foo'),
        throwsA(isA<NativeDatastoreException>()),
      );
    });

    test('getString returns value', () async {
      mockSecure('getString', 'secret-token');
      expect(await secure.getString('k'), 'secret-token');
    });

    test('getString returns null for missing key', () async {
      mockSecure('getString', null);
      expect(await secure.getString('k'), isNull);
    });

    test('setString completes', () async {
      mockSecure('setString', null);
      await secure.setString('k', 'v');
    });

    test('getBytes returns value', () async {
      mockSecure('getBytes', Uint8List.fromList([1, 2, 3]));
      expect(await secure.getBytes('k'), Uint8List.fromList([1, 2, 3]));
    });

    test('getBytes returns null for missing key', () async {
      mockSecure('getBytes', null);
      expect(await secure.getBytes('k'), isNull);
    });

    test('setBytes completes', () async {
      mockSecure('setBytes', null);
      await secure.setBytes('k', Uint8List.fromList([1, 2]));
    });

    test('remove returns bool', () async {
      mockSecure('remove', true);
      expect(await secure.remove('k'), true);
    });

    test('clear completes', () async {
      mockSecure('clear', null);
      await secure.clear();
    });

    test('getKeys returns list', () async {
      mockSecure('getKeys', ['a', 'b']);
      expect(await secure.getKeys(), ['a', 'b']);
    });

    test('containsKey returns bool', () async {
      mockSecure('containsKey', false);
      expect(await secure.containsKey('k'), false);
    });

    test('getString wraps PlatformException', () async {
      mockSecureError('getString', errorMessage: 'keychain denied');
      final e = await _expectException(() => secure.getString('k'));
      expect(e.message, contains('secure getString'));
      expect(e.cause, isA<PlatformException>());
    });

    test('setString rejects payloads over 1 MiB', () async {
      final e = await _expectException(
        () => secure.setString('k', 'a' * (1024 * 1024 + 1)),
      );
      expect(e.message, contains('too large'));
    });

    test('setBytes rejects payloads over 1 MiB', () async {
      final tooLarge = Uint8List(1024 * 1024 + 1);
      final e =
          await _expectException(() => secure.setBytes('k', tooLarge));
      expect(e.message, contains('too large'));
    });

    test('withApi constructor uses injected api', () async {
      mockSecure('getString', 'injected-secret');
      final s = SecureDatastore.withApi(SecureDatastoreApi());
      expect(await s.getString('k'), 'injected-secret');
    });

    test('configure completes', () async {
      mockSecure('configure', null);
      await secure.configure(multiProcess: true, appGroupId: 'group.test');
    });

    test('configure defaults are non-destructive', () async {
      mockSecure('configure', null);
      await secure.configure();
    });

    test('configure surfaces platform errors', () async {
      mockSecureError('configure', errorMessage: 'boom');
      final e = await _expectException(() => secure.configure());
      expect(e.message, contains('secure configure'));
      expect(e.cause, isA<PlatformException>());
    });
  });

  group('atomic operations', () {
    late NativeDatastore datastore;

    setUp(() {
      datastore = NativeDatastore();
      MockDatastoreChannel.reset();
    });

    tearDown(MockDatastoreChannel.reset);

    test('incrementInt returns the new value', () async {
      MockDatastoreChannel.mockMethod('incrementInt', 5);
      expect(await datastore.incrementInt('count', 5), 5);
    });

    test('incrementInt defaults delta to 1', () async {
      MockDatastoreChannel.mockMethod('incrementInt', 1);
      expect(await datastore.incrementInt('count'), 1);
    });

    test('decrementInt delegates to incrementInt', () async {
      MockDatastoreChannel.mockMethod('incrementInt', 9);
      expect(await datastore.decrementInt('count'), 9);
    });

    test('incrementDouble returns the new value', () async {
      MockDatastoreChannel.mockMethod('incrementDouble', 2.5);
      expect(await datastore.incrementDouble('rating', 0.5), 2.5);
    });

    test('toggleBool returns the new value', () async {
      MockDatastoreChannel.mockMethod('toggleBool', true);
      expect(await datastore.toggleBool('flag'), true);
    });

    test('compareAndSetString returns true on swap', () async {
      MockDatastoreChannel.mockMethod('compareAndSetString', true);
      expect(
        await datastore.compareAndSetString('k', expected: 'a', value: 'b'),
        isTrue,
      );
    });

    test('compareAndSetInt returns false on mismatch', () async {
      MockDatastoreChannel.mockMethod('compareAndSetInt', false);
      expect(
        await datastore.compareAndSetInt('k', expected: 1, value: 2),
        isFalse,
      );
    });

    test('compareAndSetDouble returns true', () async {
      MockDatastoreChannel.mockMethod('compareAndSetDouble', true);
      expect(await datastore.compareAndSetDouble('k', value: 1.0), isTrue);
    });

    test('compareAndSetBool returns true', () async {
      MockDatastoreChannel.mockMethod('compareAndSetBool', true);
      expect(await datastore.compareAndSetBool('k', value: true), isTrue);
    });

    test('atomic ops validate the key', () async {
      final e = await _expectException(() => datastore.incrementInt(''));
      expect(e.message, contains('empty'));
    });
  });

  group('migration and configuration', () {
    late NativeDatastore datastore;

    setUp(() {
      datastore = NativeDatastore();
      MockDatastoreChannel.reset();
    });

    tearDown(MockDatastoreChannel.reset);

    test('migrateFromSharedPreferences returns imported count', () async {
      MockDatastoreChannel.mockMethod('migrateFromSharedPreferences', 3);
      expect(await datastore.migrateFromSharedPreferences(), 3);
    });

    test('configure completes', () async {
      MockDatastoreChannel.mockMethod('configure', null);
      await expectLater(
        datastore.configure(multiProcess: true, appGroupId: 'group.test'),
        completes,
      );
    });

    test('configure surfaces platform errors', () async {
      MockDatastoreChannel.mockMethodError('configure',
          errorMessage: 'boom');
      final e = await _expectException(() => datastore.configure());
      expect(e.message, contains('configure'));
    });
  });

  group('reactive observation', () {
    const changesChannel = EventChannel('in.sudhi.native_datastore/changes');
    late NativeDatastore datastore;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MockStreamHandlerEventSink> sinks;

    setUp(() {
      datastore = NativeDatastore();
      MockDatastoreChannel.reset();
      // Fresh cached stream per test so each rebinds to the handler below.
      NativeDatastore.debugResetChangeStream();
      sinks = <MockStreamHandlerEventSink>[];
      // Capture each fresh subscription's sink so the test can push events.
      messenger.setMockStreamHandler(
        changesChannel,
        MockStreamHandler.inline(
          onListen: (Object? args, MockStreamHandlerEventSink sink) =>
              sinks.add(sink),
        ),
      );
    });

    tearDown(() {
      MockDatastoreChannel.reset();
      messenger.setMockStreamHandler(changesChannel, null);
      NativeDatastore.debugResetChangeStream();
    });

    test('watchString emits the current value on subscription', () async {
      MockDatastoreChannel.mockMethod('getString', 'v0');
      expect(await datastore.watchString('k').first, 'v0');
    });

    test('watchChanges surfaces the changed keys from the platform', () async {
      final received = <List<String>>[];
      final sub = datastore.watchChanges().listen(received.add);
      await pumpEventQueue();

      sinks.single.success(<String>['count', 'name']);
      await pumpEventQueue();
      await sub.cancel();

      expect(received.single, <String>['count', 'name']);
    });

    // Note: the per-key re-read/filter behaviour of watchInt/watchString/etc.
    // (emit the initial value, then re-read only when the changed-keys list
    // contains the watched key) is exercised on-device by the example's
    // integration test — unit-mocking the ordering of the EventChannel
    // subscription against the initial async read is brittle and adds no
    // coverage over the two tests above plus that integration test.
  });
}

/// Helper that expects a [NativeDatastoreException] to be thrown.
Future<NativeDatastoreException> _expectException(
    Future<Object?> Function() fn) async {
  try {
    await fn();
  } on NativeDatastoreException catch (e) {
    return e;
  }
  fail('Expected NativeDatastoreException to be thrown');
}
