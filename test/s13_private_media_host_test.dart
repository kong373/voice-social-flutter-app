import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/media/private_media_host.dart';
import 'package:voice_social_app/features/media/private_media_native.dart';
import 'package:voice_social_app/features/media/private_media_temporary_root.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'support/media_http_fakes.dart';

const pmAsset = '11111111-2222-4333-8444-555555555555';
const pmPeer = ConversationSummary(
  id: 'peer-2',
  kind: ConversationKind.privateChat,
  title: 'peer',
  lastMessage: '',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 2,
);
const pmOther = ConversationSummary(
  id: 'peer-3',
  kind: ConversationKind.privateChat,
  title: 'other',
  lastMessage: '',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 3,
);

class FakePrivateInput implements PrivateMediaInput {
  int starts = 0, stops = 0, closes = 0, picks = 0, releases = 0;
  int bytes = 3, voiceDuration = 1200, videoDuration = 2000;
  bool permission = true;
  Future<PrivateMediaSelection?> Function(MediaPurpose)? pickAction;
  Future<void> Function()? startAction;
  PrivateMediaSelection selection(MediaPurpose purpose) =>
      PrivateMediaSelection(
        XFile.fromData(Uint8List(bytes), name: 'contract'),
        purpose == MediaPurpose.privateImage
            ? 0
            : purpose == MediaPurpose.privateVoice
            ? voiceDuration
            : videoDuration,
        release: () async {
          releases++;
        },
      );
  @override
  Future<PrivateMediaSelection?> pick(
    MediaPurpose purpose,
    MediaIdentityScope scope,
  ) async {
    picks++;
    if (!permission)
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '照片权限被拒绝',
      );
    return pickAction == null ? selection(purpose) : pickAction!(purpose);
  }

  @override
  Future<void> startRecording(MediaIdentityScope scope) async {
    if (!permission)
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '麦克风权限被拒绝',
      );
    await startAction?.call();
    scope.check();
    starts++;
  }

  @override
  Future<PrivateMediaSelection?> finishRecording(
    MediaIdentityScope scope,
  ) async {
    stops++;
    return selection(MediaPurpose.privateVoice);
  }

  @override
  Future<void> dispose() async {
    closes++;
  }
}

class FakePrivatePlayer extends PrivateLocalPlayer {
  int opens = 0, plays = 0, pauses = 0, closes = 0;
  File? file;
  Future<void> Function()? opening;
  @override
  bool playing = false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(seconds: 2);
  @override
  Widget? get video => null;
  @override
  Future<void> open(File value) async {
    file = value;
    opens++;
    await opening?.call();
  }

  @override
  Future<void> play() async {
    plays++;
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    closes++;
    playing = false;
  }
}

class PrivateHarness {
  PrivateHarness(this.directory);
  final Directory directory;
  final identity = TestMediaIdentity();
  final store = MemoryKeyValueStore();
  final inputs = <FakePrivateInput>[];
  final players = <FakePrivatePlayer>[];
  final hosts = <PrivateMediaHost>[];
  MediaPurpose purpose = MediaPurpose.privateImage;
  String expiresAt = '2099-09-10T00:00:00Z';
  int state = 0;
  FutureOr<MediaFakeResponse> Function(MediaFakeRequest)? intercept;
  late final http = MediaFakeHttp((r) {
    if (intercept != null) return intercept!(r);
    return respond(r);
  });
  Map<String, Object?> reference() => {
    'assetId': pmAsset,
    'purpose': purpose.wire,
    'mediaType': purpose == MediaPurpose.privateVoice
        ? 'audio/mp4'
        : purpose == MediaPurpose.privateVideo
        ? 'video/mp4'
        : 'image/png',
    'bytes': 3,
    'durationMillis': purpose == MediaPurpose.privateImage ? 0 : 1200,
    'version': 3,
  };
  Map<String, Object?> status() => {
    'assetId': pmAsset,
    'purpose': purpose.wire,
    'state': ['ALLOCATED', 'UPLOADING', 'QUARANTINED', 'READY'][state],
    'version': state,
    'maximumBytes': purpose.maximumBytes,
    'expiresAt': expiresAt,
    'mediaType': state < 3 ? null : reference()['mediaType'],
    'bytes': state == 0 ? null : 3,
    'durationMillis': state < 3 ? null : reference()['durationMillis'],
  };
  Map<String, Object?> receipt({int actor = 1, int receiver = 2}) => {
    'historyVersion': '0',
    'clearedThroughSequence': '0',
    'messageSequence': '1',
    'messageId': 'stored-message',
    'senderUserId': actor,
    'receiverUserId': receiver,
    'direction': 'OUTGOING',
    'messageType': purpose == MediaPurpose.privateImage
        ? 'IMAGE'
        : purpose == MediaPurpose.privateVoice
        ? 'VOICE'
        : 'VIDEO',
    'content': '',
    'media': [reference()],
    'storageStatus': 'FIRST_PARTY_STORED',
    'deliveryStatus': 'VENDOR_BLOCKED',
    'imStatus': 'VENDOR_BLOCKED',
    'providerInvocation': false,
    'read': false,
    'readAt': '',
    'createdAt': '2026-09-10T00:00:00Z',
  };
  MediaFakeResponse respond(MediaFakeRequest r) {
    if (r.uri.path.endsWith('/message/send'))
      return MediaFakeResponse.json(receipt());
    if (r.method == 'PUT') state = 2;
    if (r.uri.path.endsWith('/complete')) state = 3;
    return MediaFakeResponse.json(status());
  }

