import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../features/media/app_image_media_host.dart';
import '../features/media/native_image_selection.dart';
import '../features/account/registration_avatar/registration_avatar_host.dart';
import '../features/account/registration_avatar/registration_avatar_transport_adapter.dart';

import 'package:flutter/widgets.dart';
import 'package:voice_social_app/features/room/application/gift_send_coordinator.dart';
import 'package:voice_social_app/features/room/domain/gift_send_models.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
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
import 'package:voice_social_app/features/commerce/application/apple_iap_purchase_coordinator.dart';
import 'package:voice_social_app/features/commerce/data/backend_apple_iap_port.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';
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
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_rtc_token_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/infrastructure/native_room_background_audio.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

import 'package:voice_social_app/features/media/private_media_host.dart';
import 'package:voice_social_app/features/media/private_media_native.dart';
import 'package:voice_social_app/features/media/private_media_temporary_root.dart';

class AppDependencies {
  AppDependencies._({
    required this.imageMediaHost,
    required this.privateMediaHost,
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
    required this.appleIapStoreKit2Adapter,
    required this.appleIapPurchaseCoordinator,
    required this.messageRepository,
    required this.roomRepository,
    required this.giftSendCoordinator,
    required this.roomOperationsRepository,
    required this.roomLifecycleRepository,
    required this.platformRoomRepository,
    required this.roomPkRepository,
    required this.rtcAdapter,
    required NativeRoomBackgroundAudio? backgroundAudio,
    required this.realtimeGateway,
    required this.roomAudioService,
    required this.externalUrlOpener,
  }) : _backgroundAudio = backgroundAudio;

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
    AppImageMediaHost? imageMediaHost,
    PrivateMediaHost? privateMediaHost,
    MessageRepository? messageRepository,
    ExternalUrlOpener? externalUrlOpener,
    ImSessionAdapter? imSessionAdapter,
    ImSessionCredentialRepository? imSessionCredentialRepository,
    ImSessionCoordinator? imSessionCoordinator,
    ImAuthoritativeRefreshBus? imAuthoritativeRefreshBus,
    TencentImAvChatRoomCoordinator? tencentImAvChatRoomCoordinator,
    AppleIapStoreKit2Adapter? appleIapStoreKit2Adapter,
    Duration? alipayNativeTimeout,
  }) {
    return _build(
      environment: environment,
      store: MemoryKeyValueStore(initialStorage),
      mockNow: mockNow,
      accountComplianceRepositoryOverride: accountComplianceRepository,
      discoveryRepositoryOverride: discoveryRepository,
      dynamicRepositoryOverride: dynamicRepository,
      imageMediaHostOverride: imageMediaHost,
      privateMediaHostOverride: privateMediaHost,
      messageRepositoryOverride: messageRepository,
      externalUrlOpenerOverride: externalUrlOpener,
      imSessionAdapterOverride: imSessionAdapter,
      imSessionCredentialRepositoryOverride: imSessionCredentialRepository,
      imSessionCoordinatorOverride: imSessionCoordinator,
      imAuthoritativeRefreshBusOverride: imAuthoritativeRefreshBus,
      tencentImAvChatRoomCoordinatorOverride: tencentImAvChatRoomCoordinator,
      appleIapStoreKit2AdapterOverride: appleIapStoreKit2Adapter,
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
    AppImageMediaHost? imageMediaHostOverride,
    PrivateMediaHost? privateMediaHostOverride,
    MessageRepository? messageRepositoryOverride,
    ExternalUrlOpener? externalUrlOpenerOverride,
    ImSessionAdapter? imSessionAdapterOverride,
    ImSessionCredentialRepository? imSessionCredentialRepositoryOverride,
    ImSessionCoordinator? imSessionCoordinatorOverride,
    ImAuthoritativeRefreshBus? imAuthoritativeRefreshBusOverride,
    TencentImAvChatRoomCoordinator? tencentImAvChatRoomCoordinatorOverride,
    AppleIapStoreKit2Adapter? appleIapStoreKit2AdapterOverride,
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
                currentUserIdProvider: () => sessionManager.session?.userId,
                identityGeneration: () => sessionManager.identityGeneration,
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
    final bool appleIapEnabled =
        environment.isLive &&
        environment.enableAppleIap &&
        environment.clientType.trim().toLowerCase() == 'ios';
    final AppleIapStoreKit2Adapter appleIapStoreKit2Adapter = appleIapEnabled
        ? appleIapStoreKit2AdapterOverride ??
              MethodChannelAppleIapStoreKit2Adapter()
        : const DisabledAppleIapStoreKit2Adapter();
    final AppleIapPurchaseCoordinator? appleIapPurchaseCoordinator =
        appleIapEnabled
        ? AppleIapPurchaseCoordinator(
            purchaseStore: store,
            storeKit: appleIapStoreKit2Adapter,
            backend: BackendAppleIapPort(apiClient: apiClient, routes: routes),
            authenticatedSession: () => sessionManager.session,
            authenticatedAccount: () =>
                sessionManager.session?.userId.toString(),
          )
        : null;
    appleIapPurchaseCoordinator?.startListening();
    final DiscoveryRepository discoveryRepository =
        discoveryRepositoryOverride ??
        (environment.isLive
            ? BackendDiscoveryRepository(
                apiClient: apiClient,
                clientType: environment.clientType,
                currentUserIdProvider: () =>
                    sessionManager.session?.userId ?? 0,
                identityGeneration: () => sessionManager.identityGeneration,
                routes: routes,
              )
            : MockDiscoveryRepository());
    final DynamicRepository dynamicRepository =
        dynamicRepositoryOverride ??
        (environment.isLive
            ? BackendDynamicRepository(
                apiClient: apiClient,
                routes: routes,
                identityGeneration: () => sessionManager.identityGeneration,
                commentIdentityChanges: sessionManager,
                currentUserIdProvider: () =>
                    sessionManager.session?.userId ?? 0,
              )
            : MockDynamicRepository());
    final SocialRepository socialRepository = environment.isLive
        ? BackendSocialRepository(
            apiClient: apiClient,
            identityGeneration: () => sessionManager.identityGeneration,
            currentUserIdProvider: () => sessionManager.session?.userId ?? 0,
            routes: routes,
          )
        : MockSocialRepository();
    final CommunityRepository communityRepository = environment.isLive
        ? BackendCommunityRepository(
            apiClient: apiClient,
            routes: routes,
            currentUserIdProvider: () => sessionManager.session?.userId,
            identityGeneration: () => sessionManager.identityGeneration,
          )
        : MockCommunityRepository();
    late final CommerceRepository commerceRepository;
    late final CommerceCatalogRepository commerceCatalogRepository;
    if (environment.isLive) {
      commerceRepository = BackendCommerceRepository(
        apiClient: apiClient,
        routes: routes,
        currentUserId: () => sessionManager.session?.userId.toString(),
        identityGeneration: () => sessionManager.identityGeneration,
        withdrawalIdentityChanges: sessionManager,
      );
      commerceCatalogRepository = BackendCommerceCatalogRepository(
        apiClient: apiClient,
        routes: routes,
        currentUserIdProvider: () => sessionManager.session?.userId,
        identityGeneration: () => sessionManager.identityGeneration,
        alipayAppPayAdapter: alipayAppPayAdapter,
        appleIapCoordinator: appleIapPurchaseCoordinator,
      );
    } else {
      final MockCommerceRepository mockCommerceRepository =
          MockCommerceRepository(now: mockNow);
      commerceRepository = mockCommerceRepository;
      commerceCatalogRepository = MockCommerceCatalogRepository(
        now: currentTime,
        onRechargeOrderChanged: mockCommerceRepository.syncRechargeOrder,
      );
    }
    final MessageRepository messageRepository =
        messageRepositoryOverride ??
        (environment.isLive
            ? BackendMessageRepository(
                apiClient: apiClient,
                routes: routes,
                identityGenerationProvider: () =>
                    sessionManager.identityGeneration,
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
    final roomLeaseBinding = RoomLeaseBinding(
      authenticationGeneration: () => sessionManager.identityGeneration,
    );
    late final AuthController authController;
    final RoomLifecycleRepository roomLifecycleRepository = environment.isLive
        ? BackendRoomLifecycleRepository(
            apiClient: apiClient,
            routes: routes,
            leaseBinding: roomLeaseBinding,
          )
        : MockRoomLifecycleRepository();
    final RoomRepository roomRepository = environment.isLive
        ? BackendRoomRepository(
            apiClient: apiClient,
            routes: routes,
            rtcTokenRepository: rtcTokenRepository,
            leaseBinding: roomLeaseBinding,
            prepareAccessSession: () =>
                authController.ensureFreshAccessSession(),
            now: currentTime,
          )
        : MockRoomRepository(
            lifecycleRepository: roomLifecycleRepository,
            giftUnitPrice: (id) async =>
                (await commerceCatalogRepository.fetchGiftCatalog())
                    .where((gift) => gift.enabled && gift.id == id)
                    .firstOrNull
                    ?.price,
            readGiftCoins: () =>
                (commerceRepository as MockCommerceRepository).giftCoins,
            writeGiftCoins: (amount) =>
                (commerceRepository as MockCommerceRepository).giftCoins =
                    amount,
          );
    final RoomOperationsRepository roomOperationsRepository = environment.isLive
        ? BackendRoomOperationsRepository(
            apiClient: apiClient,
            routes: routes,
            leaseBinding: roomLeaseBinding,
          )
        : MockRoomOperationsRepository(
            micCoordinationMode: MicCoordinationMode.approval,
          );
    final RoomPkRepository roomPkRepository = environment.isLive
        ? BackendRoomPkRepository(apiClient: apiClient, routes: routes)
        : MockRoomPkRepository();
    final NativeRoomBackgroundAudio? backgroundAudio =
        environment.isLive && rtcTokenRepository != null
        ? NativeRoomBackgroundAudio.forCurrentPlatform()
        : null;
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
                  backgroundAudioPort: backgroundAudio,
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
    authController = AuthController(
      repository: authRepository,
      sessionManager: sessionManager,
      deviceIdentityProvider: deviceIdentityProvider,
      imSessionCoordinator: imSessionCoordinator,
      allowsDevelopmentTools:
          environment.deploymentEnvironment.allowsDevelopmentTools,
      registrationAvatarClientId: environment.oauthClientId,
      registrationAvatarFactory: environment.isLive
          ? (context) => RegistrationAvatarHost(
              context: context,
              transport: ApiRegistrationAvatarTransport(apiClient),
              store: store,
              picker: NativeImageSelection(),
              temporaryParent: getTemporaryDirectory,
            )
          : null,
    );
    final ExternalUrlOpener externalUrlOpener =
        externalUrlOpenerOverride ?? MethodChannelExternalUrlOpener();
    apiClient.setUnauthorizedRecovery(authController.refreshSession);
    final privateMediaTemporary = PrivateMediaTemporaryRoot(
      getTemporaryDirectory,
    );
    return AppDependencies._(
      privateMediaHost:
          privateMediaHostOverride ??
          PrivateMediaHost(
            api: apiClient,
            store: store,
            userId: () => sessionManager.session?.userId ?? 0,
            generation: () => sessionManager.identityGeneration,
            changes: sessionManager,
            temporaryParent: privateMediaTemporary.get,
            inputFactory: () => NativePrivateMediaInput(
              temporaryParent: privateMediaTemporary.get,
            ),
            playerFactory: NativePrivateLocalPlayer.new,
            enabled: environment.isLive,
          ),
      imageMediaHost:
          imageMediaHostOverride ??
          AppImageMediaHost(
            api: apiClient,
            userId: () => sessionManager.session?.userId ?? 0,
            generation: () => sessionManager.identityGeneration,
            changes: sessionManager,
            picker: NativeImageSelection(),
            temporaryParent: getTemporaryDirectory,
            enabled: environment.isLive,
          ),
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
      appleIapStoreKit2Adapter: appleIapStoreKit2Adapter,
      appleIapPurchaseCoordinator: appleIapPurchaseCoordinator,
      messageRepository: messageRepository,
      roomRepository: roomRepository,
      giftSendCoordinator: GiftSendCoordinator(
        repository: roomRepository as GiftCommandRepository,
        store: store,
        storageScope: Uri.encodeComponent(environment.apiBaseUrl),
        identity: () => (
          sessionManager.session?.userId ?? (environment.isLive ? null : 10001),
          sessionManager.identityGeneration,
        ),
        identityChanges: sessionManager,
      ),
      roomOperationsRepository: roomOperationsRepository,
      roomLifecycleRepository: roomLifecycleRepository,
      platformRoomRepository: environment.isLive
          ? BackendPlatformRoomRepository(
              apiClient: apiClient,
              routes: routes,
              identity: () => (
                sessionManager.session?.userId ?? 0,
                sessionManager.identityGeneration,
              ),
              identityChanges: sessionManager,
            )
          : UnboundPlatformRoomRepository(
              sessionManager,
              () => (
                sessionManager.session?.userId ?? 0,
                sessionManager.identityGeneration,
              ),
            ),
      roomPkRepository: roomPkRepository,
      rtcAdapter: rtcAdapter,
      backgroundAudio: backgroundAudio,
      realtimeGateway: realtimeGateway,
      roomAudioService: roomAudioService,
      externalUrlOpener: externalUrlOpener,
    );
  }

  final AppEnvironment environment;
  final AppImageMediaHost? imageMediaHost;
  final PrivateMediaHost privateMediaHost;
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
  final AppleIapStoreKit2Adapter appleIapStoreKit2Adapter;
  final AppleIapPurchaseCoordinator? appleIapPurchaseCoordinator;
  final MessageRepository messageRepository;
  final RoomRepository roomRepository;
  final GiftSendCoordinator giftSendCoordinator;
  final RoomOperationsRepository roomOperationsRepository;
  final RoomLifecycleRepository roomLifecycleRepository;
  final PlatformRoomRepository platformRoomRepository;
  final RoomPkRepository roomPkRepository;
  final RtcAdapter rtcAdapter;
  final NativeRoomBackgroundAudio? _backgroundAudio;
  Future<void>? _rtcRuntimeRelease;
  final RoomRealtimeGateway realtimeGateway;
  final RoomAudioService roomAudioService;
  final ExternalUrlOpener externalUrlOpener;

  final ValueNotifier<int> complianceRevision = ValueNotifier<int>(0);
  bool? _youthModeResult;
  int? _youthResultIdentity;
  bool _disposed = false;
  bool _protectedAccessBlocked = false;
  final List<WeakReference<RoomController>> _roomControllers = [];

  bool? get youthModeResult =>
      _youthResultIdentity == sessionManager.identityGeneration
      ? _youthModeResult
      : null;

  /// Only a matching first-party result may release the youth lock. No PIN
  /// is retained here; stale responses never notify a different identity.
  Future<void> changeYouthMode({
    required bool enabled,
    required String pin,
  }) async {
    if (_disposed || sessionManager.session == null)
      throw StateError('登录状态已变化');
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请输入 4 位数字密码',
      );
    }
    final identity = sessionManager.identityGeneration;
    final userId = sessionManager.session?.userId;
    bool current() =>
        !_disposed &&
        identity == sessionManager.identityGeneration &&
        userId == sessionManager.session?.userId;
    try {
      final result = await accountComplianceRepository.setYouthMode(
        enabled: enabled,
        pin: pin,
      );
      if (!current()) throw StateError('登录状态已变化');
      if (result != enabled) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '青少年模式状态未确认，请重试',
        );
      }
      _youthModeResult = result;
      _youthResultIdentity = identity;
      complianceRevision.value++;
    } catch (_) {
      // An enable response may be lost after a committed write. Recheck the
      // gate before returning to business; failed unlocks keep the lock.
      if (enabled && current()) {
        _youthModeResult = null;
        _youthResultIdentity = identity;
        complianceRevision.value++;
      }
      rethrow;
    }
  }

  void setProtectedAccessBlocked(bool blocked) {
    if (_disposed || _protectedAccessBlocked == blocked) return;
    _protectedAccessBlocked = blocked;
    final cleanup = imSessionCoordinator.setAccessBlocked(blocked);
    if (blocked) {
      for (final reference in _roomControllers) {
        reference.target?.dispose();
      }
      _roomControllers.clear();
      unawaited(
        tencentImAvChatRoomCoordinator.leave().catchError((Object _) {}),
      );
    } else {
      final identity = sessionManager.identityGeneration;
      unawaited(
        cleanup
            .then((_) async {
              final session = sessionManager.session;
              if (!_disposed &&
                  !_protectedAccessBlocked &&
                  session != null &&
                  identity == sessionManager.identityGeneration) {
                await imSessionCoordinator.ensureAuthenticated(session);
              }
            })
            .catchError((Object _) {}),
      );
    }
  }

  /// Replays StoreKit's durable unfinished queue only after first-party
  /// authentication is active. Failures remain recoverable and must not block
  /// the signed-in app shell.
  Future<bool> recoverAppleIapAfterAuthentication() async {
    final AppleIapPurchaseCoordinator? coordinator =
        appleIapPurchaseCoordinator;
    if (coordinator == null) {
      return true;
    }
    if (sessionManager.session == null) {
      return false;
    }
    try {
      final result = await coordinator.recoverUnfinished();
      return result.deferred == 0;
    } catch (_) {
      // StoreKit retains unfinished transactions. A later sign-in/catalog
      // refresh can retry without falsely finishing or crediting the client.
      return false;
    }
  }

  /// Releases process-scoped controllers when the app/test tree is torn down.
  /// In particular, the IM coordinator owns a renewal Timer; leaving it
  /// alive after a widget test would make Flutter report a pending timer even
  /// though the visible tree has been disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    imageMediaHost?.dispose();
    privateMediaHost.dispose();
    complianceRevision.dispose();
    giftSendCoordinator.dispose();
    for (final reference in _roomControllers) {
      reference.target?.dispose();
    }
    _roomControllers.clear();
    final repository = roomRepository;
    if (repository is BackendRoomRepository) {
      repository.leaseBinding.clear(repository.leaseBinding.generation);
    }
    authController.dispose();
    unawaited(_rtcRuntimeRelease ??= _releaseRtcRuntime());
    imSessionCoordinator.dispose();
    unawaited(tencentImAvChatRoomCoordinator.dispose());
    final AppleIapPurchaseCoordinator? appleCoordinator =
        appleIapPurchaseCoordinator;
    if (appleCoordinator != null) {
      unawaited(appleCoordinator.dispose());
    }
    final ImSessionAdapter adapter = imSessionAdapter;
    if (adapter is TencentImSessionAdapter) {
      unawaited(adapter.dispose());
    } else if (adapter is FakeImSessionAdapter) {
      unawaited(adapter.dispose());
    }
  }

  Future<void> _releaseRtcRuntime() async {
    var unconfirmed = false;
    try {
      final rtc = rtcAdapter;
      if (rtc is AgoraRtcAdapter) await rtc.release();
    } catch (_) {
      unconfirmed = true;
    }
    try {
      await _backgroundAudio?.dispose();
    } catch (_) {
      unconfirmed = true;
    }
    if (unconfirmed) {
      // No native error text, credentials or identifiers are logged.
      debugPrint('RTC_RUNTIME_SHUTDOWN_UNCONFIRMED');
    }
  }

  RoomController createRoomController({
    required String roomId,
    required String title,
  }) {
    if (_protectedAccessBlocked) throw StateError('App 当前已锁定，不能创建房间会话');
    final session = sessionManager.session;
    if (session == null && environment.isLive) {
      throw StateError('用户未登录，不能创建房间会话');
    }
    final controller = RoomController(
      roomId: roomId,
      title: title,
      currentUserId: session?.userId ?? 10001,
      accessToken: session?.accessToken ?? 'mock-local-session',
      repository: roomRepository,
      giftSendCoordinator: giftSendCoordinator,
      roomOperationsRepository: roomOperationsRepository,
      rtcAdapter: rtcAdapter,
      realtimeGateway: realtimeGateway,
      allowSyntheticPublicMessages: !environment.isLive,
      tencentImAvChatRoomCoordinator: tencentImAvChatRoomCoordinator,
      sessionChanges: environment.isLive ? sessionManager : null,
      identityGeneration: environment.isLive
          ? () => sessionManager.identityGeneration
          : null,
      activeUserId: environment.isLive
          ? () => sessionManager.session?.userId
          : null,
      lifecycleBinding: WidgetsBinding.instance,
    );
    _roomControllers.removeWhere((reference) => reference.target == null);
    _roomControllers.add(WeakReference(controller));
    return controller;
  }
}
