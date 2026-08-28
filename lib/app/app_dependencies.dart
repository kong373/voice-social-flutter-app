import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/backend_auth_repository.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';
import 'package:voice_social_app/features/im/application/tencent_im_avchat_room_coordinator.dart';
import 'package:voice_social_app/features/im/application/im_session_coordinator.dart';
import 'package:voice_social_app/features/im/data/backend_im_session_credential_repository.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_repository.dart';
import 'package:voice_social_app/features/im/infrastructure/tencent_im_session_adapter.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';
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
import 'package:voice_social_app/features/room/data/backend_rtc_token_repository.dart';
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
    required this.imSessionAdapter,
    required this.imSessionCredentialRepository,
    required this.imSessionCoordinator,
    required this.imAuthoritativeRefreshBus,
    required this.tencentImAvChatRoomCoordinator,
    required this.currentTime,
    required this.liveReadOnlyRepository,
    required this.accountComplianceRepository,
    required this.discoveryRepository,
    required this.dynamicRepository,
    required this.socialRepository,
    required this.communityRepository,
    required this.commerceRepository,
    required this.commerceCatalogRepository,
    required this.alipayAppPayAdapter,
    required this.messageRepository,
    required this.roomRepository,
    required this.roomOperationsRepository,
    required this.roomLifecycleRepository,
    required this.roomPkRepository,
    required this.rtcAdapter,
    required this.realtimeGateway,
    required this.roomAudioService,
    required this.externalUrlOpener,
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
    AccountComplianceRepository? accountComplianceRepository,
    DiscoveryRepository? discoveryRepository,
    DynamicRepository? dynamicRepository,
    MessageRepository? messageRepository,
    ExternalUrlOpener? externalUrlOpener,
    ImSessionAdapter? imSessionAdapter,
    ImSessionCredentialRepository? imSessionCredentialRepository,
    ImSessionCoordinator? imSessionCoordinator,
    ImAuthoritativeRefreshBus? imAuthoritativeRefreshBus,
    TencentImAvChatRoomCoordinator? tencentImAvChatRoomCoordinator,
    Duration? alipayNativeTimeout,
  }) {
    return _build(
      environment: environment,
      store: MemoryKeyValueStore(initialStorage),
      mockNow: mockNow,
      accountComplianceRepositoryOverride: accountComplianceRepository,
      discoveryRepositoryOverride: discoveryRepository,
      dynamicRepositoryOverride: dynamicRepository,
      messageRepositoryOverride: messageRepository,
      externalUrlOpenerOverride: externalUrlOpener,
      imSessionAdapterOverride: imSessionAdapter,
      imSessionCredentialRepositoryOverride: imSessionCredentialRepository,
      imSessionCoordinatorOverride: imSessionCoordinator,
      imAuthoritativeRefreshBusOverride: imAuthoritativeRefreshBus,
      tencentImAvChatRoomCoordinatorOverride: tencentImAvChatRoomCoordinator,
      alipayNativeTimeout: alipayNativeTimeout,
    );
  }

  static AppDependencies _build({
    required AppEnvironment environment,
    required KeyValueStore store,
    DateTime? mockNow,
    AccountComplianceRepository? accountComplianceRepositoryOverride,
    DiscoveryRepository? discoveryRepositoryOverride,
    DynamicRepository? dynamicRepositoryOverride,
    MessageRepository? messageRepositoryOverride,
    ExternalUrlOpener? externalUrlOpenerOverride,
    ImSessionAdapter? imSessionAdapterOverride,
    ImSessionCredentialRepository? imSessionCredentialRepositoryOverride,
    ImSessionCoordinator? imSessionCoordinatorOverride,
    ImAuthoritativeRefreshBus? imAuthoritativeRefreshBusOverride,
    TencentImAvChatRoomCoordinator? tencentImAvChatRoomCoordinatorOverride,
    Duration? alipayNativeTimeout,
  }) {
    final DateTime Function() currentTime = () => mockNow ?? DateTime.now();
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
    final NativePermissionAdapter? nativePermissionAdapter = environment.isLive
        ? MethodChannelNativePermissionAdapter()
        : null;
    final AuthRepository authRepository = environment.isLive
        ? BackendAuthRepository(
            apiClient: apiClient,
            environment: environment,
            sessionManager: sessionManager,
            routes: routes,
          )
        : const MockAuthRepository();
    ImSessionAdapter buildProductionTencentImAdapter() {
      // The official callback only marks a provider event as eligible after
      // this adapter compares its transient sender metadata with the active
      // server-issued system account.  C2C remains groupId=null; an AVChatRoom
      // event must additionally match the currently joined group. This avoids
      // a hard-coded admin name, current-user/self trust, or a blanket
      // trusted=true shortcut.
      late final TencentImSessionAdapter adapter;
      final OfficialTencentImSdkClient sdkClient = OfficialTencentImSdkClient(
        trustedHintEvaluator:
            ({
              required String? senderUserId,
              required String? groupId,
              required bool? isSelf,
            }) => adapter.isTrustedProviderHint(
              senderUserId: senderUserId,
              groupId: groupId,
              isSelf: isSelf,
            ),
      );
      adapter = TencentImSessionAdapter(sdkClient: sdkClient);
      return adapter;
    }

    final ImSessionAdapter imSessionAdapter =
        imSessionAdapterOverride ??
        (environment.isLive
            ? environment.enableTencentIm
                  ? buildProductionTencentImAdapter()
                  : const BlockedImSessionAdapter()
            : FakeImSessionAdapter(now: currentTime));
    final ImSessionCredentialRepository imSessionCredentialRepository =
        imSessionCredentialRepositoryOverride ??
        (environment.isLive
            ? environment.enableTencentIm
                  ? BackendImSessionCredentialRepository(
                      apiClient: apiClient,
                      routes: routes,
                      now: currentTime,
                    )
                  : const BlockedImSessionCredentialRepository()
            : FakeImSessionCredentialRepository(
                userIdProvider: () {
                  final int? userId = sessionManager.session?.userId;
                  return userId == null
                      ? ''
                      : ImSessionCredentials.userIdForPlatformUserId(userId);
                },
                now: currentTime,
              ));
    final ImAuthoritativeRefreshBus imAuthoritativeRefreshBus =
        imAuthoritativeRefreshBusOverride ?? ImAuthoritativeRefreshBus();
    final ImSessionCoordinator imSessionCoordinator =
        imSessionCoordinatorOverride ??
        ImSessionCoordinator(
          adapter: imSessionAdapter,
          credentialsRepository: imSessionCredentialRepository,
          authoritativeRefreshBus: imAuthoritativeRefreshBus,
          now: currentTime,
        );
    final TencentImAvChatRoomCoordinator tencentImAvChatRoomCoordinator =
        tencentImAvChatRoomCoordinatorOverride ??
        TencentImAvChatRoomCoordinator(
          sessionAdapter: imSessionAdapter,
          now: currentTime,
        );
    final AccountComplianceRepository accountComplianceRepository =
        accountComplianceRepositoryOverride ??
        (environment.isLive
            ? BackendAccountComplianceRepository(
                apiClient: apiClient,
                routes: routes,
                currentDeviceIdProvider: () =>
                    sessionManager.session?.deviceId ?? '',
                nativePermissionAdapter: nativePermissionAdapter,
                // AC-006 is first-party manual review. It does not invoke a
                // formal identity vendor; the backend owns redaction and
                // persists only its first-party review result.
                supportsRealNameSubmission: true,
              )
            : MockAccountComplianceRepository());
    final AlipayAppPayAdapter alipayAppPayAdapter =
        environment.isLive && environment.enableAlipayAppPay
        ? MethodChannelAlipayAppPayAdapter(
            enabled: true,
            sandbox: environment.useAlipaySandbox,
            consentChecker: sessionManager.hasAcceptedConsent,
            nativeTimeout: alipayNativeTimeout ?? const Duration(minutes: 2),
          )
        : const DisabledAlipayAppPayAdapter();
    final DiscoveryRepository discoveryRepository =
        discoveryRepositoryOverride ??
        (environment.isLive
            ? BackendDiscoveryRepository(
                apiClient: apiClient,
                clientType: environment.clientType,
                routes: routes,
              )
            : MockDiscoveryRepository());
    final DynamicRepository dynamicRepository =
        dynamicRepositoryOverride ??
        (environment.isLive
            ? BackendDynamicRepository(
                apiClient: apiClient,
                routes: routes,
                currentUserIdProvider: () =>
                    sessionManager.session?.userId ?? 0,
              )
            : MockDynamicRepository());
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
        alipayAppPayAdapter: alipayAppPayAdapter,
      );
    } else {
      final MockCommerceRepository mockCommerceRepository =
          MockCommerceRepository(now: mockNow);
      commerceRepository = mockCommerceRepository;
      commerceCatalogRepository = MockCommerceCatalogRepository(
        onRechargeOrderChanged: mockCommerceRepository.syncRechargeOrder,
      );
    }
    final MessageRepository messageRepository =
        messageRepositoryOverride ??
        (environment.isLive
            ? BackendMessageRepository(
                apiClient: apiClient,
                routes: routes,
                currentUserIdProvider: () =>
                    sessionManager.session?.userId ?? 0,
                nativePermissionAdapter: nativePermissionAdapter,
                privateRealtimeAvailabilityProvider: () =>
                    imSessionCoordinator.realtimeReady,
              )
            : MockMessageRepository(now: mockNow));
    final RtcTokenRepository? rtcTokenRepository =
        environment.isLive && environment.enableAgoraRtc
        ? BackendRtcTokenRepository(
            apiClient: apiClient,
            routes: routes,
            now: currentTime,
          )
        : null;
    final RoomRepository roomRepository = environment.isLive
        ? BackendRoomRepository(
            apiClient: apiClient,
            routes: routes,
            rtcTokenRepository: rtcTokenRepository,
            now: currentTime,
          )
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
        ? rtcTokenRepository == null
              ? const SnapshotOnlyRtcAdapter()
              : AgoraRtcAdapter(
                  credentialsProvider: (String roomId) async {
                    final session = sessionManager.session;
                    if (session == null) {
                      throw StateError('用户未登录，不能刷新 RTC 凭证');
                    }
                    return rtcTokenRepository.buildRtcToken(
                      roomId: roomId,
                      currentUserId: session.userId,
                    );
                  },
                  microphonePermissionAdapter: nativePermissionAdapter,
                )
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
      imSessionCoordinator: imSessionCoordinator,
      allowsDevelopmentTools:
          environment.deploymentEnvironment.allowsDevelopmentTools,
    );
    final ExternalUrlOpener externalUrlOpener =
        externalUrlOpenerOverride ?? MethodChannelExternalUrlOpener();
    apiClient.setUnauthorizedRecovery(authController.refreshSession);
    return AppDependencies._(
      environment: environment,
      sessionManager: sessionManager,
      authController: authController,
      imSessionAdapter: imSessionAdapter,
      imSessionCredentialRepository: imSessionCredentialRepository,
      imSessionCoordinator: imSessionCoordinator,
      imAuthoritativeRefreshBus: imAuthoritativeRefreshBus,
      tencentImAvChatRoomCoordinator: tencentImAvChatRoomCoordinator,
      currentTime: currentTime,
      liveReadOnlyRepository: liveReadOnlyRepository,
      accountComplianceRepository: accountComplianceRepository,
      discoveryRepository: discoveryRepository,
      dynamicRepository: dynamicRepository,
      socialRepository: socialRepository,
      communityRepository: communityRepository,
      commerceRepository: commerceRepository,
      commerceCatalogRepository: commerceCatalogRepository,
      alipayAppPayAdapter: alipayAppPayAdapter,
      messageRepository: messageRepository,
      roomRepository: roomRepository,
      roomOperationsRepository: roomOperationsRepository,
      roomLifecycleRepository: roomLifecycleRepository,
      roomPkRepository: roomPkRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
      roomAudioService: roomAudioService,
      externalUrlOpener: externalUrlOpener,
    );
  }

  final AppEnvironment environment;
  final AuthSessionManager sessionManager;
  final AuthController authController;
  final ImSessionAdapter imSessionAdapter;
  final ImSessionCredentialRepository imSessionCredentialRepository;
  final ImSessionCoordinator imSessionCoordinator;
  final ImAuthoritativeRefreshBus imAuthoritativeRefreshBus;
  final TencentImAvChatRoomCoordinator tencentImAvChatRoomCoordinator;
  final DateTime Function() currentTime;
  final LiveReadOnlyRepository liveReadOnlyRepository;
  final AccountComplianceRepository accountComplianceRepository;
  final DiscoveryRepository discoveryRepository;
  final DynamicRepository dynamicRepository;
  final SocialRepository socialRepository;
  final CommunityRepository communityRepository;
  final CommerceRepository commerceRepository;
  final CommerceCatalogRepository commerceCatalogRepository;
  final AlipayAppPayAdapter alipayAppPayAdapter;
  final MessageRepository messageRepository;
  final RoomRepository roomRepository;
  final RoomOperationsRepository roomOperationsRepository;
  final RoomLifecycleRepository roomLifecycleRepository;
  final RoomPkRepository roomPkRepository;
  final RtcAdapter rtcAdapter;
  final RoomRealtimeGateway realtimeGateway;
  final RoomAudioService roomAudioService;
  final ExternalUrlOpener externalUrlOpener;

  /// Releases process-scoped controllers when the app/test tree is torn down.
  /// In particular, the IM coordinator owns a renewal Timer; leaving it
  /// alive after a widget test would make Flutter report a pending timer even
  /// though the visible tree has been disposed.
  void dispose() {
    authController.dispose();
    imSessionCoordinator.dispose();
    unawaited(tencentImAvChatRoomCoordinator.dispose());
    final ImSessionAdapter adapter = imSessionAdapter;
    if (adapter is TencentImSessionAdapter) {
      unawaited(adapter.dispose());
    } else if (adapter is FakeImSessionAdapter) {
      unawaited(adapter.dispose());
    }
  }

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
      roomOperationsRepository: roomOperationsRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
      allowSyntheticPublicMessages: !environment.isLive,
      tencentImAvChatRoomCoordinator: tencentImAvChatRoomCoordinator,
    );
  }
}