  PrivateMediaHost create({KeyValueStore? storage}) {
    final host = PrivateMediaHost(
      api: http.api(identity),
      store: storage ?? store,
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      temporaryParent: () async => directory,
      inputFactory: () {
        final input = FakePrivateInput();
        inputs.add(input);
        return input;
      },
      playerFactory: (_) {
        final player = FakePrivatePlayer();
        players.add(player);
        return player;
      },
    );
    hosts.add(host);
    return host;
  }

  BackendMessageRepository get repository => BackendMessageRepository(
    apiClient: http.api(identity),
    routes: const BackendRouteCatalog(),
    currentUserIdProvider: () => identity.user,
  );
  Future<PrivateMediaVisit> ready(
    PrivateMediaHost host, {
    MediaPurpose type = MediaPurpose.privateImage,
  }) async {
    purpose = type;
    final visit = host.visit(pmPeer);
    await visit.loaded;
    if (type == MediaPurpose.privateVoice) {
      await visit.startRecording();
      await visit.finishRecording();
    } else {
      await visit.pick(type);
    }
    await visit.upload();
    expect(visit.intent!.status!.state, MediaAssetState.ready);
    return visit;
  }

  Future<void> close() async {
    for (final host in hosts) {
      host.dispose();
      await host.cleanup;
    }
    identity.dispose();
  }
}

class _FailingStore implements KeyValueStore {
  _FailingStore(this.delegate);
  final KeyValueStore delegate;
  bool fail = false;
  Future<void> Function(String)? beforeWrite;
  @override
  Future<String?> read(String key) => delegate.read(key);
  @override
  Future<void> delete(String key) => delegate.delete(key);
  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key);
    await delegate.write(key, value);
    if (fail) throw const FileSystemException('contract write result lost');
  }
}

