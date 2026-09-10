import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/media/native_image_selection.dart';
import 'support/media_http_fakes.dart';

const hostAsset = '11111111-2222-4333-8444-555555555555';
Map<String, Object?> hostStatus(
  String state,
  int version, {
  String purpose = 'DYNAMIC_IMAGE',
  int? bytes,
}) => {
  'assetId': hostAsset,
  'purpose': purpose,
  'state': state,
  'version': version,
  'maximumBytes': 10000000,
  'expiresAt': '2099-09-10T00:00:00Z',
  'mediaType': bytes == null ? null : 'image/png',
  'bytes': bytes,
  'durationMillis': bytes == null ? null : 0,
};

class TestImageSelection implements ImageSelection {
  List<XFile> files = [
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'test.png'),
  ];
  Future<List<XFile>> Function(int)? action;
  @override
  Future<List<XFile>> pick(int remaining) async =>
      action == null ? files : action!(remaining);
}

class _PluginPicker extends ImagePicker {
  int? limit;
  bool? fullMetadata;
  String? failure;
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    this.limit = limit;
    fullMetadata = requestFullMetadata;
    expect(maxWidth, isNull);
    expect(maxHeight, isNull);
    expect(imageQuality, isNull);
    if (failure != null)
      throw PlatformException(
        code: failure!,
        message: 'native detail is not shown',
      );
    return [];
  }
}

