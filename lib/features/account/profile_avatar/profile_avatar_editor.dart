import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/media/media_identity.dart';
import '../../../core/media/media_models.dart';
import '../../../core/media/profile_avatar_transport.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../features/media/app_image_media_host.dart';
import '../domain/preset_avatar.dart';
import '../domain/user_avatar_descriptor.dart';

const String _presetPath = '/app-register-api/media/v1/avatar-presets';
const String _personalDataPath = '/app-api/user/getPersonalData';
const String _bindPath = '/app-api/user/profile/avatar';

enum ProfileAvatarChoiceKind { preset, uploaded }

final class ProfileAvatarChoice {
  const ProfileAvatarChoice._({
    required this.kind,
    required this.reference,
    required this.expectedVersion,
  });

  factory ProfileAvatarChoice.preset(String reference) {
    if (PresetAvatars.byId(reference) == null) throw mediaProtocol();
    return ProfileAvatarChoice._(
      kind: ProfileAvatarChoiceKind.preset,
      reference: reference,
      expectedVersion: null,
    );
  }

  factory ProfileAvatarChoice.uploaded({
    required String assetId,
    required int version,
  }) {
    if (version < 0) throw mediaProtocol();
    return ProfileAvatarChoice._(
      kind: ProfileAvatarChoiceKind.uploaded,
      reference: requireMediaId(assetId),
      expectedVersion: version,
    );
  }

  final ProfileAvatarChoiceKind kind;
  final String reference;
  final int? expectedVersion;

  Map<String, Object?> toBindBody(int expectedAvatarRevision) {
    if (expectedAvatarRevision < 0) throw mediaProtocol();
    return switch (kind) {
      ProfileAvatarChoiceKind.preset => {
        'kind': 'PRESET',
        'reference': reference,
        'expectedAvatarRevision': expectedAvatarRevision,
      },
      ProfileAvatarChoiceKind.uploaded => {
        'kind': 'UPLOADED',
        'reference': reference,
        'expectedVersion': expectedVersion!,
        'expectedAvatarRevision': expectedAvatarRevision,
      },
    };
  }

  bool matches(UserAvatarDescriptor? descriptor) {
    if (descriptor == null) return false;
    return switch (kind) {
      ProfileAvatarChoiceKind.preset =>
        descriptor.kind == UserAvatarKind.preset &&
            descriptor.reference == reference &&
            descriptor.version == null,
      ProfileAvatarChoiceKind.uploaded =>
        descriptor.kind == UserAvatarKind.uploaded &&
            descriptor.reference == reference &&
            descriptor.version == expectedVersion,
    };
  }
}

/// The own-profile projection is the only source used by the editor for the
/// current avatar. Legacy URL fields, if present, are intentionally ignored.
final class ProfileAvatarSnapshot {
  const ProfileAvatarSnapshot({
    required this.avatarRevision,
    required this.avatar,
  });

  final int avatarRevision;
  final UserAvatarDescriptor? avatar;

  static ProfileAvatarSnapshot fromPersonalData(Object? raw) {
    final map = _profileMap(raw);
    if (!map.containsKey('avatarRevision') || !map.containsKey('avatar')) {
      throw mediaProtocol();
    }
    final revision = map['avatarRevision'];
    if (revision is! int || revision < 0) throw mediaProtocol();
    final value = map['avatar'];
    final descriptor = value == null
        ? null
        : UserAvatarDescriptor.fromBackendData(value);
    // A null descriptor means that no avatar is currently displayable. The
    // revision remains authoritative and may be positive after an uploaded
    // avatar is revoked or is no longer READY; the parser never invents a
    // descriptor when the field is null.
    return ProfileAvatarSnapshot(avatarRevision: revision, avatar: descriptor);
  }
}

final class ProfileAvatarBindReceipt {
  const ProfileAvatarBindReceipt({
    required this.avatarRevision,
    required this.avatar,
  });

  final int avatarRevision;
  final UserAvatarDescriptor avatar;

  static ProfileAvatarBindReceipt fromData(Object? raw) {
    final map = _profileMap(raw);
    if (map.length != 2 ||
        !map.containsKey('avatarRevision') ||
        !map.containsKey('avatar')) {
      throw mediaProtocol();
    }
    final revision = map['avatarRevision'];
    if (revision is! int || revision < 1 || map['avatar'] == null) {
      throw mediaProtocol();
    }
    return ProfileAvatarBindReceipt(
      avatarRevision: revision,
      avatar: UserAvatarDescriptor.fromBackendData(map['avatar']),
    );
  }
}

final class ProfileAvatarApi {
  ProfileAvatarApi({
    required this.apiClient,
    ProfileAvatarMediaTransport? mediaTransport,
  }) : mediaTransport =
           mediaTransport ?? ApiProfileAvatarMediaTransport(apiClient);

