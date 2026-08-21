import 'package:flutter/foundation.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/backend_auth_repository.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/community/data/mock_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';
import 'package:voice_social_app/features/discovery/data/backend_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

class AppDependencies {
  AppDependencies._({
    required this.environment,
    required this.sessionManager,
    required this.authController,
    required this.liveReadOnlyRepository,
    required this.accountComplianceRepository,
    required this.discoveryRepository,
    required this.dynamicRepository,
    required this.socialRepository,
    required this.communityRepository,
    required this.commerceRepository,
    required this.commerceCatalogRepository,
    required this.messageRepository,
    required this.roomRepository,
    required this.roomOperationsRepository,
    required this.roomLifecycleRepository,
    required this.roomPkRepository,
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
    DateTime? mockNow,
  }) {
    return _build(
      environment: AppEnvironment.mock(),
      store: MemoryKeyValueStore(initialStorage),
      mockNow: mockNow,
    );
  }

  @visibleForTesting
  factory AppDependencies.forTestEnvironment({
    required AppEnvironment environment,
    Map<String, String>? initialStorage,
    DateTime? mockNow,
  }) {
    return _build(
      environment: environment,
      store: MemoryKeyValueStore(initialStorage),
      mockNow: mockNow,
    );
  }

  static AppDependencies _build({
    required AppEnvironment environment,
    required KeyValueStore store,
    DateTime? mockNow,
  }) {
    final AuthSessionManager sessionManager = AuthSessionManager(store);
    final ApiClient apiClient = ApiClient(
      baseUri: Uri.parse(environment.apiBaseUrl),
      clientType: environment.clientType,
      clientInnerVersion: environment.clientInnerVersion,
      authorizationProvider: () => sessionManager.authorizationHeader,
      requestHeadersProvider: () => <String, String>{
        if (environment.oauthClientId.trim().isNotEmpty)
          'Client-Id': environment.oauthClientId,
      },
      timeout: environment.apiTimeout,
    );
    final LiveReadOnlyRepository liveReadOnlyRepository =
        LiveReadOnlyRepository(apiClient);
    const BackendRouteCatalog routes = BackendRouteCatalog();
    final AuthRepository authRepository = environment.isLive
        ? BackendAuthRepository(
            apiClient: apiClient,
            environment: environment,
            routes: routes,
          )
        : const MockAuthRepository();
    final AccountComplianceRepository accountComplianceRepository =
        environment.isLive
        ? BackendAccountComplianceRepository(
            apiClient: apiClient,
            routes: routes,
          )
        : MockAccountComplianceRepository();
    final DiscoveryRepository discoveryRepository = environment.isLive
        ? BackendDiscoveryRepository(
            apiClient: apiClient,
            clientType: environment.clientType,
            routes: routes,
          )
        : MockDiscoveryRepository();
    final DynamicRepository dynamicRepository = environment.isLive
        ? BackendDynamicRepository(
            apiClient: apiClient,
            routes: routes,
            currentUserIdProvider: () => sessionManager.session?.userId ?? 0,
          )
        : MockDynamicRepository();
    final SocialRepository socialRepository = environment.isLive
        ? BackendSocialRepository(
            apiClient: apiClient,
            currentUserIdProvider: () => sessionManager.session?.userId ?? 0,
            routes: routes,
          )
        : MockSocialRepository();
    final CommunityRepository communityRepository = environment.isLive
        ? BackendCommunityRepository(apiClient: apiClient, routes: routes)
        : MockCommunityRepository();
    late final CommerceRepository commerceRepository;
    late final CommerceCatalogRepository commerceCatalogRepository;
    if (environment.isLive) {
      commerceRepository = BackendCommerceRepository(
        apiClient: apiClient,
        routes: routes,
      );
      commerceCatalogRepository = BackendCommerceCatalogRepository(
        apiClient: apiClient,
        routes: routes,
      );
    } else {
      final MockCommerceRepository mockCommerceRepository =
          MockCommerceRepository(now: mockNow);
      commerceRepository = mockCommerceRepository;
      commerceCatalogRepository = MockCommerceCatalogRepository(
        onRechargeOrderChanged: mockCommerceRepository.syncRechargeOrder,
      );
    }
    final MessageRepository messageRepository = environment.isLive
        ? BackendMessageRepository(
            apiClient: apiClient,
            routes: routes,
            currentUserIdProvider: () => sessionManager.session?.userId ?? 0,
          )
        : MockMessageRepository(now: mockNow);
    final RoomRepository roomRepository = environment.isLive
        ? BackendRoomRepository(apiClient: apiClient, routes: routes)
        : MockRoomRepository();
    final RoomOperationsRepository roomOperationsRepository = environment.isLive
        ? BackendRoomOperationsRepository(apiClient: apiClient, routes: routes)
        : MockRoomOperationsRepository(
            micCoordinationMode: MicCoordinationMode.direct,
          );
    final RoomLifecycleRepository roomLifecycleRepository = environment.isLive
        ? BackendRoomLifecycleRepository(apiClient: apiClient, routes: routes)
        : MockRoomLifecycleRepository();
    final RoomPkRepository roomPkRepository = environment.isLive
        ? BackendRoomPkRepository(apiClient: apiClient, routes: routes)
        : MockRoomPkRepository();
    final RtcAdapter rtcAdapter = environment.isLive
        ? const SnapshotOnlyRtcAdapter()
        : MockRtcAdapter();
    final RoomRealtimeGateway realtimeGateway = environment.isLive
        ? const SnapshotOnlyRoomRealtimeGateway()
        : MockRoomRealtimeGateway();
    final RoomAudioService roomAudioService = environment.isLive
        ? const UnavailableRoomAudioService()
        : MockRoomAudioService(now: mockNow);
    final DeviceIdentityProvider deviceIdentityProvider =
        DeviceIdentityProvider(
          environment: environment,
          sessionManager: sessionManager,
        );
    final AuthController authController = AuthController(
      repository: authRepository,
      sessionManager: sessionManager,
      deviceIdentityProvider: deviceIdentityProvider,
    );
    apiClient.setUnauthorizedRecovery(authController.refreshSession);
    return AppDependencies._(
      environment: environment,
      sessionManager: sessionManager,
      authController: authController,
      liveReadOnlyRepository: liveReadOnlyRepository,
      accountComplianceRepository: accountComplianceRepository,
      discoveryRepository: discoveryRepository,
      dynamicRepository: dynamicRepository,
      socialRepository: socialRepository,
      communityRepository: communityRepository,
      commerceRepository: commerceRepository,
      commerceCatalogRepository: commerceCatalogRepository,
      messageRepository: messageRepository,
      roomRepository: roomRepository,
      roomOperationsRepository: roomOperationsRepository,
      roomLifecycleRepository: roomLifecycleRepository,
      roomPkRepository: roomPkRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
      roomAudioService: roomAudioService,
    );
  }

