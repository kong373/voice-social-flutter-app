import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';

class LiveBackendReadinessPage extends StatefulWidget {
  const LiveBackendReadinessPage({required this.service, super.key});

  final LiveBackendReadinessService service;

  @override
  State<LiveBackendReadinessPage> createState() =>
      _LiveBackendReadinessPageState();
}

class _LiveBackendReadinessPageState
    extends State<LiveBackendReadinessPage> {
  LiveBackendReadinessSnapshot? _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_runCheck);
  }

  Future<void> _runCheck() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final LiveBackendReadinessSnapshot snapshot = await widget.service.check();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _busy = false;
    });
  }

  Future<void> _copySummary() async {
    final LiveBackendReadinessSnapshot? snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: snapshot.toRedactedText()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制脱敏诊断摘要')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LiveBackendReadinessSnapshot? snapshot = _snapshot;
    final Map<String, Object?> environment =
        widget.service.environment.redactedSummary;
    return Scaffold(
      appBar: AppBar(title: const Text('开发环境联调诊断')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: <Widget>[
          const _NoticeCard(
            icon: Icons.security_rounded,
            text: '本页只探测配置、DNS、TLS 和 HTTP 网关可达性，不调用正式短信、RTC、IM 或支付，也不会显示任何密钥。',
          ),
          const SizedBox(height: 16),
          Text('运行配置', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _DetailsCard(
            entries: <MapEntry<String, String>>[
              MapEntry<String, String>(
                '模式',
                environment['backendMode'].toString(),
              ),
              MapEntry<String, String>(
                '环境',
                environment['deploymentEnvironment'].toString(),
              ),
              MapEntry<String, String>(
                '网关',
                environment['apiOrigin'].toString(),
              ),
              MapEntry<String, String>(
                '客户端',
                '${environment['clientType']} / ${environment['clientInnerVersion']}',
              ),
              MapEntry<String, String>(
                '超时',
                '${environment['apiTimeoutSeconds']} 秒',
              ),
              MapEntry<String, String>(
                '探测路径',
                environment['liveProbePath'].toString(),
              ),
              MapEntry<String, String>(
                '公开 Client ID',
                environment['oauthClientIdConfigured'] == true
                    ? '已配置（值已隐藏）'
                    : '未配置',
              ),
              const MapEntry<String, String>(
                '移动端 Client Secret',
                '未携带（正确）',
              ),
              MapEntry<String, String>(
                '开发验证码回读',
                environment['developmentOutboxConfigured'] == true
                    ? '已配置（仅本地/开发）'
                    : '未启用',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('探测结果', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (snapshot == null)
            const _ResultCard.loading()
          else
            _ResultCard(snapshot: snapshot),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _runCheck,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_busy ? '正在检查…' : '重新检查'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: '复制脱敏摘要',
                onPressed: snapshot == null ? null : _copySummary,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _NoticeCard(
            icon: Icons.info_outline_rounded,
            text: '“网关可达”只代表网络传输链路已收到 HTTP 响应，不等于业务接口或第三方能力已经联调通过。',
          ),
          const SizedBox(height: 10),
          const _NoticeCard(
            icon: Icons.extension_off_outlined,
            text: '正式短信、RTC、腾讯 IM、微信支付、支付宝、Apple IAP、推送和对象存储在厂商配置完成前保持 VENDOR_BLOCKED。',
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.entries});

  final List<MapEntry<String, String>> entries;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            for (int index = 0; index < entries.length; index += 1) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 112,
                    child: Text(
                      entries[index].key,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Text(entries[index].value)),
                ],
              ),
              if (index != entries.length - 1) const Divider(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.snapshot}) : loading = false;

  const _ResultCard.loading()
      : snapshot = null,
        loading = true;

  final LiveBackendReadinessSnapshot? snapshot;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final LiveBackendReadinessSnapshot value = snapshot!;
    final Color color = _statusColor(value.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_statusIcon(value.status), color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value.status.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(value.message),
            const SizedBox(height: 10),
            Text(
              <String>[
                if (value.httpStatus != null) 'HTTP ${value.httpStatus}',
                if (value.latency != null)
                  '${value.latency!.inMilliseconds} ms',
                value.checkedAt.toLocal().toIso8601String(),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(LiveBackendReadinessStatus status) => switch (status) {
      LiveBackendReadinessStatus.gatewayReachable => AppColors.success,
      LiveBackendReadinessStatus.mockMode => AppColors.accent,
      LiveBackendReadinessStatus.configurationInvalid ||
      LiveBackendReadinessStatus.tlsRejected =>
        AppColors.error,
      LiveBackendReadinessStatus.networkUnavailable ||
      LiveBackendReadinessStatus.timedOut ||
      LiveBackendReadinessStatus.unexpectedFailure =>
        AppColors.warning,
    };

IconData _statusIcon(LiveBackendReadinessStatus status) => switch (status) {
      LiveBackendReadinessStatus.gatewayReachable => Icons.cloud_done_outlined,
      LiveBackendReadinessStatus.mockMode => Icons.science_outlined,
      LiveBackendReadinessStatus.configurationInvalid =>
        Icons.settings_suggest_outlined,
      LiveBackendReadinessStatus.tlsRejected => Icons.gpp_bad_outlined,
      LiveBackendReadinessStatus.networkUnavailable =>
        Icons.cloud_off_outlined,
      LiveBackendReadinessStatus.timedOut => Icons.timer_off_outlined,
      LiveBackendReadinessStatus.unexpectedFailure =>
        Icons.error_outline_rounded,
    };