  final ApiClient apiClient;
  final ProfileAvatarMediaTransport mediaTransport;

  Future<List<String>> fetchPresetIds() async {
    final response = await apiClient.get(_presetPath, authenticated: false);
    final map = _profileMap(response.data);
    if (map.length != 1 || !map.containsKey('presets')) throw mediaProtocol();
    final raw = map['presets'];
    if (raw is! List) throw mediaProtocol();
    final ids = <String>[];
    for (final value in raw) {
      if (value is! String ||
          PresetAvatars.byId(value) == null ||
          ids.contains(value)) {
        throw mediaProtocol();
      }
      ids.add(value);
    }
    if (ids.isEmpty) throw mediaProtocol();
    return List.unmodifiable(ids);
  }

  Future<ProfileAvatarSnapshot> readCurrentAvatar(
    MediaIdentityScope identity,
  ) async {
    final response = await apiClient.getBoundToIdentity(
      _personalDataPath,
      requireIdentity: identity.check,
    );
    identity.check();
    return ProfileAvatarSnapshot.fromPersonalData(response.data);
  }

  Future<MediaAssetStatus> allocateUpload({
    required MediaIdentityScope identity,
    required String requestId,
  }) async {
    final response = await mediaTransport.allocateUpload(
      identity: identity,
      requestId: requestId,
    );
    identity.check();
    return _avatarStatus(response.data);
  }

  Future<MediaAssetStatus> statusUpload({
    required MediaIdentityScope identity,
    required String assetId,
  }) async {
    final response = await mediaTransport.statusUpload(
      identity: identity,
      assetId: assetId,
    );
    identity.check();
    return _avatarStatus(response.data);
  }

  Future<MediaAssetStatus> putUploadContent({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
    required int bytes,
    required Stream<List<int>> Function() content,
  }) async {
    final response = await mediaTransport.putUploadContent(
      identity: identity,
      assetId: assetId,
      expectedVersion: expectedVersion,
      bytes: bytes,
      content: content,
    );
    identity.check();
    return _avatarStatus(response.data);
  }

  Future<MediaAssetStatus> completeUpload({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
  }) async {
    final response = await mediaTransport.completeUpload(
      identity: identity,
      assetId: assetId,
      expectedVersion: expectedVersion,
    );
    identity.check();
    return _avatarStatus(response.data);
  }

  Future<ProfileAvatarBindReceipt> bindAvatar({
    required MediaIdentityScope identity,
    required ProfileAvatarChoice choice,
    required int expectedAvatarRevision,
    required String requestId,
  }) async {
    if (!isProfileAvatarRequestId(requestId)) throw mediaProtocol();
    final response = await apiClient.putBoundToIdentity(
      _bindPath,
      requireIdentity: identity.check,
      headers: <String, String>{'X-Request-Id': requestId},
      requestId: requestId,
      stripContentEncoding: true,
      body: choice.toBindBody(expectedAvatarRevision),
    );
    identity.check();
    // This is a historical idempotency receipt. Callers must reread the own
    // projection before changing any displayed avatar state.
    return ProfileAvatarBindReceipt.fromData(response.data);
  }

  static MediaAssetStatus _avatarStatus(Object? raw) {
    final value = MediaAssetStatus.fromJson(raw);
    if (value.purpose != MediaPurpose.avatar) throw mediaProtocol();
    return value;
  }
}

enum ProfileAvatarUploadState {
  idle,
  loading,
  picked,
  uploading,
  binding,
  rereading,
  saved,
  failed,
}

final class ProfileAvatarEditor extends ChangeNotifier {
  ProfileAvatarEditor({required this.api, required this.imageHost})
    : _owner = imageHost.identity,
      _draft = imageHost.draft('profile-avatar', MediaPurpose.avatar) {
    imageHost.addListener(_hostChanged);
  }

  final ProfileAvatarApi api;
  final AppImageMediaHost imageHost;
  final (int, int) _owner;
  final ImageDraft _draft;

  ProfileAvatarSnapshot? _current;
  List<String> _availablePresetIds = const <String>[];
  String? _selectedPresetId;
  ProfileAvatarUploadState _uploadState = ProfileAvatarUploadState.idle;
  String? _error;
  String? _notice;
  bool _loaded = false;
  bool _loading = false;
  bool _saving = false;
  bool _closed = false;
  Future<void>? _loadFlight;
  Future<ProfileAvatarSnapshot>? _saveFlight;
  String? _bindFingerprint;
  String? _bindRequestId;

