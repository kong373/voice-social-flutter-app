import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays the numeric first-party user identity accepted by social actions.
/// Login names, phone numbers and record UUIDs are not interchangeable with it.
class PublicUserIdLabel extends StatelessWidget {
  const PublicUserIdLabel({
    required this.userId,
    this.prefix = 'ID',
    this.suffix = '',
    this.style,
    this.maxLines,
    this.textAlign,
    super.key,
  });

  final int userId;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final bool available = userId > 0;
    return Tooltip(
      message: available ? '复制用户 ID' : '用户 ID 暂不可用',
      child: Semantics(
        button: available,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !available
              ? null
              : () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: '$userId'));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('用户 ID 已复制')));
                  } on PlatformException {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('暂时无法复制用户 ID，请重试')),
                    );
                  }
                },
          child: Text(
            available ? '$prefix $userId$suffix' : '用户 ID 暂不可用',
            style: style,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            textAlign: textAlign,
          ),
        ),
      ),
    );
  }
}
