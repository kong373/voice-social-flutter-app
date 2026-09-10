import 'dart:io';

/// One lazy initialization per App host. Cold start removes only previous
/// media-owned subdirectories, never picker originals or another feature's
/// cache. The journal has no paths and recovery never reuses these bytes.
class PrivateMediaTemporaryRoot {
  PrivateMediaTemporaryRoot(this.parent);
  final Future<Directory> Function() parent;
  Future<Directory>? _root;
  Future<Directory> get() => _root ??= _prepare();
  Future<Directory> _prepare() async {
    final base = await parent();
    final root = Directory('${base.path}/s13-private-media-v1');
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException(
        'Private media temporary root is not a directory',
      );
    }
    await root.create();
    await for (final entry in root.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (entry is Directory &&
          RegExp(
            r'^s13-(media|private-record)-[A-Za-z0-9_-]+$',
          ).hasMatch(name)) {
        await entry.delete(recursive: true);
      }
    }
    return root;
  }
}
