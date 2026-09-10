import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_files.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/media/media_upload_coordinator.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'media_models_test.dart' show mediaId, status;
import 'support/media_http_fakes.dart';

void main() {
  test(
    'reconstructed coordinator keeps original flight; key and file cannot be substituted',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        's13-claim-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      Future<MediaUploadFile> source(int byte) => MediaUploadFile.capture(
        identity: scope,
        temporaryParent: directory,
        purpose: MediaPurpose.privateImage,
        bytes: 12,
        durationMillis: 0,
        content: Stream.value(List.filled(12, byte)),
      );
      final firstFile = await source(1);
      final otherFile = await source(2);
      addTearDown(otherFile.dispose);
      final http = MediaFakeHttp((_) => MediaFakeResponse.json(status()));
      final api = http.api(actor);
      final original = MediaUploadCoordinator(
        api: api,
        identity: scope,
        source: firstFile,
        requestId: 'original',
      );
      addTearDown(original.dispose);
      expect(
        () => MediaUploadCoordinator(
          api: api,
          identity: scope,
          source: otherFile,
          requestId: 'original',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => MediaUploadCoordinator(
          api: api,
          identity: scope,
          source: firstFile,
          requestId: 'new-key',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        identical(
          original,
          MediaUploadCoordinator(
            api: api,
            identity: scope,
            source: firstFile,
            requestId: 'original',
          ),
        ),
        isTrue,
      );
      expect(http.requests, isEmpty);
    },
  );
  for (final ending in [
    'REJECTED',
    'REVOKED',
    'expired',
    '503',
    '40983',
    'regression',
    'wrong-id',
  ]) {
    test('quarantine recovery preserves original identity on $ending', () async {
      final directory = await Directory.systemTemp.createTemp(
        's13-state-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final source = await MediaUploadFile.capture(
        identity: scope,
        temporaryParent: directory,
        purpose: MediaPurpose.privateImage,
        bytes: 12,
        durationMillis: 0,
        content: Stream.value(List.filled(12, 1)),
      );
      int completes = 0;
      bool recovering = false;
      int puts = 0;
      final http = MediaFakeHttp((r) {
        if (r.method == 'PUT') {
          puts++;
          return MediaFakeResponse.json(
            status(state: 'QUARANTINED', version: 2),
          );
        }
        if (r.uri.path.endsWith('/complete')) {
          completes++;
          return MediaFakeResponse.json(
            null,
            status: ending == '40983' ? 409 : 503,
            code: ending == '40983' ? 40983 : 50381,
          );
        }
        if (r.method == 'POST') return MediaFakeResponse.json(status());
        expect(recovering, isTrue);
        return MediaFakeResponse.json({
          ...status(
            state: ending == 'REJECTED' || ending == 'REVOKED'
                ? ending
                : 'QUARANTINED',
            version: ending == 'regression'
                ? 1
                : ending == 'REJECTED' || ending == 'REVOKED'
                ? 3
                : 2,
          ),
          if (ending == 'wrong-id')
            'assetId': 'aaaaaaaa-2222-4333-8444-555555555555',
        });
      });
      var now = DateTime.utc(2029);
      final coordinator = MediaUploadCoordinator(
        api: http.api(actor),
        identity: scope,
        source: source,
        requestId: 'unchanged-key',
        now: () => now,
      );
      addTearDown(coordinator.dispose);
      await expectLater(coordinator.advance(), throwsA(isA<ApiException>()));
      expect(coordinator.latest!.state, MediaAssetState.quarantined);
      expect(coordinator.latest!.version, 2);
      recovering = true;
      if (ending == 'expired') now = DateTime.utc(2031);
      if (ending == 'wrong-id' || ending == 'regression') {
        await expectLater(coordinator.recover(), throwsA(isA<ApiException>()));
        expect(coordinator.latest!.version, 2);
      } else {
        await coordinator
            .recover(); // recovery is read-only even when scan is still uncertain
        expect(completes, 1);
        if (ending == 'REJECTED' ||
            ending == 'REVOKED' ||
            ending == 'expired') {
          await coordinator.advance();
          expect(completes, 1);
        }
      }
      expect(puts, 1);
      expect(
        http.requests.where(
          (r) => r.method == 'POST' && !r.uri.path.endsWith('/complete'),
        ),
        hasLength(1),
      );
      expect(coordinator.latest!.assetId, mediaId);
    });
  }
  for (final loss in ['none', 'allocate', 'put', 'complete']) {
    test(
      'fixed asset/key recovery and singleflight after $loss loss',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          's13-coordinator-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final actor = TestMediaIdentity();
        final scope = actor.scope();
        addTearDown(scope.dispose);
        final file = await MediaUploadFile.capture(
          identity: scope,
          temporaryParent: directory,
          purpose: MediaPurpose.privateImage,
          bytes: 12,
          durationMillis: 0,
          content: Stream.value(List.filled(12, 9)),
        );
        var state = 'ALLOCATED';
        var version = 0;
        bool lost = false;
        int puts = 0;
        final keys = <String?>[];
        final http = MediaFakeHttp((r) {
          String operation;
          if (r.method == 'PUT') {
            operation = 'put';
            puts++;
            state = 'QUARANTINED';
            version = 2;
          } else if (r.uri.path.endsWith('/complete')) {
            operation = 'complete';
            expect(jsonDecode(utf8.decode(r.body)), {
              'expectedVersion': version,
            });
            state = 'READY';
            version = 3;
          } else if (r.method == 'POST') {
            operation = 'allocate';
            keys.add(r.headers.value('X-Request-Id'));
            expect(jsonDecode(utf8.decode(r.body)), {
              'purpose': 'PRIVATE_IMAGE',
            });
          } else {
            operation = 'status';
            expect(r.uri.path.endsWith(mediaId), isTrue);
          }
          if (loss == operation && !lost) {
            lost = true;
            throw const SocketException('response lost');
          }
          return MediaFakeResponse.json(status(state: state, version: version));
        });
        final coordinator = MediaUploadCoordinator(
          api: http.api(actor),
          identity: scope,
          source: file,
          requestId: 'fixed-original-key',
        );
        addTearDown(coordinator.dispose);
        final first = coordinator.advance();
        expect(identical(first, coordinator.advance()), isTrue);
        if (loss != 'none') {
          await expectLater(first, throwsA(isA<ApiException>()));
          final writes = http.requests.where((r) => r.method != 'GET').length;
          if (loss != 'allocate') {
            await coordinator.recover();
            expect(
              http.requests.where((r) => r.method != 'GET').length,
              writes,
            );
          }
          await coordinator.advance();
        } else {
          await first;
        }
        expect(coordinator.latest!.state, MediaAssetState.ready);
        expect(coordinator.latest!.assetId, mediaId);
        expect(puts, 1);
        expect(keys.every((key) => key == 'fixed-original-key'), isTrue);
        final writes = http.requests.where((r) => r.method != 'GET').length;
        await coordinator.advance();
        expect(http.requests.where((r) => r.method != 'GET').length, writes);
      },
    );
  }
  test(
    'uncertain PUT never repeats even when GET says ALLOCATED; UPLOADING completes',
    () async {
      final directory = await Directory.systemTemp.createTemp('s13-once-test-');
      addTearDown(() => directory.delete(recursive: true));
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final source = await MediaUploadFile.capture(
        identity: scope,
        temporaryParent: directory,
        purpose: MediaPurpose.privateImage,
        bytes: 12,
        durationMillis: 0,
        content: Stream.value(List.filled(12, 1)),
      );
      int puts = 0;
      var state = 'ALLOCATED';
      int version = 0;
      final http = MediaFakeHttp((r) {
        if (r.method == 'PUT') {
          puts++;
          throw const SocketException('lost');
        }
        if (r.uri.path.endsWith('/complete')) {
          expect(jsonDecode(utf8.decode(r.body)), {'expectedVersion': 1});
          state = 'READY';
          version = 3;
        }
        return MediaFakeResponse.json(status(state: state, version: version));
      });
      final coordinator = MediaUploadCoordinator(
        api: http.api(actor),
        identity: scope,
        source: source,
        requestId: 'fixed-key',
      );
      addTearDown(coordinator.dispose);
      await expectLater(coordinator.advance(), throwsA(isA<ApiException>()));
      expect((await coordinator.advance()).state, MediaAssetState.allocated);
      expect(puts, 1);
      state = 'UPLOADING';
      version = 1;
      expect((await coordinator.advance()).state, MediaAssetState.ready);
      expect(puts, 1);
    },
  );
  test(
    'late identity response cannot publish or allocate for B; source is deleted',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        's13-identity-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final source = await MediaUploadFile.capture(
        identity: scope,
        temporaryParent: directory,
        purpose: MediaPurpose.privateImage,
        bytes: 12,
        durationMillis: 0,
        content: Stream.value(List.filled(12, 1)),
      );
      final entered = Completer<void>();
      final response = Completer<HttpClientResponse>();
      final http = MediaFakeHttp((r) {
        entered.complete();
        return response.future;
      });
      final coordinator = MediaUploadCoordinator(
        api: http.api(actor),
        identity: scope,
        source: source,
        requestId: 'original-key',
      );
      addTearDown(coordinator.dispose);
      final outcome = coordinator.advance().then<Object>(
        (v) => v,
        onError: (Object e) => e,
      );
      await entered.future;
      actor.change(2);
      expect(
        await outcome.timeout(const Duration(seconds: 1)),
        isA<ApiException>(),
      );
      await source.cleanup;
      expect(await directory.list().toList(), isEmpty);
      response.complete(MediaFakeResponse.json(status()));
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.latest, isNull);
      expect(http.requests, hasLength(1));
      final b = actor.scope();
      addTearDown(b.dispose);
      expect(
        () => MediaUploadCoordinator(
          api: http.api(actor),
          identity: b,
          source: source,
          requestId: 'original-key',
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