  ProfileAvatarSnapshot? get current => _current;
  bool get hasCurrentSnapshot => _loaded;
  List<String> get availablePresetIds => _availablePresetIds;
  String? get selectedPresetId => _selectedPresetId;
  bool get hasSelectedImage => _draft.images.length == 1;
  ProfileAvatarUploadState get uploadState => _uploadState;
  String? get error => _error;
  String? get notice => _notice;
  bool get busy =>
      _loading ||
      _saving ||
      _draft.picking ||
      _draft.images.any((image) => image.flight != null);

  bool get _ownerCurrent => !_closed && imageHost.identity == _owner;

  MediaIdentityScope _requireOwner() {
    if (!_ownerCurrent) throw MediaIdentityScope.invalid;
    final scope = imageHost.scope;
    scope.check();
    return scope;
  }

  Future<void> load() {
    if (_closed) return Future<void>.error(MediaIdentityScope.invalid);
    if (!_ownerCurrent) return Future<void>.error(MediaIdentityScope.invalid);
    if (_loaded) return Future<void>.value();
    return _startLoad(recoverUpload: false);
  }

  /// Explicit read-only recovery. A lost upload/inspection response keeps its
  /// original asset; this action never allocates, resends bytes or binds it.
  Future<void> reload() {
    if (!_ownerCurrent) return Future<void>.error(MediaIdentityScope.invalid);
    if (busy) return _loadFlight ?? Future<void>.value();
    return _startLoad(recoverUpload: true);
  }

  Future<void> _startLoad({required bool recoverUpload}) {
    final existing = _loadFlight;
    if (existing != null) return existing;
    late Future<void> flight;
    flight = _loadInternal(recoverUpload: recoverUpload).whenComplete(() {
      if (identical(_loadFlight, flight)) _loadFlight = null;
    });
    _loadFlight = flight;
    return flight;
  }

