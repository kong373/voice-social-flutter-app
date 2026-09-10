import '../../core/media/media_models.dart';

String mediaStateLabel(MediaAssetState? state, {bool attempted = false}) =>
    switch (state) {
      MediaAssetState.allocated => '待上传',
      MediaAssetState.uploading => '上传处理中',
      MediaAssetState.quarantined => '安全检查中',
      MediaAssetState.ready => '已上传',
      MediaAssetState.rejected => '文件未通过检查',
      MediaAssetState.revoked => '文件已失效',
      null => attempted ? '结果待确认' : '待上传',
    };
