import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_exception.dart';

const registrationAvatarMaximumBytes = 10000000;
const registrationAvatarInvalid = ApiException(
  kind: ApiFailureKind.protocol,
  message: '注册头像响应无效，请检查上传状态',
);
const registrationAvatarContextExpired = ApiException(
  kind: ApiFailureKind.unauthorized,
  message: '注册验证已变化或过期，请重新获取验证码',
);

String registrationAvatarUuid(Object? value) {
  if (value is! String ||
      value.length != 36 ||
      !RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(value)) {
    throw registrationAvatarInvalid;
  }
  return value;
}

/// One immutable SMS challenge, never an App principal. The caller's callback
/// must check its captured registration generation, including same-phone ABA.
class RegistrationAvatarContext extends ChangeNotifier {
  RegistrationAvatarContext({
    required this.phone,
    required this.smsCode,
    required this.challengeId,
    required this.deviceId,
    required this.clientId,
    required this.expiresAt,
    required void Function() requireCurrent,
    required Listenable changes,
    DateTime Function()? now,
  }) : _requireCurrent = requireCurrent,
       _changes = changes,
       _now = now ?? DateTime.now {
    registrationAvatarUuid(challengeId);
    if (phone.length != 11 ||
        !RegExp(r'^1[0-9]{10}$').hasMatch(phone) ||
        smsCode.length != 6 ||
        !RegExp(r'^[0-9]{6}$').hasMatch(smsCode) ||
        !_header(deviceId) ||
        !_header(clientId) ||
        !expiresAt.isUtc) {
      throw registrationAvatarInvalid;
    }
    check();
    _changes.addListener(_changed);
    _timer = Timer(expiresAt.difference(_now()), invalidate);
  }
  final String phone, smsCode, challengeId, deviceId, clientId;
  final DateTime expiresAt;
  final Listenable _changes;
  final void Function() _requireCurrent;
  final DateTime Function() _now;
  final _cancelled = Completer<void>();
  final _callbacks = <void Function()>{};
  Timer? _timer;
  bool _invalid = false, _disposed = false;
  static bool _header(String value) =>
      value.isNotEmpty &&
      value.length <= 160 &&
      value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7e);
  bool get isCurrent {
    if (_invalid || _disposed || !_now().isBefore(expiresAt)) return false;
    try {
      _requireCurrent();
      return true;
    } catch (_) {
      return false;
    }
  }

  void check() {
    if (!isCurrent) {
      invalidate();
      throw registrationAvatarContextExpired;
    }
  }

  void _changed() {
    if (!isCurrent) invalidate();
  }

  void invalidate() {
    if (_invalid) return;
    _invalid = true;
    _timer?.cancel();
    _changes.removeListener(_changed);
    _cancelled.complete();
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
    if (!_disposed) notifyListeners();
  }

  void Function() onCancel(void Function() callback) {
    check();
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  Future<T> wait<T>(Future<T> operation) async {
    final observed = operation.then<T>(
      (value) {
        check();
        return value;
      },
      onError: (Object error, StackTrace stack) {
        check();
        Error.throwWithStackTrace(error, stack);
      },
    );
    if (!isCurrent) invalidate();
    return Future.any<T>([
      observed,
      _cancelled.future.then<T>((_) => throw registrationAvatarContextExpired),
    ]);
  }

  /// Secure-journal binding includes the code without persisting it in clear.
  String binding(String capability) => Hmac(sha256, utf8.encode(capability))
      .convert(
        utf8.encode(
          jsonEncode([
            phone,
            smsCode,
            challengeId,
            deviceId,
            clientId,
            expiresAt.toIso8601String(),
          ]),
        ),
      )
      .toString();
  @override
  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    super.dispose();
  }
}

enum RegistrationAvatarState {
  allocated,
  uploading,
  quarantined,
  ready,
  bound,
  rejected,
}

class RegistrationAvatarStatus {
  RegistrationAvatarStatus.fromData(Object? raw) {
    if (raw is! Map<String, Object?>) throw registrationAvatarInvalid;
    const keys = {
      'assetId',
      'purpose',
      'state',
      'version',
      'maximumBytes',
      'expiresAt',
      'mediaType',
      'bytes',
      'durationMillis',
    };
    if (raw.length != keys.length ||
        !raw.keys.toSet().containsAll(keys) ||
        raw['purpose'] != 'AVATAR' ||
        raw['maximumBytes'] is! int ||
        raw['maximumBytes'] != registrationAvatarMaximumBytes)
      throw registrationAvatarInvalid;
    assetId = registrationAvatarUuid(raw['assetId']);
    final versionValue = raw['version'];
    if (versionValue is! int ||
        versionValue < 0 ||
        versionValue > 9007199254740991)
      throw registrationAvatarInvalid;
    version = versionValue;
    state = switch (raw['state']) {
      'ALLOCATED' => RegistrationAvatarState.allocated,
      'UPLOADING' => RegistrationAvatarState.uploading,
      'QUARANTINED' => RegistrationAvatarState.quarantined,
      'READY' => RegistrationAvatarState.ready,
      'BOUND' => RegistrationAvatarState.bound,
      'REJECTED' => RegistrationAvatarState.rejected,
      _ => throw registrationAvatarInvalid,
    };
    final expiry = raw['expiresAt'];
    if (expiry is! String || !expiry.endsWith('Z'))
      throw registrationAvatarInvalid;
    final parsed = DateTime.tryParse(expiry);
    if (parsed == null || !parsed.isUtc) throw registrationAvatarInvalid;
    expiresAt = parsed;
    final type = raw['mediaType'],
        size = raw['bytes'],
        duration = raw['durationMillis'];
    // QUARANTINED already has observed bytes; MIME/duration are still null
    // until the server finishes decoding and scanning.
    if ((size != null &&
            (size is! int ||
                size <= 0 ||
                size > registrationAvatarMaximumBytes)) ||
        (type == null && duration != null) ||
        (type != null &&
            (type is! String ||
                !const {
                  'image/jpeg',
                  'image/png',
                  'image/webp',
                }.contains(type) ||
                size == null ||
                duration is! int ||
                duration != 0))) {
      throw registrationAvatarInvalid;
    }
    if ((type == null || size == null) &&
        (state == RegistrationAvatarState.ready ||
            state == RegistrationAvatarState.bound))
      throw registrationAvatarInvalid;
    mediaType = type as String?;
    bytes = size as int?;
    durationMillis = duration as int?;
  }
  late final String assetId;
  late final int version;
  late final RegistrationAvatarState state;
  late final DateTime expiresAt;
  late final String? mediaType;
  late final int? bytes, durationMillis;
  Map<String, Object?> toData() => {
    'assetId': assetId,
    'purpose': 'AVATAR',
    'state': state.name.toUpperCase(),
    'version': version,
    'maximumBytes': registrationAvatarMaximumBytes,
    'expiresAt': expiresAt.toIso8601String(),
    'mediaType': mediaType,
    'bytes': bytes,
    'durationMillis': durationMillis,
  };
}

/// Capability is a credential: pass only to the final registration header;
/// never stringify into logs or put it in a URL, widget key or diagnostics.
class RegistrationAvatarReady {
  const RegistrationAvatarReady({
    required this.assetId,
    required this.version,
    required this.requestId,
    required this.capability,
  });
  final String assetId, requestId, capability;
  final int version;
}
