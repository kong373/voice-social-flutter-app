import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';

const List<String> _formalVendorCapabilities = <String>[
  'SMS',
  'RTC',
  'IM',
  'PAYMENT',
  'PUSH',
  'OBJECT_STORAGE',
];

class LiveVendorBoundaryPage extends StatefulWidget {
  const LiveVendorBoundaryPage({
    required this.dependencies,
    this.repository,
    super.key,
  });

  final AppDependencies dependencies;
  final LiveReadOnlyRepository? repository;

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
      final VendorReadinessOverview overview =
          await (widget.repository ??
                  widget.dependencies.liveReadOnlyRepository)
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
              for (final String capability in _formalVendorCapabilities)
                _VendorCapabilityCard(
                  capability: capability,
                  readiness: overview.capabilities[capability],
                ),
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
    final bool capabilitiesComplete = _hasAllFormalCapabilities(overview);
    final bool boundariesReady =
        overview.allBoundariesReady &&
        capabilitiesComplete &&
        _allBoundaryStatusesReady(overview);
    final bool runtimeReady =
        overview.allRuntimeAdaptersReady &&
        overview.runtimeStatus == 'READY' &&
        capabilitiesComplete &&
        _allRuntimeStatusesReady(overview);
    final String integrationStatus = _knownStatus(
      overview.integrationStatus,
      fallback: '接入状态未知（已阻断）',
    );
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
                    integrationStatus,
                    key: const Key('vendor-integration-status'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '契约版本：${_knownStatus(overview.contractVersion, fallback: '未知（已阻断）')}',
            ),
            Text(
              '运行状态：${_runtimeStatusLabel(overview.runtimeStatus)}',
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
  const _VendorCapabilityCard({
    required this.capability,
    required this.readiness,
  });

  final String capability;
  final VendorCapabilityReadiness? readiness;

  @override
  Widget build(BuildContext context) {
    final bool validReadiness =
        readiness != null && readiness!.capability == capability;
    final bool boundaryReady = validReadiness && readiness!.boundaryReady;
    final bool runtimeReady = validReadiness && readiness!.runtimeReady;
    final String runtimeStatus = validReadiness
        ? _runtimeStatusLabel(readiness!.runtimeStatus)
        : 'UNKNOWN（已阻断）';
    final String adapterContract = validReadiness
        ? _knownStatus(readiness!.adapterContract, fallback: '未知（已阻断）')
        : '未知（已阻断）';
    final String provider = validReadiness
        ? _knownStatus(readiness!.provider, fallback: 'UNCONFIGURED')
        : 'UNCONFIGURED';
    final List<String> missingConfiguration = validReadiness
        ? readiness!.missingConfiguration
        : const <String>[];
    final String securityBoundary = validReadiness
        ? _knownStatus(
            readiness!.securityBoundary,
            fallback: '服务端未返回该正式能力，已安全阻断。',
          )
        : '服务端未返回该正式能力，已安全阻断。';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: Key('vendor-${_capabilityKey(capability)}-status'),
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
                        Text(adapterContract),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _StatusPill(
                        label: boundaryReady ? '边界就绪' : '边界失败',
                        positive: boundaryReady,
                      ),
                      const SizedBox(height: 4),
                      _StatusPill(
                        label: runtimeReady ? '运行时已启用' : '已禁用',
                        positive: runtimeReady,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: <Widget>[
                  Text('运行时：$runtimeStatus'),
                  Text('Provider：$provider'),
                ],
              ),
              if (!runtimeReady) ...<Widget>[
                const SizedBox(height: 10),
                Text('待补配置', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
                if (missingConfiguration.isEmpty)
                  Text(
                    '服务端未返回该正式能力，已安全阻断。',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final String item in missingConfiguration)
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
                securityBoundary,
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
                '移动端不保存短信、RTC、IM、支付、推送或对象存储密钥。签名、Token、UserSig、支付下单与回调验签全部由服务端适配器完成。',
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
  'PUSH' => '推送',
  'OBJECT_STORAGE' => '对象存储',
  _ => capability,
};

IconData _capabilityIcon(String capability) => switch (capability) {
  'SMS' => Icons.sms_outlined,
  'RTC' => Icons.graphic_eq_rounded,
  'IM' => Icons.forum_outlined,
  'PAYMENT' => Icons.payments_outlined,
  'PUSH' => Icons.notifications_none_outlined,
  'OBJECT_STORAGE' => Icons.cloud_upload_outlined,
  _ => Icons.extension_outlined,
};

bool _hasAllFormalCapabilities(VendorReadinessOverview overview) {
  final Set<String> keys = overview.capabilities.keys.toSet();
  return keys.length == _formalVendorCapabilities.length &&
      _formalVendorCapabilities.every(
        (String capability) =>
            overview.capabilities[capability]?.capability == capability,
      );
}

bool _allBoundaryStatusesReady(VendorReadinessOverview overview) =>
    _formalVendorCapabilities.every(
      (String capability) =>
          overview.capabilities[capability]?.boundaryReady == true,
    );

bool _allRuntimeStatusesReady(VendorReadinessOverview overview) =>
    _formalVendorCapabilities.every(
      (String capability) =>
          overview.capabilities[capability]?.runtimeReady == true,
    );

String _capabilityKey(String capability) =>
    capability.toLowerCase().replaceAll('_', '-');

String _knownStatus(String value, {required String fallback}) {
  final String normalized = value.trim();
  return normalized.isEmpty ? fallback : normalized;
}

String _runtimeStatusLabel(String value) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    return 'UNKNOWN（已阻断）';
  }
  return switch (normalized) {
    'READY' || 'VENDOR_BLOCKED' => normalized,
    _ => '$normalized（已阻断）',
  };
}
