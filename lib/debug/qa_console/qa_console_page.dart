import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

const String _gitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: 'unknown',
);
const String _packageVersion = String.fromEnvironment(
  'PACKAGE_VERSION',
  defaultValue: '0.5.0+5',
);
const String _initialNetwork = String.fromEnvironment(
  'QA_NETWORK_SCENARIO',
  defaultValue: 'normal',
);

class QaConsolePage extends StatefulWidget {
  const QaConsolePage({
    required this.dependencies,
    required this.onResetMockData,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onResetMockData;

  @override
  State<QaConsolePage> createState() => _QaConsolePageState();
}

class _QaConsolePageState extends State<QaConsolePage> {
  final TextEditingController _searchController = TextEditingController();
  ProductArea? _area;
  QaRole _role = QaRole.registeredUser;
  QaPageState _state = QaPageState.normal;
  QaMockScenario _mockScenario = QaMockScenario.defaultData;
  late QaNetworkScenario _network;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _network = QaNetworkScenario.values.firstWhere(
      (QaNetworkScenario value) => value.label == _initialNetwork,
      orElse: () => QaNetworkScenario.normal,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<QaPageEntry> get _visibleEntries {
    final String query = _searchController.text.trim().toLowerCase();
    return qaPageCatalog
        .where((QaPageEntry entry) {
          final bool matchesArea = _area == null || entry.area == _area;
          final bool matchesQuery =
              query.isEmpty ||
              entry.id.toLowerCase().contains(query) ||
              entry.name.toLowerCase().contains(query) ||
              entry.widgetClass.toLowerCase().contains(query);
          return matchesArea && matchesQuery;
        })
        .toList(growable: false);
  }

  QaScenario get _scenario => QaScenario(
    role: _role,
    state: _state,
    mockScenario: _mockScenario,
    network: _network,
  );

  Future<void> _resetMockData() async {
    if (_resetting) {
      return;
    }
    setState(() => _resetting = true);
    try {
      await widget.onResetMockData();
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  void _open(QaPageEntry entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/qa/${entry.id}'),
        builder: (BuildContext context) => QaPageFrame(
          pageId: entry.id,
          scenario: _scenario,
          stateSupported: entry.requiredStates.contains(_state),
          child: entry.builder(widget.dependencies, _scenario),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final List<QaPageEntry> entries = _visibleEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('M2.4 QA Console'),
        actions: <Widget>[
          IconButton(
            tooltip: '重置 Mock 数据',
            onPressed: _resetting ? null : _resetMockData,
            icon: _resetting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          key: const ValueKey<String>('qa-console-directory'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            _EnvironmentCard(
              backendMode: widget.dependencies.environment.backendMode.name,
              gitCommit: _gitCommit,
              packageVersion: _packageVersion,
              media: media,
              network: _network.label,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey<String>('qa-page-search'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                labelText: '搜索 Page ID、名称或 Widget/Class',
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  FilterChip(
                    label: const Text('全部 69'),
                    selected: _area == null,
                    onSelected: (_) => setState(() => _area = null),
                  ),
                  const SizedBox(width: 8),
                  for (final ProductArea area
                      in ProductArea.values) ...<Widget>[
                    FilterChip(
                      label: Text(area.code),
                      selected: _area == area,
                      onSelected: (_) => setState(() => _area = area),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ScenarioControls(
              role: _role,
              state: _state,
              mockScenario: _mockScenario,
              network: _network,
              onRoleChanged: (QaRole value) => setState(() => _role = value),
              onStateChanged: (QaPageState value) =>
                  setState(() => _state = value),
              onMockChanged: (QaMockScenario value) =>
                  setState(() => _mockScenario = value),
              onNetworkChanged: (QaNetworkScenario value) =>
                  setState(() => _network = value),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Page ID 目录',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${entries.length} / 69'),
              ],
            ),
            const SizedBox(height: 8),
            for (final QaPageEntry entry in entries)
              _PageEntryCard(entry: entry, onOpen: () => _open(entry)),
          ],
        ),
      ),
    );
  }
}

class QaPageFrame extends StatelessWidget {
  const QaPageFrame({
    required this.pageId,
    required this.scenario,
    required this.stateSupported,
    required this.child,
    super.key,
  });

  final String pageId;
  final QaScenario scenario;
  final bool stateSupported;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: ValueKey<String>('qa-frame-$pageId'),
      children: <Widget>[
        child,
        Positioned(
          left: 10,
          top: 10,
          child: SafeArea(
            child: _ActiveScenarioBadge(
              pageId: pageId,
              scenario: scenario,
              stateSupported: stateSupported,
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 18,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'qa-directory-$pageId',
              tooltip: '一键回到 QA 目录',
              onPressed: () => Navigator.of(
                context,
              ).popUntil((Route<dynamic> route) => route.isFirst),
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveScenarioBadge extends StatelessWidget {
  const _ActiveScenarioBadge({
    required this.pageId,
    required this.scenario,
    required this.stateSupported,
  });

  final String pageId;
  final QaScenario scenario;
  final bool stateSupported;

  @override
  Widget build(BuildContext context) {
    final String support = stateSupported ? '适用' : '本页不适用';
    final String label =
        '$pageId · ${scenario.role.label} · ${scenario.state.label} ($support) '
        '· ${scenario.mockScenario.label} · ${scenario.network.label}';
    return Semantics(
      container: true,
      label: 'QA 当前场景：$label',
      child: Material(
        key: ValueKey<String>('qa-active-scenario-$pageId'),
        color: stateSupported
            ? AppColors.surface.withValues(alpha: 0.94)
            : AppColors.warning.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.backendMode,
    required this.gitCommit,
    required this.packageVersion,
    required this.media,
    required this.network,
  });

  final String backendMode;
  final String gitCommit;
  final String packageVersion;
  final MediaQueryData media;
  final String network;

  @override
  Widget build(BuildContext context) {
    final String commit = gitCommit.length > 12
        ? gitCommit.substring(0, 12)
        : gitCommit;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: <Widget>[
          _Datum(label: 'BackendMode', value: backendMode),
          _Datum(label: 'Git', value: commit),
          _Datum(label: 'Version', value: packageVersion),
          _Datum(
            label: 'MediaQuery',
            value:
                '${media.size.width.toStringAsFixed(0)}×${media.size.height.toStringAsFixed(0)}',
          ),
          _Datum(
            label: 'DPR',
            value: media.devicePixelRatio.toStringAsFixed(2),
          ),
          _Datum(
            label: 'Font',
            value: '${media.textScaler.scale(1).toStringAsFixed(2)}×',
          ),
          _Datum(label: 'Network', value: network),
        ],
      ),
    );
  }
}

class _Datum extends StatelessWidget {
  const _Datum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text('$label: $value', style: Theme.of(context).textTheme.bodySmall);
  }
}

class _ScenarioControls extends StatelessWidget {
  const _ScenarioControls({
    required this.role,
    required this.state,
    required this.mockScenario,
    required this.network,
    required this.onRoleChanged,
    required this.onStateChanged,
    required this.onMockChanged,
    required this.onNetworkChanged,
  });

  final QaRole role;
  final QaPageState state;
  final QaMockScenario mockScenario;
  final QaNetworkScenario network;
  final ValueChanged<QaRole> onRoleChanged;
  final ValueChanged<QaPageState> onStateChanged;
  final ValueChanged<QaMockScenario> onMockChanged;
  final ValueChanged<QaNetworkScenario> onNetworkChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        DropdownButtonFormField<QaRole>(
          value: role,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '当前角色'),
          items: <DropdownMenuItem<QaRole>>[
            for (final QaRole value in QaRole.values)
              DropdownMenuItem<QaRole>(value: value, child: Text(value.label)),
          ],
          onChanged: (QaRole? value) {
            if (value != null) {
              onRoleChanged(value);
            }
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<QaPageState>(
          value: state,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '当前必要状态'),
          items: <DropdownMenuItem<QaPageState>>[
            for (final QaPageState value in QaPageState.values)
              DropdownMenuItem<QaPageState>(
                value: value,
                child: Text(value.label),
              ),
          ],
          onChanged: (QaPageState? value) {
            if (value != null) {
              onStateChanged(value);
            }
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<QaMockScenario>(
                value: mockScenario,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mock 场景'),
                items: <DropdownMenuItem<QaMockScenario>>[
                  for (final QaMockScenario value in QaMockScenario.values)
                    DropdownMenuItem<QaMockScenario>(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                onChanged: (QaMockScenario? value) {
                  if (value != null) {
                    onMockChanged(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<QaNetworkScenario>(
                value: network,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '网络场景'),
                items: <DropdownMenuItem<QaNetworkScenario>>[
                  for (final QaNetworkScenario value
                      in QaNetworkScenario.values)
                    DropdownMenuItem<QaNetworkScenario>(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                onChanged: (QaNetworkScenario? value) {
                  if (value != null) {
                    onNetworkChanged(value);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PageEntryCard extends StatelessWidget {
  const _PageEntryCard({required this.entry, required this.onOpen});

  final QaPageEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey<String>('qa-entry-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceHigh,
          child: Text(entry.area.code),
        ),
        title: Text('${entry.id} · ${entry.name}'),
        subtitle: Text(entry.widgetClass),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('源码：${entry.sourcePath}'),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('普通入口：${entry.userEntry}'),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '必要状态：${entry.requiredStates.map((QaPageState value) => value.label).join(', ')}',
            ),
          ),
          if (entry.vendorBoundary.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'VENDOR_BLOCKED：${entry.vendorBoundary}',
                style: const TextStyle(color: AppColors.warning),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: ValueKey<String>('qa-open-${entry.id}'),
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('直接打开真实页面'),
            ),
          ),
        ],
      ),
    );
  }
}
