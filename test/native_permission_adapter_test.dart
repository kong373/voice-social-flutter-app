import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';

void main() {
  test(
    'method-channel adapter maps native states and requests per permission',
    () async {
      final List<NativePermissionCall> calls = <NativePermissionCall>[];
      final MethodChannelNativePermissionAdapter adapter =
          MethodChannelNativePermissionAdapter(
            invoker: (String method, Map<String, Object?> arguments) async {
              calls.add(
                NativePermissionCall(method: method, arguments: arguments),
              );
              if (method == 'status') {
                return 'permanentlyDenied';
              }
              if (method == 'request') {
                return 'granted';
              }
              if (method == 'openAppSettings') {
                return true;
              }
              return null;
            },
          );

      expect(
        await adapter.status(PermissionKind.notifications),
        PermissionState.permanentlyDenied,
      );
      expect(
        await adapter.request(PermissionKind.notifications),
        PermissionState.granted,
      );
      expect(
        await adapter.status(PermissionKind.camera),
        PermissionState.permanentlyDenied,
      );
      await adapter.openAppSettings();

      expect(calls, <NativePermissionCall>[
        const NativePermissionCall(
          method: 'status',
          arguments: <String, Object?>{'kind': 'notifications'},
        ),
        const NativePermissionCall(
          method: 'request',
          arguments: <String, Object?>{'kind': 'notifications'},
        ),
        const NativePermissionCall(
          method: 'status',
          arguments: <String, Object?>{'kind': 'camera'},
        ),
        const NativePermissionCall(method: 'openAppSettings'),
      ]);
    },
  );

  test(
    'method-channel adapter rejects any settings result except explicit true',
    () async {
      for (final Object? nativeResult in <Object?>[false, null, 'true']) {
        final MethodChannelNativePermissionAdapter adapter =
            MethodChannelNativePermissionAdapter(
              invoker: (String method, Map<String, Object?> arguments) async =>
                  nativeResult,
            );

        await expectLater(
          adapter.openAppSettings(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.configuration,
            ),
          ),
          reason: 'native result: $nativeResult',
        );
      }
    },
  );

  test(
    'method-channel adapter fails closed when native host is unavailable',
    () async {
      final MethodChannelNativePermissionAdapter adapter =
          MethodChannelNativePermissionAdapter(
            invoker: (String method, Map<String, Object?> arguments) async =>
                throw StateError('native host unavailable'),
          );

      expect(
        await adapter.status(PermissionKind.microphone),
        PermissionState.unavailable,
      );
      expect(
        await adapter.request(PermissionKind.photos),
        PermissionState.unavailable,
      );
    },
  );

  test('external URL opener only sends strict HTTPS URLs', () async {
    final List<NativePermissionCall> calls = <NativePermissionCall>[];
    final MethodChannelExternalUrlOpener opener =
        MethodChannelExternalUrlOpener(
          invoker: (String method, Map<String, Object?> arguments) async {
            calls.add(
              NativePermissionCall(method: method, arguments: arguments),
            );
            return true;
          },
        );

    expect(
      await opener.open(Uri.parse('http://updates.example/app.apk')),
      isFalse,
    );
    expect(await opener.open(Uri.parse('https:///app.apk')), isFalse);
    expect(
      await opener.open(
        Uri.parse('https://user:password@updates.example/app.apk'),
      ),
      isFalse,
    );
    expect(
      await opener.open(Uri.parse('https://updates.example/app.apk')),
      isTrue,
    );
    expect(calls, <NativePermissionCall>[
      const NativePermissionCall(
        method: 'openExternalUrl',
        arguments: <String, Object?>{'url': 'https://updates.example/app.apk'},
      ),
    ]);
  });

  test(
    'external URL opener treats missing or failed host as not opened',
    () async {
      final MethodChannelExternalUrlOpener missing =
          MethodChannelExternalUrlOpener(
            invoker: (String _, Map<String, Object?> __) async {
              throw MissingPluginException();
            },
          );
      final MethodChannelExternalUrlOpener rejected =
          MethodChannelExternalUrlOpener(
            invoker: (String _, Map<String, Object?> __) async => false,
          );

      expect(
        await missing.open(Uri.parse('https://updates.example/app.apk')),
        isFalse,
      );
      expect(
        await rejected.open(Uri.parse('https://updates.example/app.apk')),
        isFalse,
      );
    },
  );
}

class NativePermissionCall {
  const NativePermissionCall({required this.method, this.arguments = const {}});

  final String method;
  final Map<String, Object?> arguments;

  @override
  bool operator ==(Object other) =>
      other is NativePermissionCall &&
      other.method == method &&
      _mapsEqual(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(method, arguments.length);

  static bool _mapsEqual(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (final MapEntry<String, Object?> entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