void main() {
  test(
    'Q19 cleared media replay 40481 retires only its original local intent without fake success',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'q19-private-intent-',
      );
      final fixture = PrivateHarness(directory);
      addTearDown(() async {
        await fixture.close();
        await directory.delete(recursive: true);
      });
      final host = fixture.create();
      final visit = await fixture.ready(host);
      final originalKey = visit.intent!.requestId;
      fixture.intercept = (r) => r.uri.path.endsWith('/message/send')
          ? MediaFakeResponse.json({}, status: 404, code: 40481)
          : fixture.respond(r);
      await expectLater(
        visit.send(fixture.repository),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40481)),
      );
      expect(visit.intent, isNull);
      final resumed = host.visit(pmPeer);
      await resumed.loaded;
      expect(resumed.intent, isNull);
      final sends = fixture.http.requests
          .where((r) => r.uri.path.endsWith('/message/send'))
          .toList();
      expect(sends, hasLength(1));
      expect(sends.single.headers.value('X-Request-Id'), originalKey);
    },
  );
  late Directory temp;
  late PrivateHarness h;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('s13-private-host-test-');
    h = PrivateHarness(temp);
  });
  tearDown(() async {
    await h.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  for (final type in [
    MediaPurpose.privateImage,
    MediaPurpose.privateVoice,
    MediaPurpose.privateVideo,
  ]) {
    test(
      '$type READY six fields only, one PUT, stored receipt not realtime success',
      () async {
        final visit = await h.ready(h.create(), type: type);
        final original = visit.intent!;
        final result = await visit.send(h.repository);
        expect(result.status, ChatMessageStatus.storedPendingDelivery);
        expect(result.deliveryStatus, MessageDeliveryStatus.vendorBlocked);
        final send = h.http.requests.singleWhere(
          (r) => r.uri.path.endsWith('/message/send'),
        );
        expect(jsonDecode(utf8.decode(send.body)), {
          'targetUserId': 2,
          'messageType': result.messageType.wire,
          'mediaAssetId': pmAsset,
        });
        expect(send.headers.value('X-Request-Id'), original.requestId);
        expect(h.http.requests.where((r) => r.method == 'PUT').length, 1);
        expect(await h.store.read('s13.private-media.v1.1.2'), isNull);
        expect(visit.intent, isNull);
      },
    );
  }
  test(
    'unknown send survives cold host, no automatic I/O, same original body/key',
    () async {
      final firstHost = h.create();
      final visit = await h.ready(firstHost);
      h.intercept = (r) {
        if (r.uri.path.endsWith('/message/send'))
          throw const SocketException('lost');
        return h.respond(r);
      };
      await expectLater(visit.send(h.repository), throwsA(isA<ApiException>()));
      final first = h.http.requests.last,
          raw = (await h.store.read('s13.private-media.v1.1.2'))!;
      expect(raw, isNot(contains('Bearer')));
      expect(raw, isNot(contains(temp.path)));
      expect(jsonDecode(raw), isNot(contains('content')));
      firstHost.dispose();
      await firstHost.cleanup;
      final current = h.create().visit(pmPeer);
      await current.loaded;
      expect(h.http.requests.last, same(first));
      h.intercept = null;
      await current.send(h.repository);
      final last = h.http.requests.last;
      expect(last.body, first.body);
      expect(
        last.headers.value('X-Request-Id'),
        first.headers.value('X-Request-Id'),
      );
      expect(h.http.requests.where((r) => r.method == 'PUT').length, 1);
    },
  );
  test(
    'unknown PUT persisted before I/O, cold recovery GET same ID never replaces body',
    () async {
      final host = h.create(), visit = h.create().visit(pmPeer);
      await visit.loaded;
      await visit.pick(MediaPurpose.privateImage);
      h.intercept = (r) async {
        if (r.method == 'PUT') {
          expect(
            (jsonDecode((await h.store.read('s13.private-media.v1.1.2'))!)
                as Map<String, Object?>)['putAttempted'],
            true,
          );
          throw const SocketException('lost upload');
        }
        return h.respond(r);
      };
      await expectLater(visit.upload(), throwsA(isA<ApiException>()));
      visit.dispose();
      await visit.cleanup;
      final restored = host.visit(pmPeer);
      await restored.loaded;
      final count = h.http.requests.length;
      await restored.upload(readOnly: true);
      await restored.upload();
      expect(h.http.requests.skip(count).map((r) => r.method), ['GET', 'GET']);
      expect(restored.intent!.status!.assetId, pmAsset);
      await expectLater(
        restored.send(h.repository),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'lost allocation retries only original key, then no blind cold PUT',
    () async {
      final visit = h.create().visit(pmPeer);
      await visit.loaded;
      await visit.pick(MediaPurpose.privateImage);
      h.intercept = (_) => throw const SocketException('lost allocation');
      await expectLater(visit.upload(), throwsA(isA<ApiException>()));
      final first = h.http.requests.single;
      visit.dispose();
      await visit.cleanup;
      h.intercept = null;
      final restored = h.create().visit(pmPeer);
      await restored.loaded;
      await restored.upload(readOnly: true);
      expect(h.http.requests.last.body, first.body);
      expect(
        h.http.requests.last.headers.value('X-Request-Id'),
        first.headers.value('X-Request-Id'),
      );
      expect(h.http.requests.map((r) => r.method), ['POST', 'POST']);
    },
  );
  test(
    'cold expired ALLOCATED can be explicitly abandoned without blocking new selection',
    () async {
      final firstHost = h.create(), original = firstHost.visit(pmPeer);
      await original.loaded;
      await original.pick(MediaPurpose.privateImage);
      final key = original.intent!.allocationKey;
      h.intercept = (_) => throw const SocketException('lost allocation');
      await expectLater(original.upload(), throwsA(isA<ApiException>()));
      firstHost.dispose();
      await firstHost.cleanup;

      // Backend replays the original expired allocation and status remains a
      // read-only ALLOCATED snapshot. No terminal state or expiry renewal.
      h.expiresAt = '2020-01-01T00:00:00Z';
      h.intercept = null;
      final restored = h.create().visit(pmPeer);
      await restored.loaded;
      await restored.upload(readOnly: true);
      await restored.upload(readOnly: true);
      expect(restored.intent!.status!.state, MediaAssetState.allocated);
      expect(restored.intent!.status!.isExpired(DateTime.now()), true);
      expect(restored.intent!.putAttempted, false);
      expect(h.http.requests.map((r) => r.method), ['POST', 'POST', 'GET']);
      expect(h.http.requests[1].headers.value('X-Request-Id'), key);
      final count = h.http.requests.length;
      final originalRaw = await h.store.read('s13.private-media.v1.1.2');

      await restored.discard();
      expect(restored.intent, isNull);
      expect(await h.store.read('s13.private-media.v1.1.2'), isNull);
      final archiveKey = 's13.private-media.abandoned.v1.1.2.$key';
      expect(await h.store.read(archiveKey), originalRaw);
      await restored.pick(MediaPurpose.privateImage);
      expect(restored.intent!.allocationKey, isNot(key));
      expect(restored.intent!.allocationAttempted, false);
      expect(
        h.http.requests.length,
        count,
        reason: 'no DELETE, allocate or send',
      );
      restored.dispose();
      await restored.cleanup;
      final next = h.create().visit(pmPeer);
      await next.loaded;
      expect(next.intent!.allocationKey, isNot(key));
      expect(await h.store.read(archiveKey), originalRaw);
    },
  );
  test(
    'lost allocation without ID retains original key when explicitly abandoned',
    () async {
      final visit = h.create().visit(pmPeer);
      await visit.loaded;
      await visit.pick(MediaPurpose.privateImage);
      h.intercept = (_) => throw const SocketException('lost allocation');
      await expectLater(visit.upload(), throwsA(isA<ApiException>()));
      final original = (await h.store.read('s13.private-media.v1.1.2'))!;
      final key = visit.intent!.allocationKey;
      visit.dispose();
      await visit.cleanup;
      final restored = h.create().visit(pmPeer);
      await restored.loaded;
      await restored.discard();
      expect(
        await h.store.read('s13.private-media.abandoned.v1.1.2.$key'),
        original,
      );
      expect(h.http.requests.length, 1);
      await restored.pick(MediaPurpose.privateImage);
      expect(restored.intent!.allocationKey, isNot(key));
      expect(h.http.requests.length, 1);
    },
  );
  test(
    'unknown PUT can be locally abandoned without replay, revoke or send',
    () async {
      final visit = h.create().visit(pmPeer);
      await visit.loaded;
      await visit.pick(MediaPurpose.privateImage);
      h.intercept = (r) {
        if (r.method == 'PUT') throw const SocketException('unknown bytes');
        return h.respond(r);
      };
      await expectLater(visit.upload(), throwsA(isA<ApiException>()));
      final key = visit.intent!.allocationKey;
      final original = await h.store.read('s13.private-media.v1.1.2');
      visit.dispose();
      await visit.cleanup;
      final restored = h.create().visit(pmPeer);
      await restored.loaded;
      expect(restored.intent!.putAttempted, true);
      await restored.discard();
      expect(
        await h.store.read('s13.private-media.abandoned.v1.1.2.$key'),
        original,
      );
      expect(h.http.requests.map((r) => r.method), ['POST', 'PUT']);
      expect(await h.store.read('s13.private-media.v1.1.2'), isNull);
    },
  );
  test(
    'archive storage failure keeps active upload and prevents replacing selection',
    () async {
      final storage = _FailingStore(h.store);
      final visit = await h.ready(h.create(storage: storage));
      final original = await h.store.read('s13.private-media.v1.1.2');
      final key = visit.intent!.allocationKey, count = h.http.requests.length;
      storage.fail = true;
      await expectLater(visit.discard(), throwsA(isA<FileSystemException>()));
      expect(await h.store.read('s13.private-media.v1.1.2'), original);
      expect(visit.intent!.allocationKey, key);
      await expectLater(
        visit.pick(MediaPurpose.privateImage),
        throwsA(isA<ApiException>()),
      );
      storage.fail = false;
      await visit.discard();
      expect(
        await h.store.read('s13.private-media.abandoned.v1.1.2.$key'),
        original,
      );
      expect(await h.store.read('s13.private-media.v1.1.2'), isNull);
      expect(h.http.requests.length, count);
    },
  );
  test(
    'ABA during archive never clears the active original account intent',
    () async {
      final storage = _FailingStore(h.store), host = h.create(storage: null);
      final visit = await h.ready(h.create(storage: storage));
      final key = visit.intent!.allocationKey;
      final original = await h.store.read('s13.private-media.v1.1.2');
      final entered = Completer<void>(), gate = Completer<void>();
      storage.beforeWrite = (key) async {
        if (key.startsWith('s13.private-media.abandoned.')) {
          entered.complete();
          await gate.future;
        }
      };
      final discarded = visit.discard();
      final rejected = expectLater(discarded, throwsA(isA<ApiException>()));
      await entered.future;
      h.identity.change(7);
      final b = host.visit(pmPeer);
      await b.loaded;
      expect(b.intent, isNull);
      h.identity.change(1);
      gate.complete();
      await rejected;
      expect(await h.store.read('s13.private-media.v1.1.2'), original);
      final a = host.visit(pmPeer);
      await a.loaded;
      expect(a.intent!.allocationKey, key);
    },
  );
  test(
    'expired unknown message send cannot be abandoned and replays original request',
    () async {
      final visit = await h.ready(h.create());
      h.intercept = (_) => throw const SocketException('unknown message');
      await expectLater(visit.send(h.repository), throwsA(isA<ApiException>()));
      final originalPost = h.http.requests.last;
      final raw =
          jsonDecode((await h.store.read('s13.private-media.v1.1.2'))!)
              as Map<String, dynamic>;
      (raw['status'] as Map<String, dynamic>)['expiresAt'] =
          '2020-01-01T00:00:00Z';
      await h.store.write('s13.private-media.v1.1.2', jsonEncode(raw));
      visit.dispose();
      await visit.cleanup;
      final restored = h.create().visit(pmPeer);
      await restored.loaded;
      expect(restored.intent!.status!.isExpired(DateTime.now()), true);
      expect(restored.intent!.canDiscard, false);
      await expectLater(restored.discard(), throwsA(isA<ApiException>()));
      expect(await h.store.read('s13.private-media.v1.1.2'), jsonEncode(raw));
      expect(h.http.requests.last, same(originalPost));
      expect(
        await h.store.read(
          's13.private-media.abandoned.v1.1.2.${raw['allocationKey']}',
        ),
        isNull,
      );
      h.intercept = null;
      await restored.send(h.repository);
      expect(h.http.requests.last.body, originalPost.body);
      expect(
        h.http.requests.last.headers.value('X-Request-Id'),
        originalPost.headers.value('X-Request-Id'),
      );
    },
  );
  test(
    'A B A invalidates original openUrl and resumes original intent explicitly',
    () async {
      final host = h.create(), visit = await h.ready(h.create());
      final gate = Completer<void>(), entered = Completer<void>();
      h.http.beforeOpen = (_) async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      };
      final future = visit.send(h.repository);
      final rejected = expectLater(future, throwsA(isA<ApiException>()));
      await entered.future;
      h.identity.change(7);
      h.identity.change(1);
      final current = host.visit(pmPeer);
      await current.loaded;
      expect(current.intent!.sendAttempted, true);
      gate.complete();
      await rejected;
      final stale = h.http.requests.last;
      expect(stale.closes, 0);
      expect(stale.body, isEmpty);
      h.http.beforeOpen = null;
      await current.send(h.repository);
      expect(
        h.http.requests.last.headers.value('Authorization'),
        'Bearer contract-1',
      );
    },
  );
  test(
    'late send success after leaving cannot delete pending or enter a new receiver',
    () async {
      final host = h.create(), visit = await h.ready(h.create());
      final gate = Completer<MediaFakeResponse>(), entered = Completer<void>();
      h.intercept = (_) {
        entered.complete();
        return gate.future;
      };
      final sent = visit.send(h.repository);
      final rejected = expectLater(sent, throwsA(isA<ApiException>()));
      await entered.future;
      visit.dispose();
      final other = host.visit(pmOther);
      await other.loaded;
      expect(other.intent, isNull);
      gate.complete(MediaFakeResponse.json(h.receipt()));
      await rejected;
      final original = host.visit(pmPeer);
      await original.loaded;
      expect(original.intent!.sendAttempted, true);
      expect(await h.store.read('s13.private-media.v1.1.2'), isNotNull);
    },
  );
  test(
    'new actor has no previous peer content and does not reuse previous Future',
    () async {
      final host = h.create();
      final visit = await h.ready(host);
      final key = visit.intent!.requestId;
      h.identity.change(7);
      final b = host.visit(pmPeer);
      await b.loaded;
      expect(b.intent, isNull);
      expect(visit.current, false);
      h.identity.change(1);
      final a = host.visit(pmPeer);
      await a.loaded;
      expect(a.intent!.requestId, key);
      expect(a.scope, isNot(same(visit.scope)));
    },
  );
  test(
    'late picker after scope cancellation releases selection, creates no journal',
    () async {
      final visit = h.create().visit(pmPeer);
      await visit.loaded;
      final gate = Completer<PrivateMediaSelection?>(),
          entered = Completer<void>();
      h.inputs.last.pickAction = (_) {
        entered.complete();
        return gate.future;
      };
      final action = visit.pick(MediaPurpose.privateImage);
      final rejected = expectLater(action, throwsA(isA<ApiException>()));
      await entered.future;
      visit.dispose();
      gate.complete(h.inputs.last.selection(MediaPurpose.privateImage));
      await rejected;
      expect(h.inputs.last.releases, 1);
      expect(h.http.requests, isEmpty);
      expect(await h.store.read('s13.private-media.v1.1.2'), isNull);
    },
  );
  for (final purpose in [
    MediaPurpose.privateImage,
    MediaPurpose.privateVoice,
    MediaPurpose.privateVideo,
  ]) {
    test('$purpose invalid selection rejects before allocation', () async {
      final visit = h.create().visit(pmPeer);
      await visit.loaded;
      if (purpose == MediaPurpose.privateImage) h.inputs.last.bytes = 10000001;
      if (purpose == MediaPurpose.privateVoice)
        h.inputs.last.voiceDuration = 60001;
      if (purpose == MediaPurpose.privateVideo)
        h.inputs.last.videoDuration = 30001;
      final action = purpose == MediaPurpose.privateVoice
          ? () async {
              await visit.startRecording();
              await visit.finishRecording();
            }
          : () => visit.pick(purpose);
      await expectLater(action(), throwsA(isA<ApiException>()));
      expect(h.http.requests, isEmpty);
      expect(visit.intent, isNull);
    });
  }
  for (final voice in [false, true]) {
    test(
      'permission denied ${voice ? 'microphone' : 'gallery'} never allocates or records',
      () async {
        final visit = h.create().visit(pmPeer);
        await visit.loaded;
        h.inputs.last.permission = false;
        await expectLater(
          voice
              ? visit.startRecording()
              : visit.pick(MediaPurpose.privateImage),
          throwsA(isA<ApiException>()),
        );
        expect(h.inputs.last.starts, 0);
        expect(visit.recording, false);
        expect(h.http.requests, isEmpty);
      },
    );
  }
  test(
    'malformed persisted journal is fail closed without overwrite or new allocation',
    () async {
      await h.store.write(
        's13.private-media.v1.1.2',
        '{"schema":1,"url":"https://external.test"}',
      );
      final visit = h.create().visit(pmPeer);
      await visit.loaded;
      await expectLater(
        visit.pick(MediaPurpose.privateImage),
        throwsA(isA<ApiException>()),
      );
      expect(h.http.requests, isEmpty);
      expect(h.inputs.last.picks, 0);
      expect(
        await h.store.read('s13.private-media.v1.1.2'),
        contains('external.test'),
      );
    },
  );
  test(
    'cold cleanup only deletes owned subdirectories and never follows a symlink',
    () async {
      final root = Directory('${temp.path}/s13-private-media-v1');
      await root.create();
      final owned = Directory('${root.path}/s13-media-old');
      await owned.create();
      await File('${owned.path}/content').writeAsBytes([1]);
      final foreign = Directory('${root.path}/other-feature');
      await foreign.create();
      final outside = Directory('${temp.path}/outside');
      await outside.create();
      await Link('${root.path}/s13-media-link').create(outside.path);
      final provider = PrivateMediaTemporaryRoot(() async => temp);
      expect((await provider.get()).path, root.path);
      expect(await owned.exists(), false);
      expect(await foreign.exists(), true);
      expect(await outside.exists(), true);
      final fresh = await root.createTemp('s13-media-');
      await provider.get();
      expect(await fresh.exists(), true);
    },
  );
  test(
    'journal write failure is zero POST; retry preserves original send key',
    () async {
      final store = _FailingStore(h.store);
      final visit = await h.ready(h.create(storage: store));
      final key = visit.intent!.requestId;
      final count = h.http.requests.length;
      store.fail = true;
      await expectLater(
        visit.send(h.repository),
        throwsA(isA<FileSystemException>()),
      );
      expect(h.http.requests.length, count);
      expect(visit.intent!.requestId, key);
      store.fail = false;
      await visit.send(h.repository);
      expect(h.http.requests.last.headers.value('X-Request-Id'), key);
    },
  );
  test('concurrent duplicate click cannot create a second send', () async {
    final visit = await h.ready(h.create());
    final entered = Completer<void>(), gate = Completer<MediaFakeResponse>();
    h.intercept = (_) {
      entered.complete();
      return gate.future;
    };
    final send = visit.send(h.repository);
    await entered.future;
    await expectLater(visit.send(h.repository), throwsA(isA<ApiException>()));
    gate.complete(MediaFakeResponse.json(h.receipt()));
    await send;
    expect(
      h.http.requests.where((r) => r.uri.path.endsWith('/message/send')).length,
      1,
    );
  });
  test(
    'same identity 401 recovery keeps original key/body and refreshed authorization',
    () async {
      final visit = await h.ready(h.create());
      var posts = 0, refreshes = 0;
      h.intercept = (r) {
        posts++;
        return posts == 1
            ? MediaFakeResponse.json({}, status: 401, code: 40101)
            : h.respond(r);
      };
      final repo = BackendMessageRepository(
        apiClient: h.http.api(
          h.identity,
          refresh: () async {
            refreshes++;
            h.identity.refreshToken();
            return true;
          },
        ),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => h.identity.user,
      );
      await visit.send(repo);
      final sends = h.http.requests
          .where((r) => r.uri.path.endsWith('/message/send'))
          .toList();
      expect(refreshes, 1);
      expect(sends.length, 2);
      expect(sends.last.body, sends.first.body);
      expect(
        sends.last.headers.value('X-Request-Id'),
        sends.first.headers.value('X-Request-Id'),
      );
      expect(
        sends.last.headers.value('Authorization'),
        'Bearer contract-refreshed',
      );
    },
  );
  test(
    '401 recovery changing identity never sends original media with new token',
    () async {
      final visit = await h.ready(h.create());
      h.intercept = (_) => MediaFakeResponse.json({}, status: 401, code: 40101);
      final repo = BackendMessageRepository(
        apiClient: h.http.api(
          h.identity,
          refresh: () async {
            h.identity.change(7);
            return true;
          },
        ),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => h.identity.user,
      );
      await expectLater(visit.send(repo), throwsA(isA<ApiException>()));
      expect(
        h.http.requests
            .where((r) => r.uri.path.endsWith('/message/send'))
            .length,
        1,
      );
      expect(
        await h.store.read('s13.private-media.v1.1.2'),
        contains('"sendAttempted":true'),
      );
    },
  );
}
