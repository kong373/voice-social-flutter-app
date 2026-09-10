import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/media/private_media_native.dart';
import 'support/media_http_fakes.dart';

class _Picker extends ImagePicker {
  ImageSource? source;
  bool? fullMetadata;
  int? quality;
  XFile? selected;
  Object? failure;
  Completer<void>? gate;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    fullMetadata = requestFullMetadata;
    quality = imageQuality;
    await gate?.future;
    if (failure != null) throw failure!;
    return selected;
  }

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    this.source = source;
    if (failure != null) throw failure!;
    return selected;
  }
}

class _LargeFile extends XFile {
  _LargeFile() : super('/not-opened');
  @override
  Future<int> length() async => 100000001;
}

class _Recorder extends RecordPlatform {
  bool permission = true;
  int starts = 0, cancels = 0, disposals = 0;
  String? path;
  RecordConfig? config;
  Completer<void>? permissionGate;
  final permissionEntered = Completer<void>();
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async {
    if (!permissionEntered.isCompleted) permissionEntered.complete();
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    starts++;
    this.config = config;
    this.path = path;
    await File(path).writeAsBytes([1, 2, 3]);
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<void> cancel(String recorderId) async {
    cancels++;
  }

  @override
  Future<void> dispose(String recorderId) async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  late TestMediaIdentity actor;
  late _Picker picker;
  late NativePrivateMediaInput input;
  late RecordPlatform previous;
  late _Recorder recorder;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('s13-native-contract-test-');
    actor = TestMediaIdentity();
    picker = _Picker();
    input = NativePrivateMediaInput(
      temporaryParent: () async => temp,
      picker: picker,
    );
    previous = RecordPlatform.instance;
    recorder = _Recorder();
    RecordPlatform.instance = recorder;
  });
  tearDown(() async {
    await input.dispose();
    RecordPlatform.instance = previous;
    actor.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  test(
    'real image plugin boundary uses gallery, no client recompression, cancellation is no selection',
    () async {
      final scope = actor.scope();
      addTearDown(scope.dispose);
      expect(await input.pick(MediaPurpose.privateImage, scope), isNull);
      expect(picker.source, ImageSource.gallery);
      expect(picker.fullMetadata, false);
      expect(picker.quality, isNull);
    },
  );
  test(
    'native permission rejection is explicit without native detail leakage',
    () async {
      picker.failure = PlatformException(
        code: 'photo_access_denied',
        message: 'private native detail',
      );
      final scope = actor.scope();
      addTearDown(scope.dispose);
      await expectLater(
        input.pick(MediaPurpose.privateImage, scope),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiFailureKind.forbidden)
              .having(
                (e) => e.message,
                'message',
                isNot(contains('private native detail')),
              ),
        ),
      );
    },
  );
  test(
    'native video selection enforces actual size before local decoder',
    () async {
      picker.selected = _LargeFile();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      await expectLater(
        input.pick(MediaPurpose.privateVideo, scope),
        throwsA(isA<ApiException>()),
      );
      expect(picker.source, ImageSource.gallery);
    },
  );
  test('native picker late A result after ABA is not accepted', () async {
    picker.gate = Completer<void>();
    final scope = actor.scope();
    addTearDown(scope.dispose);
    final result = input.pick(MediaPurpose.privateImage, scope);
    final rejected = expectLater(result, throwsA(isA<ApiException>()));
    actor.change(7);
    actor.change(1);
    picker.gate!.complete();
    await rejected;
  });
  test('real recorder permission denial never starts', () async {
    recorder.permission = false;
    final scope = actor.scope();
    addTearDown(scope.dispose);
    await expectLater(
      input.startRecording(scope),
      throwsA(isA<ApiException>()),
    );
    expect(recorder.starts, 0);
    expect(recorder.disposals, 1);
  });
  test(
    'real recorder start uses AAC local owned path, cancel removes only that directory',
    () async {
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final other = File('${temp.path}/picker-original');
      await other.writeAsBytes([9]);
      await input.startRecording(scope);
      expect(recorder.config!.encoder, AudioEncoder.aacLc);
      expect(recorder.path, startsWith('${temp.path}/s13-private-record-'));
      expect(recorder.path, endsWith('/voice.m4a'));
      await input.dispose();
      expect(recorder.cancels, 1);
      expect(recorder.disposals, 1);
      expect(await File(recorder.path!).exists(), false);
      expect(await other.exists(), true);
    },
  );
  test(
    'delayed native permission after dispose cannot start microphone',
    () async {
      recorder.permissionGate = Completer<void>();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final action = input.startRecording(scope);
      final rejected = expectLater(action, throwsA(isA<ApiException>()));
      await recorder.permissionEntered.future;
      final cleanup = input.dispose();
      scope.dispose();
      recorder.permissionGate!.complete();
      await rejected;
      await cleanup;
      expect(recorder.starts, 0);
      expect(recorder.disposals, 1);
    },
  );
}