void main() {
  late TestMediaIdentity identity;
  late Directory temp;
  late TestImageSelection picker;
  late MediaFakeHttp http;
  late AppImageMediaHost host;
  setUp(() async {
    identity = TestMediaIdentity();
    picker = TestImageSelection();
    temp = await Directory.systemTemp.createTemp('s13-image-host-test-');
    http = MediaFakeHttp(
      (r) => MediaFakeResponse.json(
        r.method == 'PUT'
            ? hostStatus('UPLOADING', 1, bytes: 3)
            : r.uri.path.endsWith('/complete')
            ? hostStatus('READY', 2, bytes: 3)
            : hostStatus('ALLOCATED', 0),
      ),
    );
  });
  AppImageMediaHost create() => host = AppImageMediaHost(
    api: http.api(identity),
    userId: () => identity.user,
    generation: () => identity.generation,
    changes: identity,
    picker: picker,
    temporaryParent: () async => temp,
  );
  tearDown(() async {
    host.dispose();
    await host.cleanup;
    identity.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'ready upload and pure image draft survive page rebind with one PUT',
    () async {
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      await host.pick(draft);
      await host.upload(draft, draft.images.single);
      expect(draft.ready.single.assetId, hostAsset);
      expect(
        identical(host.draft('publish', MediaPurpose.dynamicImage), draft),
        isTrue,
      );
      expect(http.requests.where((r) => r.method == 'PUT').length, 1);
      expect(http.requests.singleWhere((r) => r.method == 'PUT').body, [
        1,
        2,
        3,
      ]);
    },
  );
  test(
    'unknown PUT recovers GET same ID and never repeats PUT even ALLOCATED',
    () async {
      http = MediaFakeHttp((r) {
        if (r.method == 'PUT') throw const SocketException('lost');
        return MediaFakeResponse.json(hostStatus('ALLOCATED', 0));
      });
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      await host.pick(draft);
      await expectLater(
        host.upload(draft, draft.images.single),
        throwsA(isA<ApiException>()),
      );
      final image = draft.images.single;
      expect(image.status!.assetId, hostAsset);
      await host.upload(draft, image, recover: true);
      await host.upload(draft, image);
      expect(http.requests.map((r) => r.method), ['POST', 'PUT', 'GET', 'GET']);
      expect(() => draft.ready, throwsA(isA<ApiException>()));
      host.remove(draft, image);
      await host.cleanup;
      expect(draft.images, isEmpty);
      expect(draft.retainedUploads.single.key, image.key);
      expect(draft.retainedUploads.single.status!.assetId, hostAsset);
      expect(draft.ready, isEmpty);
      expect(image.source, isNull);
      expect(http.requests.map((r) => r.method), ['POST', 'PUT', 'GET', 'GET']);
      await host.upload(draft, draft.retainedUploads.single, recover: true);
      expect(http.requests.last.method, 'GET');
      expect(http.requests.where((r) => r.method == 'PUT').length, 1);
      await host.submit(draft, {'content': 'text'}, (key, images) async {
        expect(images, isEmpty);
        return 'receipt';
      });
      host.acknowledge(draft);
      expect(draft.retainedUploads.single.key, image.key);
    },
  );
  test(
    'lost allocation response retries same key without new file or blind PUT',
    () async {
      var first = true;
      http = MediaFakeHttp((r) {
        if (first) {
          first = false;
          throw const SocketException('lost');
        }
        return MediaFakeResponse.json(hostStatus('ALLOCATED', 0));
      });
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      await host.pick(draft);
      final image = draft.images.single;
      await expectLater(
        host.upload(draft, image),
        throwsA(isA<ApiException>()),
      );
      await host.upload(draft, image, recover: true);
      expect(http.requests.length, 2);
      expect(
        http.requests.first.headers.value('X-Request-Id'),
        http.requests.last.headers.value('X-Request-Id'),
      );
      expect(http.requests.first.body, http.requests.last.body);
      expect(http.requests.every((r) => r.method == 'POST'), isTrue);
    },
  );
  test(
    'A B A cleans only owned copies and original actor recovers same asset via GET',
    () async {
      http = MediaFakeHttp((r) {
        if (r.method == 'PUT') throw const SocketException('lost');
        return MediaFakeResponse.json(hostStatus('ALLOCATED', 0));
      });
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      await host.pick(draft);
      final source = draft.images.single.source!;
      await expectLater(
        host.upload(draft, draft.images.single),
        throwsA(isA<ApiException>()),
      );
      final originalKey = draft.images.single.key;
      identity.change(2);
      await source.cleanup;
      expect(host.draft('publish', MediaPurpose.dynamicImage).images, isEmpty);
      expect(await temp.list().length, 0);
      identity.change(1);
      final restored = host.draft('publish', MediaPurpose.dynamicImage);
      expect(restored.images.single.key, originalKey);
      expect(restored.images.single.source, isNull);
      await host.upload(restored, restored.images.single, recover: true);
      expect(http.requests.last.method, 'GET');
      expect(http.requests.last.uri.path.endsWith(hostAsset), isTrue);
      expect(http.requests.where((r) => r.method == 'PUT').length, 1);
    },
  );
  test(
    'domain unknown remount same key; ABA uses independent Future and drops late receipt',
    () async {
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      draft.fields['content'] = '原文';
      final first = Completer<String>();
      final keys = <String>[];
      Future<String> send(String key, List<MediaReference> _) {
        keys.add(key);
        return first.future;
      }

      final pending = expectLater(
        host.submit(draft, {'content': '原文'}, send),
        throwsA(isA<ApiException>()),
      );
      identity.change(2);
      expect(host.draft('publish', MediaPurpose.dynamicImage).fields, isEmpty);
      identity.change(1);
      final restored = host.draft('publish', MediaPurpose.dynamicImage);
      final result = await host.submit(restored, {'content': '原文'}, (
        key,
        _,
      ) async {
        keys.add(key);
        return 'current';
      });
      first.complete('old');
      await pending;
      expect(result, 'current');
      expect(keys[0], keys[1]);
      expect(draft.receipt, 'current');
      host.acknowledge(restored);
      expect(restored.locked, isFalse);
    },
  );
  test(
    'unknown submission forbids changed content and retries original key; explicit 400 unlocks',
    () async {
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      final keys = <String>[];
      await expectLater(
        host.submit(draft, {'content': 'A'}, (key, _) async {
          keys.add(key);
          throw const ApiException(
            kind: ApiFailureKind.network,
            message: 'unknown',
          );
        }),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => host.submit(draft, {'content': 'B'}, (key, _) async => 'bad'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        host.submit(draft, {'content': 'A'}, (key, _) async {
          keys.add(key);
          throw const ApiException(
            kind: ApiFailureKind.validation,
            httpStatus: 400,
            message: 'reject',
          );
        }),
        throwsA(isA<ApiException>()),
      );
      expect(keys[0], keys[1]);
      expect(draft.locked, isFalse);
    },
  );
  test(
    'picker actual count/bytes checked; cancelled selection leaves existing untouched',
    () async {
      create();
      final draft = host.draft('ticket', MediaPurpose.supportImage);
      picker.files = List.generate(4, (_) => XFile.fromData(Uint8List(3)));
      await expectLater(host.pick(draft), throwsA(isA<ApiException>()));
      expect(draft.images, isEmpty);
      picker.files = [XFile.fromData(Uint8List(10000001))];
      await expectLater(host.pick(draft), throwsA(isA<ApiException>()));
      expect(draft.images, isEmpty);
      picker.files = [XFile.fromData(Uint8List(3))];
      await host.pick(draft);
      picker.files = [];
      await host.pick(draft);
      expect(draft.images.length, 1);
      final source = draft.images.single.source!;
      host.remove(draft, draft.images.single);
      await source.cleanup;
      expect(await temp.list().length, 0);
      expect(http.requests, isEmpty);
    },
  );
  test(
    'late selector A B A cannot capture files into returned A generation',
    () async {
      final gate = Completer<List<XFile>>();
      picker.action = (_) => gate.future;
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      final result = expectLater(
        host.pick(draft),
        throwsA(isA<ApiException>()),
      );
      identity.change(2);
      identity.change(1);
      gate.complete(picker.files);
      await result;
      expect(draft.images, isEmpty);
      expect(await temp.list().length, 0);
      expect(http.requests, isEmpty);
    },
  );
  test(
    'cancelling selection deletes only the app copy, not original picker file',
    () async {
      create();
      final original = File('${temp.path}/original.png');
      await original.writeAsBytes([1, 2, 3]);
      picker.files = [XFile(original.path)];
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      await host.pick(draft);
      host.remove(draft, draft.images.single);
      await host.cleanup;
      expect(await original.readAsBytes(), [1, 2, 3]);
      expect(http.requests, isEmpty);
    },
  );
  test('identity notification works before any upload scope exists', () {
    create();
    var changed = 0;
    host.addListener(() => changed++);
    identity.change(2);
    expect(changed, 1);
    identity.refreshToken();
    expect(changed, 1);
  });
  test(
    'inflight and received commands reject another body before returning cached Future',
    () async {
      create();
      final draft = host.draft('publish', MediaPurpose.dynamicImage);
      final result = Completer<String>();
      final first = host.submit(draft, {
        'content': 'original',
      }, (key, _) => result.future);
      try {
        expect(
          () => host.submit(draft, {
            'content': 'changed',
          }, (key, _) async => 'wrong'),
          throwsA(isA<ApiException>()),
        );
      } finally {
        result.complete('receipt');
        await first;
      }
      expect(
        () => host.submit(draft, {
          'content': 'changed',
        }, (key, _) async => 'wrong'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'official picker receives count and no full metadata; permission denial is explicit',
    () async {
      create();
      final plugin = _PluginPicker();
      final selection = NativeImageSelection(picker: plugin);
      expect(await selection.pick(3), isEmpty);
      expect(plugin.limit, 3);
      expect(plugin.fullMetadata, isFalse);
      plugin.failure = 'photo_access_denied';
      await expectLater(
        selection.pick(3),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiFailureKind.forbidden)
              .having((e) => e.message, 'message', contains('照片访问权限')),
        ),
      );
    },
  );
}
