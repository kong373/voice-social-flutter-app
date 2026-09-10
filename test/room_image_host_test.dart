import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/room/presentation/room_image_editor.dart';
import 'support/media_http_fakes.dart';
import 's13_image_host_test.dart'
    show TestImageSelection, hostStatus, hostAsset;

void main() {
  late TestMediaIdentity identity;
  late Directory temp;
  late ChangeNotifier roomChanges;
  late AppImageMediaHost host;
  late RoomImageEditorBinding binding;
  late MediaFakeHttp http;
  bool inRoom = true;
  setUp(() async {
    identity = TestMediaIdentity();
    roomChanges = ChangeNotifier();
    inRoom = true;
    temp = await Directory.systemTemp.createTemp('room-image-test-');
    http = MediaFakeHttp(
      (r) => MediaFakeResponse.json(
        r.method == 'PUT'
            ? hostStatus('UPLOADING', 1, purpose: 'ROOM_COVER', bytes: 3)
            : r.uri.path.endsWith('/complete')
            ? hostStatus('READY', 2, purpose: 'ROOM_COVER', bytes: 3)
            : hostStatus('ALLOCATED', 0, purpose: 'ROOM_COVER'),
      ),
    );
  });
  void create() {
    host = AppImageMediaHost(
      api: http.api(identity),
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      picker: TestImageSelection(),
      temporaryParent: () async => temp,
    );
    binding = RoomImageEditorBinding(
      host: host,
      roomId: 'room-1',
      roomChanges: roomChanges,
      isCurrent: () => inRoom,
    );
  }

  tearDown(() async {
    binding.dispose();
    host.dispose();
    await host.cleanup;
    roomChanges.dispose();
    identity.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'single image uploads only purpose, READY enables save, room context never enters allocate',
    () async {
      create();
      await binding.pick(binding.cover);
      expect(binding.canSave, isFalse);
      await binding.upload(binding.cover, binding.cover.images.single);
      expect(binding.canSave, isTrue);
      expect(binding.change(binding.cover).media!.assetId, hostAsset);
      final allocate = http.requests.first;
      expect(jsonDecode(utf8.decode(allocate.body)), {'purpose': 'ROOM_COVER'});
      expect(
        allocate.headers.value('X-Request-Id'),
        binding.cover.images.single.key,
      );
      expect(http.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(http.requests.map((r) => r.uri.queryParameters).toList(), [
        <String, String>{},
        {'expectedVersion': '0'},
        <String, String>{},
      ]);
    },
  );

  test(
    'allocation response loss then remount reuses allocation key without blindly PUT',
    () async {
      bool lost = true;
      http = MediaFakeHttp((r) {
        if (lost) throw const SocketException('lost allocation response');
        return MediaFakeResponse.json(
          hostStatus('ALLOCATED', 0, purpose: 'ROOM_COVER'),
        );
      });
      create();
      await binding.pick(binding.cover);
      final image = binding.cover.images.single;
      await expectLater(
        binding.upload(binding.cover, image),
        throwsA(isA<ApiException>()),
      );
      expect(image.source, isNull);
      binding.dispose();
      binding = RoomImageEditorBinding(
        host: host,
        roomId: 'room-1',
        roomChanges: roomChanges,
        isCurrent: () => inRoom,
      );
      expect(binding.cover.images.single, same(image));
      lost = false;
      await binding.upload(binding.cover, image, recover: true);
      expect(http.requests[0].body, http.requests[1].body);
      expect(
        http.requests[0].headers.value('X-Request-Id'),
        http.requests[1].headers.value('X-Request-Id'),
      );
      expect(http.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(binding.canSave, isFalse);
      binding.removeSelection(binding.cover);
      expect(binding.canSave, isTrue);
      expect(binding.change(binding.cover).changed, isFalse);
      expect(binding.cover.retainedUploads.single.key, image.key);
    },
  );

  test(
    'PUT response loss restores same asset by GET and complete, never repeats PUT',
    () async {
      int version = 0;
      http = MediaFakeHttp((r) {
        if (r.method == 'PUT') {
          version = 1;
          throw const SocketException('committed upload, lost response');
        }
        if (r.uri.path.endsWith('/complete')) version = 2;
        return MediaFakeResponse.json(
          hostStatus(
            version == 0
                ? 'ALLOCATED'
                : version == 1
                ? 'UPLOADING'
                : 'READY',
            version,
            purpose: 'ROOM_COVER',
            bytes: version == 0 ? null : 3,
          ),
        );
      });
      create();
      await binding.pick(binding.cover);
      final image = binding.cover.images.single;
      await expectLater(
        binding.upload(binding.cover, image),
        throwsA(isA<ApiException>()),
      );
      expect(image.putAttempted, isTrue);
      expect(image.source, isNull);
      await binding.upload(binding.cover, image, recover: true);
      expect(binding.canSave, isFalse);
      await binding.upload(binding.cover, image);
      expect(binding.canSave, isTrue);
      expect(http.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(
        http.requests
            .where((r) => r.method == 'GET')
            .every((r) => r.uri.path.endsWith(hostAsset)),
        isTrue,
      );
    },
  );

  for (final change in ['leave', 'ABA']) {
    test(
      '$change aborts delayed allocation and removes owned bytes without adopting late asset',
      () async {
        final started = Completer<void>();
        final late = Completer<HttpClientResponse>();
        http = MediaFakeHttp((r) {
          started.complete();
          return late.future;
        });
        create();
        await binding.pick(binding.cover);
        final image = binding.cover.images.single;
        final result = expectLater(
          binding.upload(binding.cover, image),
          throwsA(isA<ApiException>()),
        );
        await started.future;
        if (change == 'leave') {
          inRoom = false;
          roomChanges.notifyListeners();
        } else {
          identity.change(2);
          identity.change(1);
        }
        await result;
        late.complete(
          MediaFakeResponse.json(
            hostStatus('READY', 2, purpose: 'ROOM_COVER', bytes: 3),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await host.cleanup;
        expect(http.requests.single.aborted, isTrue);
        expect(image.status, isNull);
        expect(image.source, isNull);
        expect(binding.current, isFalse);
        expect(await temp.list().toList(), isEmpty);
      },
    );
  }
}