  Future<void> _loadInternal({required bool recoverUpload}) async {
    _loading = true;
    _uploadState = ProfileAvatarUploadState.loading;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final scope = _requireOwner();
      final snapshot = await api.readCurrentAvatar(scope);
      _requireOwner();
      final presetIds = await api.fetchPresetIds();
      _requireOwner();
      final pending = hasSelectedImage ? _draft.images.single : null;
      if (recoverUpload && pending?.status != null) {
        await imageHost.upload(
          _draft,
          pending!,
          recover: true,
          identity: scope,
        );
        _requireOwner();
      }
      final alreadyBound =
          pending?.status?.state == MediaAssetState.ready &&
          snapshot.avatar?.kind == UserAvatarKind.uploaded &&
          snapshot.avatar?.reference == pending!.status!.assetId &&
          snapshot.avatar?.version == pending.status!.version;
      if (alreadyBound) {
        imageHost.remove(_draft, pending);
        _resetBindRequest();
      }
      _current = snapshot;
      _availablePresetIds = presetIds;
      _selectedPresetId =
          !hasSelectedImage && snapshot.avatar?.kind == UserAvatarKind.preset
          ? snapshot.avatar!.reference
          : null;
      _loaded = true;
      _error = pending?.error;
      _uploadState = alreadyBound
          ? ProfileAvatarUploadState.saved
          : _error != null
          ? ProfileAvatarUploadState.failed
          : hasSelectedImage
          ? ProfileAvatarUploadState.picked
          : ProfileAvatarUploadState.idle;
      if (recoverUpload && pending?.status != null) {
        _notice = alreadyBound
            ? '头像已保存，已读取最新头像'
            : pending!.status!.state == MediaAssetState.ready
            ? '图片已处理完成，点击保存头像后生效'
            : '已读取原图片状态；尚未绑定头像，可稍后继续保存';
      }
      notifyListeners();
    } catch (error) {
      if (_ownerCurrent) {
        _uploadState = ProfileAvatarUploadState.failed;
        _error = _avatarError(error);
        notifyListeners();
      }
      rethrow;
    } finally {
      _loading = false;
      if (_ownerCurrent) notifyListeners();
    }
  }

  void choosePreset(String presetId) {
    _requireOwner();
    if (!_loaded || !_availablePresetIds.contains(presetId)) {
      throw mediaProtocol();
    }
    if (busy) return;
    _removeImages();
    _selectedPresetId = presetId;
    _resetBindRequest();
    _error = null;
    _notice = null;
    _uploadState = ProfileAvatarUploadState.picked;
    notifyListeners();
  }

  Future<void> chooseImage() async {
    final scope = _requireOwner();
    if (!_loaded || busy) return;
    _removeImages();
    _selectedPresetId = null;
    _resetBindRequest();
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await imageHost.pick(_draft, identity: scope);
      _requireOwner();
      _uploadState = hasSelectedImage
          ? ProfileAvatarUploadState.picked
          : ProfileAvatarUploadState.idle;
      notifyListeners();
    } catch (error) {
      if (_ownerCurrent) {
        _uploadState = ProfileAvatarUploadState.failed;
        _error = _avatarError(error);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<ProfileAvatarSnapshot> save() {
    if (_closed)
      return Future<ProfileAvatarSnapshot>.error(MediaIdentityScope.invalid);
    final existing = _saveFlight;
    if (existing != null) return existing;
    late Future<ProfileAvatarSnapshot> flight;
    flight = _saveInternal().whenComplete(() {
      if (identical(_saveFlight, flight)) _saveFlight = null;
    });
    _saveFlight = flight;
    return flight;
  }

  Future<ProfileAvatarSnapshot> _saveInternal() async {
    _saving = true;
    _error = null;
    _notice = null;
    try {
      if (!_loaded) await load();
      final scope = _requireOwner();
      final before = _current;
      if (before == null) throw mediaProtocol();

      final ProfileAvatarChoice choice;
      ImageUpload? uploaded;
      if (_selectedPresetId != null) {
        choice = ProfileAvatarChoice.preset(_selectedPresetId!);
      } else {
        final images = _draft.images;
        if (images.length != 1) throw mediaProtocol();
        uploaded = images.single;
        if (uploaded.status?.state != MediaAssetState.ready ||
            uploaded.status!.isExpired(DateTime.now())) {
          _uploadState = ProfileAvatarUploadState.uploading;
          notifyListeners();
          await imageHost.upload(
            _draft,
            uploaded,
            recover: false,
            identity: scope,
          );
          _requireOwner();
          if (uploaded.status?.state == MediaAssetState.uploading ||
              uploaded.status?.state == MediaAssetState.quarantined) {
            await imageHost.upload(_draft, uploaded, identity: scope);
            _requireOwner();
          }
        }
        final ready = _draft.ready;
        if (ready.length != 1) throw mediaProtocol();
        choice = ProfileAvatarChoice.uploaded(
          assetId: ready.single.assetId,
          version: ready.single.version,
        );
      }

      _requireOwner();
      final fingerprint = jsonEncode([
        choice.kind.name,
        choice.reference,
        choice.expectedVersion,
        before.avatarRevision,
      ]);
      if (_bindFingerprint != fingerprint) {
        _bindFingerprint = fingerprint;
        _bindRequestId = _newBindRequestId();
      }
      _uploadState = ProfileAvatarUploadState.binding;
      notifyListeners();
      await api.bindAvatar(
        identity: scope,
        choice: choice,
        expectedAvatarRevision: before.avatarRevision,
        requestId: _bindRequestId!,
      );
      _requireOwner();

      _uploadState = ProfileAvatarUploadState.rereading;
      notifyListeners();
      final after = await api.readCurrentAvatar(scope);
      _requireOwner();
      final bool choiceApplied =
          after.avatarRevision == before.avatarRevision + 1 &&
          choice.matches(after.avatar);
      _current = after;
      _selectedPresetId = after.avatar?.kind == UserAvatarKind.preset
          ? after.avatar!.reference
          : null;
      if (uploaded != null) imageHost.remove(_draft, uploaded);
      _resetBindRequest();
      _uploadState = ProfileAvatarUploadState.saved;
      _error = null;
      _notice = choiceApplied ? null : '头像已被其他更新覆盖，已展示最新头像';
      notifyListeners();
      return after;
    } catch (error) {
      // Keep the last authoritative snapshot untouched. A bind failure or a
      // failed reread must not make the old avatar disappear from the page.
      if (_ownerCurrent) {
        _uploadState = ProfileAvatarUploadState.failed;
        _error = _avatarError(error);
        notifyListeners();
      }
      rethrow;
    } finally {
      _saving = false;
      if (_ownerCurrent) notifyListeners();
    }
  }

  void _removeImages() {
    for (final image in _draft.images.toList()) {
      imageHost.remove(_draft, image);
    }
  }

  void _resetBindRequest() {
    _bindFingerprint = null;
    _bindRequestId = null;
  }

  void _hostChanged() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    imageHost.removeListener(_hostChanged);
    super.dispose();
  }
}

Map<String, Object?> _profileMap(Object? raw) {
  if (raw is! Map || raw.keys.any((key) => key is! String)) {
    throw mediaProtocol();
  }
  return <String, Object?>{for (final key in raw.keys) key as String: raw[key]};
}

String _avatarError(Object error) =>
    error is ApiException ? error.message : '头像操作未完成，请检查图片权限或网络后重试';

String _newBindRequestId() {
  final random = Random.secure();
  final entropy = List<String>.generate(
    32,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  return 'flutter-profile-avatar-bind-$entropy';
}
