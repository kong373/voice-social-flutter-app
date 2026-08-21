import 'dart:io';
import 'dart:math';

import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

class DeviceIdentityProvider {
  DeviceIdentityProvider({
    required AppEnvironment environment,
    required AuthSessionManager sessionManager,
  }) : _environment = environment,
       _sessionManager = sessionManager;

  final AppEnvironment _environment;
  final AuthSessionManager _sessionManager;

  Future<ClientDevice> load() async {
    String? installId = await _sessionManager.readInstallId();
    if (installId == null || installId.isEmpty) {
      installId = _createInstallId();
      await _sessionManager.saveInstallId(installId);
    }
    final bool isIos = _environment.clientType.toLowerCase() == 'ios';
    return ClientDevice(
      deviceType: isIos ? 2 : 1,
      deviceId: installId,
      mobileKind: '${Platform.operatingSystem} Flutter',
      appMarketType: isIos ? 12 : 0,
      isEmulator: 0,
      smDeviceId: installId,
    );
  }

  static String _createInstallId() {
    final int random = Random.secure().nextInt(1 << 32);
    return 'flutter-${DateTime.now().microsecondsSinceEpoch}-$random';
  }
}
