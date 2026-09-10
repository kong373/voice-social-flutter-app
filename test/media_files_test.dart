import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_files.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'media_models_test.dart' show reference;
import 'support/media_http_fakes.dart';

void main() {
  late Directory parent;
  setUp(() async {
    parent = await Directory.systemTemp.createTemp('s13-file-tests-');
  });
  tearDown(() async {
    await parent.delete(recursive: true);
  });

  test(
    'owned upload copy preserves input, enforces actual bytes, deletes on logout',
    () async {
      final input = File('${parent.path}/selected-user-file');
      await input.writeAsBytes([1, 2, 3, 4]);
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final file = await MediaUploadFile.capture(
        identity: scope,
        temporaryParent: parent,
        purpose: MediaPurpose.privateImage,
        bytes: 4,
        durationMillis: 0,
        content: input.openRead(),
      );
      expect(await file.openRead().expand((c) => c).toList(), [1, 2, 3, 4]);
      for (final count in [3, 5]) {
        await expectLater(
          MediaUploadFile.capture(
            identity: scope,
            temporaryParent: parent,
            purpose: MediaPurpose.privateImage,
            bytes: 4,
            durationMillis: 0,
            content: Stream.value(List.filled(count, 1)),
          ),
          throwsA(isA<ApiException>()),
        );
      }
      expect(
        await parent.list().length,
        2,
      ); // original plus one owned valid copy
      actor.change(0);
      await file.cleanup;
      expect(await input.readAsBytes(), [1, 2, 3, 4]);
      expect(await parent.list().length, 1);
      actor.change(1);
      await expectLater(
        file.openRead().drain<void>(),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'idle capture cancellation removes partial copy before any next chunk',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final started = Completer<void>();
      final stream = StreamController<List<int>>(
        onListen: () => started.complete(),
      );
      final pending = MediaUploadFile.capture(
        identity: scope,
        temporaryParent: parent,
        purpose: MediaPurpose.privateImage,
        bytes: 4,
        durationMillis: 0,
        content: stream.stream,
      ).then<Object>((v) => v, onError: (Object e) => e);
      await started.future;
      stream.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      actor.change(2);
      expect(
        await pending.timeout(const Duration(seconds: 2)),
        isA<ApiException>(),
      );
      expect(await parent.list().toList(), isEmpty);
      await stream.close();
    },
  );

  test(
    'controlled file exact bytes; logout removes cache and old path access',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse(
          200,
          Stream.fromIterable([List.filled(6, 255), List.filled(6, 0)]),
          type: 'image/png',
        ),
      );
      final file = await MediaBinaryFiles(http.api(actor)).download(
        media: MediaReference.fromJson(reference()),
        identity: scope,
        temporaryParent: parent,
      );
      final path = file.path;
      expect(await File(path).readAsBytes(), [
        ...List.filled(6, 255),
        ...List.filled(6, 0),
      ]);
      actor.change(0);
      await file.cleanup;
      expect(await File(path).exists(), isFalse);
      expect(() => file.path, throwsA(isA<ApiException>()));
      expect(await parent.list().toList(), isEmpty);
    },
  );

  test(
    'failed/oversized and unauthorized content never returns or retains partial file',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      for (final response in [
        MediaFakeResponse(
          200,
          Stream.fromIterable([List.filled(6, 1), List.filled(7, 1)]),
          type: 'image/png',
        ),
        MediaFakeResponse(
          200,
          Stream<List<int>>.error(const SocketException('interrupted')),
          type: 'image/png',
        ),
        MediaFakeResponse.json(null, status: 404, code: 40481),
      ]) {
        final http = MediaFakeHttp((_) => response);
        await expectLater(
          MediaBinaryFiles(http.api(actor)).download(
            media: MediaReference.fromJson(reference()),
            identity: scope,
            temporaryParent: parent,
          ),
          throwsA(isA<ApiException>()),
        );
        expect(await parent.list().toList(), isEmpty);
      }
    },
  );

  test(
    'logout during stalled download stops stream and deletes partial temp',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final listening = Completer<void>();
      final chunks = StreamController<List<int>>(
        onListen: () => listening.complete(),
      );
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse(200, chunks.stream, type: 'image/png'),
      );
      final pending = MediaBinaryFiles(http.api(actor))
          .download(
            media: MediaReference.fromJson(reference()),
            identity: scope,
            temporaryParent: parent,
          )
          .then<Object>((v) => v, onError: (Object e) => e);
      await listening.future;
      chunks.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      actor.change(2);
      expect(
        await pending.timeout(const Duration(seconds: 2)),
        isA<ApiException>(),
      );
      expect(await parent.list().toList(), isEmpty);
      expect(http.requests.single.aborted, isTrue);
      await chunks.close();
    },
  );
}
