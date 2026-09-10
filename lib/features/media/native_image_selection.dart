import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';

abstract interface class ImageSelection {
  Future<List<XFile>> pick(int remaining);
}

class NativeImageSelection implements ImageSelection {
  NativeImageSelection({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  bool _checkedLostData = false;

  @override
  Future<List<XFile>> pick(int remaining) async {
    try {
      return await _pick(remaining);
    } on PlatformException catch (error) {
      throw switch (error.code) {
        'photo_access_denied' ||
        'photo_access_restricted' => const ApiException(
          kind: ApiFailureKind.forbidden,
          message: '未获得照片访问权限，请在系统设置中允许后重试',
        ),
        'already_active' => const ApiException(
          kind: ApiFailureKind.conflict,
          message: '系统选图页面已打开，请先完成或取消本次选择',
        ),
        _ => const ApiException(
          kind: ApiFailureKind.configuration,
          message: '系统照片选择器暂不可用，请稍后重试',
        ),
      };
    }
  }

  Future<List<XFile>> _pick(int remaining) async {
    if (Platform.isAndroid && !_checkedLostData) {
      _checkedLostData = true;
      final lost = await _picker.retrieveLostData();
      if (!lost.isEmpty) {
        // A restarted Activity supplies files, but no trusted original actor.
        // Never attach these to the current account or delete picker-owned data.
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          message: '上次选图被系统中断，请重新选择；不会自动上传恢复的文件',
        );
      }
    }
    return _picker.pickMultiImage(limit: remaining, requestFullMetadata: false);
  }
}
