import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/component.dart';
import '../../models/db_modeling.dart';
import '../../models/problem.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';

class DbModelingPanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final bool embedded;

  const DbModelingPanel({
    super.key,
    this.onClose,
    this.embedded = false,
  });

  @override
  ConsumerState<DbModelingPanel> createState() => _DbModelingPanelState();
}

class _DbModelingPanelState extends ConsumerState<DbModelingPanel> {
  static const String _globalKey = '__global__';

  late double _readWriteRatio;
  late double _dataSizeGb;
  late ConsistencyNeed _consistency;
  late LatencySensitivity _latencySensitivity;
  late bool _needsTransactions;
  late bool _flexibleSchema;
  late Set<QueryPattern> _patterns;
  final Map<String, _DbModelingState> _stateByKey = {};
  String _activeKey = _globalKey;
  SystemComponent? _activeComponent;
  ProviderSubscription<String?>? _selectionSub;

  @override
  void initState() {
    super.initState();
    _loadStateForSelection(ref.read(canvasProvider).selectedComponentId);
    _selectionSub = ref.listenManual<String?>(
      canvasProvider.select((s) => s.selectedComponentId),
      (previous, next) => _loadStateForSelection(next),
    );
  }

  @override
  void dispose() {
    _selectionSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeComponent = _activeComponent;
    final workload = DbWorkload(
      readWriteRatio: _readWriteRatio,
      patterns: _patterns,
      consistency: _consistency,
      latencySensitivity: _latencySensitivity,
      needsTransactions: _needsTransactions,
      flexibleSchema: _flexibleSchema,
      dataSizeGb: _dataSizeGb,
    );

    final recommendations = DbModeling.recommend(workload);
    final comparison = DbModeling.compare(workload);
    final hybrid = DbModeling.buildHybridStack(workload);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        _sectionTitle('Workload Profile'),
        if (activeComponent != null) _activeTargetRow(activeComponent),
        _ratioSlider(),
        _dataSizeSlider(),
        _toggleRow(),
        _dropdownRow(),
        const SizedBox(height: 10),
        _sectionTitle('Query Patterns'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: QueryPattern.values.map((pattern) {
            final selected = _patterns.contains(pattern);
            return FilterChip(
              selected: selected,
              label: Text(pattern.label, style: const TextStyle(fontSize: 10)),
              onSelected: (value) {
                setState(() {
                  if (value) {
                    _patterns = {..._patterns, pattern};
                  } else {
                    _patterns = {..._patterns}..remove(pattern);
                  }
                  _storeState();
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Decision Tree'),
        ...recommendations.take(3).map((rec) => _recommendationRow(rec)),
        if (activeComponent != null) ...[
          const SizedBox(height: 10),
          _sectionTitle('Selected DB Config'),
          _configSnapshot(activeComponent),
        ],
        const SizedBox(height: 12),
        _sectionTitle('Comparative Modeling'),
        _comparisonHeader(),
        ...comparison.map(_comparisonRow),
        const SizedBox(height: 12),
        _sectionTitle('Hybrid Architecture'),
        _hybridSummary(hybrid),
      ],
    );

    return Container(
      width: widget.embedded ? null : 320,
      margin: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.embedded ? AppTheme.surfaceLight : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: widget.embedded
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: content,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: content,
            ),
    );
  }

  void _loadStateForSelection(String? selectedId) {
    final problem = ref.read(currentProblemProvider);
    final canvas = ref.read(canvasProvider);
    final selectedComponent = selectedId != null ? canvas.getComponent(selectedId) : null;
    final isDbSelected = selectedComponent != null && _isDbComponent(selectedComponent.type);
    final key = isDbSelected ? selectedComponent!.id : _globalKey;

    final cached = _stateByKey[key];
    final state = cached ?? _defaultState(problem, selectedComponent);

    setState(() {
      _activeKey = key;
      _activeComponent = isDbSelected ? selectedComponent : null;
      _applyState(state);
      _stateByKey[_activeKey] = state;
    });
  }

  _DbModelingState _defaultState(Problem problem, SystemComponent? component) {
    final constraints = problem.constraints;
    final ratio = _defaultRatio(constraints, component);
    final patterns = _defaultPatterns(constraints, component, ratio);
    return _DbModelingState(
      readWriteRatio: ratio,
      dataSizeGb: constraints.dataStorageGb.toDouble(),
      consistency: _defaultConsistency(constraints, component),
      latencySensitivity: _defaultLatency(constraints, component),
      needsTransactions: _defaultTransactions(component),
      flexibleSchema: _defaultFlexibleSchema(component),
      patterns: patterns,
    );
  }

  void _applyState(_DbModelingState state) {
    _readWriteRatio = state.readWriteRatio;
    _dataSizeGb = state.dataSizeGb;
    _consistency = state.consistency;
    _latencySensitivity = state.latencySensitivity;
    _needsTransactions = state.needsTransactions;
    _flexibleSchema = state.flexibleSchema;
    _patterns = {...state.patterns};
  }

  void _storeState() {
    _stateByKey[_activeKey] = _DbModelingState(
      readWriteRatio: _readWriteRatio,
      dataSizeGb: _dataSizeGb,
      consistency: _consistency,
      latencySensitivity: _latencySensitivity,
      needsTransactions: _needsTransactions,
      flexibleSchema: _flexibleSchema,
      patterns: _patterns,
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Icon(Icons.storage_rounded, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'DB Modeling Lab',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (!widget.embedded && widget.onClose != null)
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
      ],
    );
  }

  Widget _activeTargetRow(SystemComponent component) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(component.type.icon, size: 14, color: component.type.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Target: ${component.customName ?? component.type.displayName}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text('per DB', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _ratioSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Read/Write Ratio: ${_readWriteRatio.toStringAsFixed(0)}:1',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        Slider(
          value: _readWriteRatio.clamp(1, 200),
          min: 1,
          max: 200,
          divisions: 199,
          onChanged: (value) => setState(() {
            _readWriteRatio = value;
            _storeState();
          }),
        ),
      ],
    );
  }

  Widget _dataSizeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Size: ${_formatSize(_dataSizeGb)}',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        Slider(
          value: _dataSizeGb.clamp(10, 5000),
          min: 10,
          max: 5000,
          divisions: 100,
          onChanged: (value) => setState(() {
            _dataSizeGb = value;
            _storeState();
          }),
        ),
      ],
    );
  }

  Widget _toggleRow() {
    return Row(
      children: [
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Transactions', style: TextStyle(fontSize: 11)),
            value: _needsTransactions,
            onChanged: (value) => setState(() {
              _needsTransactions = value;
              _storeState();
            }),
          ),
        ),
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Flexible Schema', style: TextStyle(fontSize: 11)),
            value: _flexibleSchema,
            onChanged: (value) => setState(() {
              _flexibleSchema = value;
              _storeState();
            }),
          ),
        ),
      ],
    );
  }

  Widget _dropdownRow() {
    return Row(
      children: [
        Expanded(
          child: _dropdown<ConsistencyNeed>(
            label: 'Consistency',
            value: _consistency,
            values: ConsistencyNeed.values,
            labelBuilder: (v) => v.label,
            onChanged: (value) => setState(() {
              _consistency = value!;
              _storeState();
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dropdown<LatencySensitivity>(
            label: 'Latency',
            value: _latencySensitivity,
            values: LatencySensitivity.values,
            labelBuilder: (v) => v.label,
            onChanged: (value) => setState(() {
              _latencySensitivity = value!;
              _storeState();
            }),
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        DropdownButtonFormField<T>(
          value: value,
          items: values
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(labelBuilder(item), style: const TextStyle(fontSize: 11)),
                  ))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
      ],
    );
  }

  Widget _recommendationRow(DbRecommendation recommendation) {
    final score = (recommendation.score * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                recommendation.family.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$score%',
                style: TextStyle(
                  color: score >= 75
                      ? AppTheme.success
                      : score >= 55
                          ? AppTheme.warning
                          : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: recommendation.reasons
                .map((reason) => Chip(
                      label: Text(reason, style: const TextStyle(fontSize: 9)),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _comparisonHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: const [
          Expanded(child: Text('DB Type', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
          SizedBox(width: 52, child: Text('Fit', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
          SizedBox(width: 64, child: Text('Latency', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
          SizedBox(width: 64, child: Text('RPS', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
        ],
      ),
    );
  }

  Widget _comparisonRow(DbComparisonRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.family.label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${row.fitScore.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '${row.latencyMs.toStringAsFixed(0)}ms',
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              _formatNumber(row.throughputRps),
              style: TextStyle(
                fontSize: 10,
                color: row.consistencyRisk == 'High' ? AppTheme.warning : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hybridSummary(DbHybridStack hybrid) {
    final secondary = hybrid.secondary.isEmpty
        ? 'None'
        : hybrid.secondary.map((f) => f.label).join(', ');
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Primary: ${hybrid.primary.label}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Secondary: $secondary',
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          ...hybrid.reasons.map((reason) => Text(
                '• $reason',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              )),
        ],
      ),
    );
  }

  Widget _configSnapshot(SystemComponent component) {
    final config = component.config;
    final replication = config.replication
        ? 'RF ${config.replicationFactor} · ${config.replicationType.name}'
        : 'Disabled';
    final quorum = '${config.quorumRead ?? 1}/${config.quorumWrite ?? 1}';
    final regionCount = config.regions.isEmpty ? 1 : config.regions.length;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Replication: $replication', style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 4),
          Text('Quorum (R/W): $quorum', style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 4),
          Text('Regions: $regionCount', style: const TextStyle(fontSize: 10)),
          if (config.sharding) ...[
            const SizedBox(height: 4),
            Text('Shards: ${config.partitionCount}', style: const TextStyle(fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppTheme.textMuted,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  String _formatSize(double value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}TB';
    return '${value.toStringAsFixed(0)}GB';
  }

  ConsistencyNeed _defaultConsistency(
    ProblemConstraints constraints,
    SystemComponent? component,
  ) {
    if (component == null) {
      if (constraints.availabilityTarget >= 0.9999) return ConsistencyNeed.strong;
      if (constraints.readWriteRatio > 50) return ConsistencyNeed.eventual;
      return ConsistencyNeed.causal;
    }

    final config = component.config;
    if (config.quorumRead != null && config.quorumRead! > 1) return ConsistencyNeed.strong;
    if (config.quorumWrite != null && config.quorumWrite! > 1) return ConsistencyNeed.strong;
    if (config.replicationType == ReplicationType.synchronous) return ConsistencyNeed.strong;
    if (config.replicationType == ReplicationType.streaming) return ConsistencyNeed.causal;
    if (config.replicationType == ReplicationType.asynchronous) return ConsistencyNeed.eventual;

    return switch (component.type) {
      ComponentType.graphDb => ConsistencyNeed.causal,
      ComponentType.keyValueStore => ConsistencyNeed.eventual,
      ComponentType.timeSeriesDb => ConsistencyNeed.eventual,
      ComponentType.searchIndex => ConsistencyNeed.eventual,
      ComponentType.vectorDb => ConsistencyNeed.eventual,
      ComponentType.dataWarehouse => ConsistencyNeed.strong,
      _ => ConsistencyNeed.causal,
    };
  }

  LatencySensitivity _defaultLatency(
    ProblemConstraints constraints,
    SystemComponent? component,
  ) {
    if (component == null) {
      if (constraints.latencySlaMsP95 <= 100) return LatencySensitivity.strict;
      if (constraints.latencySlaMsP95 <= 250) return LatencySensitivity.balanced;
      return LatencySensitivity.relaxed;
    }

    return switch (component.type) {
      ComponentType.dataWarehouse => LatencySensitivity.relaxed,
      ComponentType.dataLake => LatencySensitivity.relaxed,
      ComponentType.searchIndex => LatencySensitivity.strict,
      ComponentType.timeSeriesDb => LatencySensitivity.balanced,
      ComponentType.vectorDb => LatencySensitivity.strict,
      _ => LatencySensitivity.balanced,
    };
  }

  double _defaultRatio(ProblemConstraints constraints, SystemComponent? component) {
    if (component == null) return constraints.readWriteRatio;
    return switch (component.type) {
      ComponentType.timeSeriesDb => 2,
      ComponentType.dataWarehouse => 60,
      ComponentType.dataLake => 50,
      ComponentType.searchIndex => 40,
      ComponentType.vectorDb => 25,
      ComponentType.graphDb => 6,
      _ => constraints.readWriteRatio,
    };
  }

  Set<QueryPattern> _defaultPatterns(
    ProblemConstraints constraints,
    SystemComponent? component,
    double ratio,
  ) {
    final patterns = <QueryPattern>{
      QueryPattern.pointReads,
      if (ratio >= 10) QueryPattern.rangeScans,
      if (constraints.dau > 50000000) QueryPattern.analytics,
    };

    if (component != null) {
      switch (component.type) {
        case ComponentType.graphDb:
          patterns.add(QueryPattern.graphTraversal);
          break;
        case ComponentType.timeSeriesDb:
          patterns.add(QueryPattern.timeSeries);
          break;
        case ComponentType.searchIndex:
          patterns.add(QueryPattern.fullText);
          break;
        case ComponentType.vectorDb:
          patterns.add(QueryPattern.vectorSearch);
          break;
        case ComponentType.dataWarehouse:
        case ComponentType.dataLake:
          patterns.add(QueryPattern.analytics);
          break;
        default:
          break;
      }
    }

    return patterns;
  }

  bool _defaultTransactions(SystemComponent? component) {
    if (component == null) return true;
    return switch (component.type) {
      ComponentType.database => true,
      ComponentType.graphDb => true,
      ComponentType.keyValueStore => false,
      ComponentType.timeSeriesDb => false,
      ComponentType.searchIndex => false,
      ComponentType.vectorDb => false,
      ComponentType.dataWarehouse => true,
      ComponentType.dataLake => false,
      _ => true,
    };
  }

  bool _defaultFlexibleSchema(SystemComponent? component) {
    if (component == null) return false;
    return switch (component.type) {
      ComponentType.keyValueStore => true,
      ComponentType.timeSeriesDb => true,
      ComponentType.searchIndex => true,
      ComponentType.vectorDb => true,
      ComponentType.dataLake => true,
      _ => false,
    };
  }

  bool _isDbComponent(ComponentType type) {
    return switch (type) {
      ComponentType.database ||
      ComponentType.keyValueStore ||
      ComponentType.timeSeriesDb ||
      ComponentType.graphDb ||
      ComponentType.vectorDb ||
      ComponentType.searchIndex ||
      ComponentType.dataWarehouse ||
      ComponentType.dataLake => true,
      _ => false,
    };
  }
}

class _DbModelingState {
  final double readWriteRatio;
  final double dataSizeGb;
  final ConsistencyNeed consistency;
  final LatencySensitivity latencySensitivity;
  final bool needsTransactions;
  final bool flexibleSchema;
  final Set<QueryPattern> patterns;

  const _DbModelingState({
    required this.readWriteRatio,
    required this.dataSizeGb,
    required this.consistency,
    required this.latencySensitivity,
    required this.needsTransactions,
    required this.flexibleSchema,
    required this.patterns,
  });
}