  final AppEnvironment environment;
  final AuthSessionManager sessionManager;
  final AuthController authController;
  final LiveReadOnlyRepository liveReadOnlyRepository;
  final AccountComplianceRepository accountComplianceRepository;
  final DiscoveryRepository discoveryRepository;
  final DynamicRepository dynamicRepository;
  final SocialRepository socialRepository;
  final CommunityRepository communityRepository;
  final CommerceRepository commerceRepository;
  final CommerceCatalogRepository commerceCatalogRepository;
  final MessageRepository messageRepository;
  final RoomRepository roomRepository;
  final RoomOperationsRepository roomOperationsRepository;
  final RoomLifecycleRepository roomLifecycleRepository;
  final RoomPkRepository roomPkRepository;
  final RtcAdapter rtcAdapter;
  final RoomRealtimeGateway realtimeGateway;
  final RoomAudioService roomAudioService;

  RoomController createRoomController({
    required String roomId,
    required String title,
  }) {
    final session = sessionManager.session;
    if (session == null && environment.isLive) {
      throw StateError('用户未登录，不能创建房间会话');
    }
    return RoomController(
      roomId: roomId,
      title: title,
      currentUserId: session?.userId ?? 10001,
      accessToken: session?.accessToken ?? 'mock-local-session',
      repository: roomRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
    );
  }
}
