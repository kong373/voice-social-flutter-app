import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_models.dart';
import 'support/registration_avatar_fakes.dart';

void main() {
  test(
    'selection flags and immutable RAM preview survive upload but not context loss',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final host = f.host();
      expect(host.hasSelection, false);
      expect(host.hasPendingUpload, false);
      await host.choose();
      expect(host.status, isNull);
      expect(host.hasSelection, true);
      expect(host.hasPendingUpload, true);
      expect(host.previewBytes, avatarPng);
      expect(() => host.previewBytes![0] = 0, throwsUnsupportedError);
      await host.upload();
      await host.cleanup;
      expect(host.hasPendingUpload, false);
      expect(host.previewBytes, avatarPng);
      expect((await f.directory.list().toList()).length, 1);
      f.signal.change();
      f.signal.change();
      expect(host.previewBytes, isNull);
      expect(host.hasSelection, false);
      expect(host.ready, isNull);
      final cold = f.host();
      await cold.restore();
      expect(cold.hasSelection, true);
      expect(cold.hasPendingUpload, true);
      expect(cold.previewBytes, isNull);
      await cold.recover();
      expect(cold.hasPendingUpload, false);
      expect(cold.ready?.assetId, avatarTestId);
      cold.dispose();
      expect(cold.previewBytes, isNull);
    },
  );
  test(
    'UUID phone SMS and headers reject suffix newlines and wrong lengths',
    () {
      final signal = AvatarSignal();
      addTearDown(signal.dispose);
      for (final value in [
        '$avatarTestId\n',
        avatarTestId.substring(1),
        'x$avatarTestId',
      ]) {
        expect(
          () => registrationAvatarUuid(value),
          throwsA(isA<ApiException>()),
        );
      }
      expect(
        () => signal.context(phone: '13800138000\n'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => signal.context(code: '123456\n'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => signal.context(device: 'device\n'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => signal.context(client: 'client\r\n'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => signal.context(
          expiry: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('backend quarantine allows observed bytes before detected type', () {
    final signal = AvatarSignal();
    addTearDown(signal.dispose);
    final server = AvatarServer(signal.expiresAt)
      ..state = 'QUARANTINED'
      ..version = 2;
    final status = RegistrationAvatarStatus.fromData(server.projection());
    expect(status.bytes, avatarPng.length);
    expect(status.mediaType, isNull);
  });
  test(
    'selected image follows persisted allocation and one PUT to strict READY',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      f.store.beforeWrite = (value) async {
        if (value['allocationAttempted'] == true && value['status'] == null)
          expect(f.server.allocations, 0);
        if (value['putAttempted'] == true &&
            (value['status'] as Map)['state'] == 'ALLOCATED')
          expect(f.server.puts, 0);
      };
      final host = f.host();
      await host.choose();
      await host.upload();
      expect(host.ready?.assetId, avatarTestId);
      expect(host.ready?.version, 3);
      expect(f.server.puts, 1);
      expect(f.server.allocations, 1);
      expect(f.server.completes, 1);
      expect(f.store.record.containsKey('smsCode'), false);
      expect(f.store.record.containsKey('token'), false);
      expect(f.store.record.containsKey('path'), false);
      final cap = host.ready!.capability;
      expect(cap.length, 43);
      expect(base64Url.decode('$cap=').length, 32);
      expect(
        base64Url.encode(base64Url.decode('$cap=')).replaceAll('=', '') == cap,
        true,
      );
      expect(f.store.record['capability'] == cap, true);
      final requests = f.server.http.requests;
      expect(
        requests.every((r) => r.headers.value('Authorization') == null),
        true,
      );
      expect(
        requests.every(
          (r) => r.headers.value('X-Request-Id') == host.ready!.requestId,
        ),
        true,
      );
      expect(
        requests.every(
          (r) => r.headers.value('X-Registration-Avatar-Capability') == cap,
        ),
        true,
      );
      expect(
        requests.every((r) => !r.followRedirects && r.maxRedirects == 0),
        true,
      );
      expect(requests.singleWhere((r) => r.method == 'PUT').body, avatarPng);
      await host.cleanup;
      expect(await f.original.exists(), true);
      expect((await f.directory.list().toList()).length, 1);
    },
  );

  for (final loss in ['allocation', 'put', 'complete']) {
    test(
      'cold $loss loss restores same capability key and asset without PUT replay',
      () async {
        final f = await AvatarFixture.create();
        addTearDown(f.dispose);
        f.server.loseAllocation = loss == 'allocation';
        f.server.losePut = loss == 'put';
        f.server.loseComplete = loss == 'complete';
        final first = f.host();
        await first.choose();
        await expectLater(first.upload(), throwsA(isA<ApiException>()));
        final original = f.store.record;
        first.dispose();
        await first.cleanup;
        final restored = f.host();
        await restored.restore();
        expect(restored.ready, isNull);
        final initialPuts = f.server.puts;
        await restored.recover();
        expect(f.server.puts, initialPuts);
        expect(f.store.record['capability'] == original['capability'], true);
        expect(f.store.record['requestId'] == original['requestId'], true);
        expect(restored.status?.assetId, avatarTestId);
        if (loss == 'allocation') {
          expect(restored.sourceUnavailable, true);
          expect(restored.ready, isNull);
          await expectLater(restored.upload(), throwsA(isA<ApiException>()));
          expect(f.server.puts, 0);
          expect(
            f.server.allocations,
            2,
          ); // Idempotent replay, not a new allocation key.
        } else {
          expect(restored.ready?.version, 3);
        }
        expect(f.picker.calls, 1);
        expect(await f.original.exists(), true);
      },
    );
  }
  test(
    'scan unavailability keeps original quarantine and completes explicitly later',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      f.server.scanUnavailable = true;
      final host = f.host();
      await host.choose();
      await expectLater(host.upload(), throwsA(isA<ApiException>()));
      expect(host.status?.state, RegistrationAvatarState.quarantined);
      expect(host.ready, isNull);
      f.server.scanUnavailable = false;
      await host.complete();
      expect(host.ready?.assetId, avatarTestId);
      expect(f.server.puts, 1);
      expect(f.server.allocations, 1);
    },
  );
  for (final phase in ['selection', 'allocation', 'put']) {
    test(
      '$phase persistence failure sends no corresponding network mutation',
      () async {
        final f = await AvatarFixture.create();
        addTearDown(f.dispose);
        f.store.beforeWrite = (value) async {
          if (phase == 'selection' ||
              (phase == 'allocation' && value['allocationAttempted'] == true) ||
              (phase == 'put' && value['putAttempted'] == true))
            throw StateError('secure store unavailable');
        };
        final host = f.host();
        if (phase == 'selection')
          await expectLater(host.choose(), throwsStateError);
        else {
          await host.choose();
          await expectLater(host.upload(), throwsStateError);
        }
        expect(f.server.puts, 0);
        expect(f.server.completes, 0);
        expect(f.server.allocations, phase == 'put' ? 1 : 0);
      },
    );
  }
  test(
    'cold put marker blocks a PUT even if server remains ALLOCATED',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      f.store.beforeWrite = (value) async {
        if (value['putAttempted'] == true)
          throw StateError('write interrupted');
      };
      final host = f.host();
      await host.choose();
      await expectLater(host.upload(), throwsStateError);
      // Model a durable pre-PUT write followed by process death, before send.
      final record = f.store.record..['putAttempted'] = true;
      f.store.data[f.store.data.keys.single] = jsonEncode(record);
      f.store.beforeWrite = null;
      host.dispose();
      await host.cleanup;
      final cold = f.host();
      await cold.restore();
      await expectLater(cold.recover(), throwsA(isA<ApiException>()));
      expect(cold.ready, isNull);
      expect(cold.status?.state, RegistrationAvatarState.allocated);
      expect(f.server.puts, 0);
      expect(f.server.allocations, 1);
    },
  );
  test(
    'stored READY does not export proof until current GET validates original TTL',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final first = f.host();
      await first.choose();
      await first.upload();
      first.dispose();
      final second = f.host();
      await second.restore();
      expect(second.ready, isNull);
      f.server.extendExpiry = true;
      await expectLater(second.recover(), throwsA(isA<ApiException>()));
      expect(second.ready, isNull);
      f.server.extendExpiry = false;
      await second.recover();
      expect(second.ready?.assetId, avatarTestId);
    },
  );
  for (final changed in [
    'phone',
    'code',
    'device',
    'client',
    'challenge',
    'expiry',
  ]) {
    test('journal cannot transfer to changed $changed context', () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final first = f.host();
      await first.choose();
      first.dispose();
      final context = f.signal.context(
        phone: changed == 'phone' ? '13900139000' : '13800138000',
        code: changed == 'code' ? '234567' : '123456',
        device: changed == 'device' ? 'device-B' : 'device-A',
        client: changed == 'client' ? 'other-client' : 'public-client',
        challenge: changed == 'challenge'
            ? '33333333-3333-4333-8333-333333333333'
            : avatarChallenge,
        expiry: changed == 'expiry'
            ? f.signal.expiresAt.add(const Duration(seconds: 1))
            : null,
      );
      final next = f.host(context: context);
      if (const ['phone', 'code', 'expiry'].contains(changed))
        await expectLater(next.restore(), throwsA(isA<ApiException>()));
      else
        await next.restore();
      expect(next.ready, isNull);
      expect(next.status, isNull);
      expect(f.server.allocations, 0);
    });
  }
  test(
    'picker ABA neither adopts late selection nor deletes picker-owned original',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      f.picker.pause = Completer<void>();
      f.picker.entered = Completer<void>();
      final host = f.host();
      final choosing = expectLater(host.choose(), throwsA(isA<ApiException>()));
      await f.picker.entered!.future.timeout(const Duration(seconds: 5));
      f.signal.change();
      f.signal.change();
      f.picker.pause!.complete();
      await choosing;
      expect(f.store.data.isEmpty, true);
      expect(await f.original.exists(), true);
      expect(host.ready, isNull);
    },
  );
  test(
    'discard cancels a blocked upload and retains original durable command',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final reached = Completer<void>(), release = Completer<void>();
      f.server.http.beforeOpen = (count) async {
        if (count == 2) {
          reached.complete();
          await release.future;
        }
      };
      final host = f.host();
      await host.choose();
      final uploading = expectLater(
        host.upload(),
        throwsA(isA<ApiException>()),
      );
      await reached.future.timeout(const Duration(seconds: 5));
      await host.discard();
      release.complete();
      await uploading;
      expect(host.ready, isNull);
      expect(f.store.record['putAttempted'], true);
      expect(f.server.puts, 0);
      expect(await f.original.exists(), true);
    },
  );
  test('choosing a replacement cannot erase an uncertain allocation', () async {
    final f = await AvatarFixture.create();
    addTearDown(f.dispose);
    f.server.loseAllocation = true;
    final host = f.host();
    await host.choose();
    await expectLater(host.upload(), throwsA(isA<ApiException>()));
    final before = f.store.record;
    await expectLater(host.choose(), throwsA(isA<ApiException>()));
    expect(f.store.record['requestId'] == before['requestId'], true);
    expect(f.picker.calls, 1);
  });
  test('parallel upload shares one flight and one raw PUT', () async {
    final f = await AvatarFixture.create();
    addTearDown(f.dispose);
    final host = f.host();
    await host.choose();
    final first = host.upload(), second = host.upload();
    expect(identical(first, second), true);
    await Future.wait([first, second]);
    expect(f.server.puts, 1);
  });
  test(
    'context loss during durable write fences old sender and cold restore waits for same intent',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final old = f.host();
      await old.choose();
      final selected = f.store.record;
      final entered = Completer<void>(), release = Completer<void>();
      f.store.beforeWrite = (value) async {
        if (value['allocationAttempted'] == true) {
          entered.complete();
          await release.future;
        }
      };
      final uploading = expectLater(old.upload(), throwsA(isA<ApiException>()));
      await entered.future.timeout(const Duration(seconds: 5));
      old.dispose();
      final cold = f.host();
      final restoring = cold.restore();
      expect(cold.busy, true);
      release.complete();
      await uploading;
      await restoring;
      expect(f.server.allocations, 0);
      expect(f.server.puts, 0);
      expect(cold.hasSelection, true);
      expect(cold.hasPendingUpload, true);
      expect(cold.previewBytes, isNull);
      expect(f.store.record['allocationAttempted'], true);
      expect(f.store.record['requestId'] == selected['requestId'], true);
      expect(f.store.record['capability'] == selected['capability'], true);
    },
  );
  test(
    'exact decimal 10MB preview is bounded and dispose does not delete picker original',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final original = await f.original.open(mode: FileMode.write);
      await original.truncate(10000000);
      await original.close();
      final host = f.host();
      await host.choose();
      expect(host.previewBytes?.length, 10000000);
      expect(host.hasSelection, true);
      host.dispose();
      expect(host.previewBytes, isNull);
      await host.cleanup;
      expect(await f.original.length(), 10000000);
      expect((await f.directory.list().toList()).length, 1);
      expect(f.server.allocations, 0);
    },
  );
  test(
    'single image selection enforces count and decimal 10MB before allocation',
    () async {
      final f = await AvatarFixture.create();
      addTearDown(f.dispose);
      final host = f.host();
      f.picker.files = [XFile(f.original.path), XFile(f.original.path)];
      await expectLater(host.choose(), throwsA(isA<ApiException>()));
      final large = File('${f.directory.path}/large-source');
      final output = await large.open(mode: FileMode.write);
      await output.truncate(10000001);
      await output.close();
      f.picker.files = [XFile(large.path)];
      await expectLater(host.choose(), throwsA(isA<ApiException>()));
      expect(f.server.allocations, 0);
      expect(f.store.data.isEmpty, true);
      expect(await large.exists(), true);
    },
  );
}
