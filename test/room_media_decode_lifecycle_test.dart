import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/room/presentation/room_cover_artwork.dart';

import 's13_image_host_test.dart' show TestImageSelection;
import 'support/media_http_fakes.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/p8AAAAASUVORK5CYII=',
);

void main() {
  for (final invalidation in ['ABA', 'room context', 'unmount']) {
    for (final buffered in [false, true]) {
      testWidgets(
        'pending room decode ${buffered ? 'success' : 'deleted-file error'} after $invalidation stays local and evicted',
        (tester) async {
          final identity = TestMediaIdentity();
          final changes = ChangeNotifier();
          var current = true;
          final temp = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('room-codec-race-'),
          ))!;
          final io = _PausedImageIo(temp.path, buffered: buffered);
          final http = MediaFakeHttp(
            (_) => MediaFakeResponse(
              200,
              Stream.value(_png),
              type: 'image/png',
              contentLength: _png.length,
            ),
          );
          final host = AppImageMediaHost(
            api: http.api(identity),
            userId: () => identity.user,
            generation: () => identity.generation,
            changes: identity,
            picker: TestImageSelection(),
            temporaryParent: () async => temp,
          );
          try {
            await IOOverrides.runWithIOOverrides(() async {
              await tester.pumpWidget(
                MaterialApp(
                  home: Scaffold(
                    body: SizedBox(
                      width: 200,
                      height: 200,
                      child: RoomMediaImage(
                        host: host,
                        media: MediaReference.fromJson({
                          'assetId': '11111111-2222-4333-8444-555555555501',
                          'purpose': 'ROOM_COVER',
                          'mediaType': 'image/png',
                          'bytes': _png.length,
                          'durationMillis': 0,
                          'version': 3,
                        }),
                        contextChanges: changes,
                        contextIsCurrent: () => current,
                      ),
                    ),
                  ),
                ),
              );
              await _until(tester, () => io.started.isCompleted);
              final image = find.byWidgetPredicate(
                (w) => w is Image && w.image is FileImage,
              );
              final provider = tester.widget<Image>(image).image as FileImage;
              // Resolving the same pending cache key adds no listener. An error
              // listener in this test would mask the production lifecycle bug.
              final completer = provider
                  .resolve(ImageConfiguration.empty)
                  .completer!;
              expect(
                PaintingBinding.instance.imageCache
                    .statusForKey(provider)
                    .pending,
                isTrue,
              );
              expect(io.release.isCompleted, isFalse);

              if (invalidation == 'ABA') {
                identity.change(2);
                identity.change(1);
              } else if (invalidation == 'room context') {
                current = false;
                changes.notifyListeners();
              } else {
                await tester.pumpWidget(const SizedBox());
              }
              await tester.pump(); // Remove Image/errorBuilder before I/O ends.
              await _until(tester, () => !provider.file.existsSync());
              expect(
                io.release.isCompleted,
                isFalse,
                reason:
                    'sensitive file deletion cannot wait for decoder completion',
              );
              expect(image, findsNothing);
              expect(
                PaintingBinding.instance.imageCache
                    .statusForKey(provider)
                    .pending,
                isFalse,
              );
              expect(
                PaintingBinding.instance.imageCache.statusForKey(provider).live,
                isFalse,
              );

              io.release.complete();
              await _until(
                tester,
                () => io.finished.isCompleted && !completer.hasListeners,
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason:
                    'a detached room codec must not report through FlutterError',
              );
              expect(image, findsNothing);
              expect(
                PaintingBinding.instance.imageCache.containsKey(provider),
                isFalse,
              );
              expect(
                PaintingBinding.instance.imageCache.statusForKey(provider).live,
                isFalse,
              );
              expect(http.requests, hasLength(1));
              expect(
                await tester.runAsync(
                  () async => (await temp.list().toList()).isEmpty,
                ),
                isTrue,
              );
            }, io);
          } finally {
            if (!io.release.isCompleted) io.release.complete();
            await tester.pumpWidget(const SizedBox());
            host.dispose();
            var cleaned = false;
            final cleanup = host.cleanup.then((_) => cleaned = true);
            await _until(tester, () => cleaned);
            await cleanup;
            identity.dispose();
            changes.dispose();
            await tester.runAsync(() => temp.delete(recursive: true));
          }
        },
      );
    }
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'controlled decode lifecycle did not settle');
}

/// Only pauses the actual FileImage read, not downloads, deletion, or widgets.
/// One variant reads after unlink (real PathNotFoundException); the other has
/// already read bytes and allows the real codec to finish after invalidation.
final class _PausedImageIo extends IOOverrides {
  _PausedImageIo(this.parent, {required this.buffered});
  final String parent;
  final bool buffered;
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.startsWith('$parent/') && path.endsWith('/content')
        ? _PausedImageFile(file, this)
        : file;
  }
}

class _PausedImageFile implements File {
  _PausedImageFile(this.file, this.io);
  final File file;
  final _PausedImageIo io;
  @override
  String get path => file.path;
  @override
  Future<int> length() => file.length();
  @override
  bool existsSync() => file.existsSync();
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = io.buffered ? await file.readAsBytes() : null;
    if (!io.started.isCompleted) io.started.complete();
    await io.release.future;
    try {
      return bytes ?? await file.readAsBytes();
    } finally {
      if (!io.finished.isCompleted) io.finished.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
