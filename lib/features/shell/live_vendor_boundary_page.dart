import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';

class LiveVendorBoundaryPage extends StatefulWidget {
  const LiveVendorBoundaryPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<LiveVendorBoundaryPage> createState() => _LiveVendorBoundaryPageState();
}

class _LiveVendorBoundaryPageState extends State<LiveVendorBoundaryPage> {
  VendorReadinessOverview? _overview;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final VendorReadinessOverview overview = await widget
          .dependencies
          .liveReadOnlyRepository
          .fetchVendorReadiness();
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '厂商接入状态加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final VendorReadinessOverview? overview = _overview;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('vendor-readiness-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: <Widget>[
            Text('厂商接入准备', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '状态来自后端的脱敏接入清单。只有边界就绪不代表厂商能力已启用；缺少适配器或服务端密钥时必须返回 VENDOR_BLOCKED。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 72),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _VendorReadinessError(message: _error!, onRetry: _load)
            else if (overview != null) ...<Widget>[
              _VendorSummaryCard(overview: overview),
              const SizedBox(height: 14),
              for (final String capability in const <String>[
                'SMS',
                'RTC',
                'IM',
                'PAYMENT',
              ])
                if (overview.capabilities[capability] case final item?)
                  _VendorCapabilityCard(readiness: item),
              const SizedBox(height: 8),
              const _SecurityBoundaryCard(),
            ],
          ],
        ),
      ),
    );
  }
}

class _VendorSummaryCard extends StatelessWidget {
  const _VendorSummaryCard({required this.overview});

  final VendorReadinessOverview overview;

  @override
  Widget build(BuildContext context) {
    final bool boundariesReady = overview.allBoundariesReady;
    final bool runtimeReady = overview.allRuntimeAdaptersReady;
    return Material(
      key: const Key('vendor-readiness-summary'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  boundariesReady
                      ? Icons.verified_user_outlined
                      : Icons.gpp_bad_outlined,
                  color: boundariesReady ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    overview.integrationStatus,
                    key: const Key('vendor-integration-status'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('契约版本：${overview.contractVersion}'),
            Text(
              '运行状态：${overview.runtimeStatus}',
              key: const Key('vendor-runtime-status'),
            ),
            const SizedBox(height: 8),
            Text(
              runtimeReady
                  ? '所有运行时适配器均已配置，可以开始厂商沙箱联调。'
                  : '运行时仍被阻断；可以安全提交厂商凭证和适配器实现，不会误触发生产调用。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorCapabilityCard extends StatelessWidget {
  const _VendorCapabilityCard({required this.readiness});

  final VendorCapabilityReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final bool boundaryReady = readiness.boundaryReady;
    final bool runtimeReady = readiness.runtimeReady;
    final String capability = readiness.capability;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: Key('vendor-${capability.toLowerCase()}-status'),
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(_capabilityIcon(capability), color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _capabilityLabel(capability),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(readiness.adapterContract),
                      ],
                    ),
                  ),
                  _StatusPill(
                    label: boundaryReady ? '边界就绪' : '边界失败',
                    positive: boundaryReady,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text('运行时：${readiness.runtimeStatus}'),
                  const Spacer(),
                  Text('Provider：${readiness.provider}'),
                ],
              ),
              if (!runtimeReady) ...<Widget>[
                const SizedBox(height: 10),
                Text('待补配置', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
                for (final String item in readiness.missingConfiguration)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $item',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                readiness.securityBoundary,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final Color color = positive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _SecurityBoundaryCard extends StatelessWidget {
  const _SecurityBoundaryCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('vendor-secret-boundary'),
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, color: AppColors.accent),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '移动端不保存短信、RTC、IM 或支付密钥。签名、Token、UserSig、支付下单与回调验签全部由服务端适配器完成。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorReadinessError extends StatelessWidget {
  const _VendorReadinessError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('vendor-readiness-error'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, color: AppColors.error),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

String _capabilityLabel(String capability) => switch (capability) {
  'SMS' => '短信',
  'RTC' => '实时语音 RTC',
  'IM' => '腾讯 IM',
  'PAYMENT' => '支付',
  _ => capability,
};

IconData _capabilityIcon(String capability) => switch (capability) {
  'SMS' => Icons.sms_outlined,
  'RTC' => Icons.graphic_eq_rounded,
  'IM' => Icons.forum_outlined,
  'PAYMENT' => Icons.payments_outlined,
  _ => Icons.extension_outlined,
};
