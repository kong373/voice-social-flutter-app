import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/backend_auth_repository.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

class AppDependencies {
  AppDependencies._({
    required this.environment,
    required this.sessionManager,
    required this.authController,
    required this.roomRepository,
    required this.roomOperationsRepository,
    required this.rtcAdapter,
    required this.realtimeGateway,
    required this.roomAudioService,
  });

  factory AppDependencies.fromEnvironment() {
    final AppEnvironment environment = AppEnvironment.fromDefines();
    final KeyValueStore store = SecureKeyValueStore();
    return _build(environment: environment, store: store);
  }

  factory AppDependencies.mock({
    Map<String, String>? initialStorage,
  }) {
    return _build(
      environment: AppEnvironment.mock(),
      store: MemoryKeyValueStore(initialStorage),
    );
  }

  static AppDependencies _build({
    required AppEnvironment environment,
    required KeyValueStore store,
  }) {
    final AuthSessionManager sessionManager = AuthSessionManager(store);
    final ApiClient apiClient = ApiClient(
      baseUri: Uri.parse(environment.apiBaseUrl),
      clientType: environment.clientType,
      clientInnerVersion: environment.clientInnerVersion,
      authorizationProvider: () => sessionManager.authorizationHeader,
    );
    const BackendRouteCatalog routes = BackendRouteCatalog();
    final AuthRepository authRepository = environment.isLive
        ? BackendAuthRepository(
            apiClient: apiClient,
            environment: environment,
            routes: routes,
          )
        : const MockAuthRepository();
    final RoomRepository roomRepository = environment.isLive
        ? BackendRoomRepository(apiClient: apiClient, routes: routes)
        : MockRoomRepository();
    final RoomOperationsRepository roomOperationsRepository = environment.isLive
        ? BackendRoomOperationsRepository(apiClient: apiClient, routes: routes)
        : MockRoomOperationsRepository();
    final RtcAdapter rtcAdapter =
        environment.isLive ? const UnavailableRtcAdapter() : MockRtcAdapter();
    final RoomRealtimeGateway realtimeGateway = environment.isLive
        ? const UnavailableRoomRealtimeGateway()
        : MockRoomRealtimeGateway();
    final RoomAudioService roomAudioService = environment.isLive
        ? const UnavailableRoomAudioService()
        : MockRoomAudioService();
    final DeviceIdentityProvider deviceIdentityProvider = DeviceIdentityProvider(
      environment: environment,
      sessionManager: sessionManager,
    );
    final AuthController authController = AuthController(
      repository: authRepository,
      sessionManager: sessionManager,
      deviceIdentityProvider: deviceIdentityProvider,
    );
    return AppDependencies._(
      environment: environment,
      sessionManager: sessionManager,
      authController: authController,
      roomRepository: roomRepository,
      roomOperationsRepository: roomOperationsRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
      roomAudioService: roomAudioService,
    );
  }

  final AppEnvironment environment;
  final AuthSessionManager sessionManager;
  final AuthController authController;
  final RoomRepository roomRepository;
  final RoomOperationsRepository roomOperationsRepository;
  final RtcAdapter rtcAdapter;
  final RoomRealtimeGateway realtimeGateway;
  final RoomAudioService roomAudioService;

  RoomController createRoomController({
    required String roomId,
    required String title,
  }) {
    final session = sessionManager.session;
    if (session == null) {
      throw StateError('用户未登录，不能创建房间会话');
    }
    return RoomController(
      roomId: roomId,
      title: title,
      currentUserId: session.userId,
      accessToken: session.accessToken,
      repository: roomRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
    );
  }
}
