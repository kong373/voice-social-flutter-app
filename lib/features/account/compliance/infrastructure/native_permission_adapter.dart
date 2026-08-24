import 'package:flutter/services.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

/// The small first-party boundary between Flutter and the operating system.
///
/// No vendor SDK or provider status is represented here. The adapter only
/// knows about the three OS permissions used by the product and returns an
/// explicit unavailable state when the generated host has not registered the
/// native channel.
abstract interface class NativePermissionAdapter {
  Future<PermissionState> status(PermissionKind kind);

  Future<PermissionState> request(PermissionKind kind);

  Future<void> openAppSettings();
}

typedef NativePermissionInvoker =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

/// Method-channel implementation used by live mode.
///
/// The optional invoker is intentionally injectable for unit tests. Production
/// callers use the default [MethodChannel.invokeMethod] implementation.
class MethodChannelNativePermissionAdapter implements NativePermissionAdapter {
  MethodChannelNativePermissionAdapter({
    MethodChannel? channel,
    NativePermissionInvoker? invoker,
  }) : _channel = channel ?? _defaultChannel,
       _invoker = invoker;

  static const MethodChannel _defaultChannel = MethodChannel(
    'voice_social_app/system_permissions',
  );

  final MethodChannel _channel;
  final NativePermissionInvoker? _invoker;

  @override
  Future<PermissionState> status(PermissionKind kind) async {
    final Object? value = await _invoke('status', <String, Object?>{
      'kind': kind.name,
    });
    return _parseState(value);
  }

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    final Object? value = await _invoke('request', <String, Object?>{
      'kind': kind.name,
    });
    return _parseState(value);
  }

  @override
  Future<void> openAppSettings() async {
    await _invoke('openAppSettings', const <String, Object?>{});
  }

  Future<Object?> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      if (_invoker != null) {
        return await _invoker(method, arguments);
      }
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // Permission integration is deliberately fail-closed. A native host
      // error cannot be treated as a grant or as a provider response.
      return null;
    } on Object {
      // A test host or an incorrectly configured generated runner must have
      // the same safe behavior as a missing plugin.
      return null;
    }
  }

  static PermissionState _parseState(Object? value) {
    final String raw = value is Map
        ? value['state']?.toString() ?? ''
        : value?.toString() ?? '';
    return switch (raw.trim().toLowerCase()) {
      'notdetermined' || 'not_determined' => PermissionState.notDetermined,
      'granted' ||
      'authorized' ||
      'limited' ||
      'provisional' ||
      'ephemeral' => PermissionState.granted,
      'denied' => PermissionState.denied,
      'permanentlydenied' ||
      'permanently_denied' ||
      'blocked' => PermissionState.permanentlyDenied,
      'restricted' => PermissionState.restricted,
      _ => PermissionState.unavailable,
    };
  }
}
