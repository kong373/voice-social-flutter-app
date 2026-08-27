import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

/// The first-party agreement gate.
///
/// This is an app-owned, versioned consent document. It is intentionally not
/// presented as a third-party legal review or certification. A caller must
/// persist the acknowledgement before the app can leave this gate.
class ConsentPage extends StatefulWidget {
  const ConsentPage({required this.onAccept, super.key});

  final Future<void> Function() onAccept;

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  final ScrollController _scrollController = ScrollController();
  bool _hasReachedEnd = false;
  bool _checked = false;
  bool _submitting = false;
  String? _error;

  bool get _canContinue => _hasReachedEnd && _checked && !_submitting;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _hasReachedEnd) {
      return;
    }
    if (_scrollController.position.extentAfter <= 24) {
      setState(() => _hasReachedEnd = true);
    }
  }

  Future<void> _submit() async {
    if (!_canContinue) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onAccept();
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = '协议保存失败，请重试。${error is Error ? '' : '当前未进入应用。'}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      bottomNavigationBar: AccountBottomActionBar(
        child: AccountPrimaryAction(
          key: const Key('consent-submit'),
          label: _submitting ? '保存中…' : '同意并继续',
          icon: _submitting
              ? Icons.hourglass_top_rounded
              : Icons.arrow_forward_rounded,
          busy: _submitting,
          onPressed: _canContinue ? _submit : null,
        ),
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('consent-scroll'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 32),
          children: <Widget>[
            const AccountMistHero(
              eyebrow: 'WELCOME',
              title: '欢迎使用',
              subtitle: '请阅读应用内协议正文，滚动至文末并确认后继续。',
              markSize: 60,
              centered: false,
            ),
            const SizedBox(height: 25),
            const AccountSectionLabel(text: '应用协议 · App-owned v2'),
            const AccountSheet(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: _ConsentBody(),
            ),
            const SizedBox(height: 18),
            AccountNoticeStrip(
              icon: Icons.privacy_tip_outlined,
              text:
                  '本协议由本应用以 App-owned v2 版本发布和留档，不代表第三方法律审核或认证。协议更新后，应用会再次请求你的确认。',
              tone: AccountOxygenColors.cyan,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextButton(
                  key: const Key('consent-user-agreement'),
                  onPressed: () => _showDocument(context, '用户协议'),
                  child: const Text('查看用户协议正文'),
                ),
                Text('和', style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  key: const Key('consent-privacy-policy'),
                  onPressed: () => _showDocument(context, '隐私政策'),
                  child: const Text('查看隐私政策正文'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              key: const Key('consent-agreement-checkbox'),
              value: _checked,
              onChanged: _hasReachedEnd && !_submitting
                  ? (bool? value) {
                      setState(() => _checked = value ?? false);
                    }
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('我已阅读并同意 App-owned v2 用户协议与隐私政策'),
              subtitle: Text(_hasReachedEnd ? '已读到正文末尾，可以确认。' : '请先滚动到正文末尾。'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              AccountNoticeStrip(
                key: const Key('consent-error'),
                icon: Icons.error_outline_rounded,
                text: _error!,
                tone: AppColors.error,
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          title: const Text('暂不使用'),
                          content: const Text('不同意协议将无法进入应用。你可以关闭应用后再决定。'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('返回'),
                            ),
                          ],
                        ),
                      ),
                child: const Text('暂不使用'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showDocument(BuildContext context, String title) =>
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (BuildContext context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '$title · ${AuthSessionManager.consentVersion}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  const _ConsentBody(showTitle: false),
                  const SizedBox(height: 18),
                  const Text('这是应用自行发布的版本化文本，不是第三方法律审核证明。'),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('知道了'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ConsentBody extends StatelessWidget {
  const _ConsentBody({this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final TextStyle? heading = Theme.of(context).textTheme.titleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('用户协议与隐私政策正文', style: heading),
          const SizedBox(height: 12),
        ],
        Text('1. 服务范围', style: heading),
        const SizedBox(height: 5),
        const Text('本应用提供声音房间、动态、关系和消息等产品功能。具体功能是否可用，以服务端返回的账号状态和能力状态为准。'),
        const SizedBox(height: 12),
        Text('2. 信息处理边界', style: heading),
        const SizedBox(height: 5),
        const Text(
          '应用会在登录安全、账号保护、房间互动和消息通知所必需的范围内处理账号、设备和操作信息。系统权限只会在对应功能需要时请求。',
        ),
        const SizedBox(height: 12),
        Text('3. 账号与内容责任', style: heading),
        const SizedBox(height: 5),
        const Text(
          '你应当保护登录凭据并对自行发布的内容负责。平台可以依据服务端规则限制违反法律、协议或社区规则的账号，并提供可用时的申诉入口。',
        ),
        const SizedBox(height: 12),
        Text('4. 版本与变更', style: heading),
        const SizedBox(height: 5),
        const Text(
          '本次确认绑定 App-owned v2。后续版本发生实质变更时，应用会清除旧版本的确认效力，在进入主要功能前重新展示对应版本正文。',
        ),
        const SizedBox(height: 12),
        Text('5. 厂商能力边界', style: heading),
        const SizedBox(height: 5),
        const Text(
          '实时音视频功能可能使用声网 Agora；消息会话与消息通知可能使用腾讯云即时通信 IM。仅在对应功能启用并完成本次确认后，应用才会连接相应提供方。为完成登录、连接、风控和故障诊断，可能处理必要的设备标识、操作系统与版本、网络地址/网络状态、房间或会话标识，以及服务端签发的短期连接凭证；不会在客户端生成或持久化厂商密钥。未启用的能力会显示不可用状态，应用不会把本地演示或缺失适配器描述为正式厂商成功。',
        ),
        const SizedBox(height: 12),
        Text('6. 支付 SDK 说明', style: heading),
        const SizedBox(height: 5),
        const Text(
          '仅当你主动确认 Android 充值并点击支付宝支付时，应用才会调用支付宝 App Pay SDK，目的是打开支付宝或其网页支付流程并处理订单返回。SDK 可能处理服务端签名订单串、订单结果状态，以及完成网络请求和应用切换所需的设备、网络和已安装应用可用性信息；应用只接收脱敏后的临时结果分类，到账和金额以本应用服务端订单状态为准。应用不会把支付宝私钥、证书或长期支付密钥放入客户端。',
        ),
        const SizedBox(height: 12),
        Text('7. 第三方能力的主动触发', style: heading),
        const SizedBox(height: 5),
        const Text(
          '支付宝支付以及其他可选第三方能力只会在对应功能被明确操作且配置已通过检查时尝试调用；未配置、取消、超时或返回不确定状态时，应用会回到服务端核验或明确失败，不会伪造成功。相关厂商对其处理活动另有说明的，以其实际页面和隐私规则为准。',
        ),
        // Keep the document long enough that the user must deliberately reach
        // the end on a phone-sized viewport.
        const SizedBox(height: 260),
        const Text('正文结束 · App-owned v2'),
      ],
    );
  }
}
