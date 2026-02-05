import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/component.dart';
import '../../models/custom_component.dart';
import '../../models/metrics.dart';
import '../../providers/custom_component_provider.dart';
import '../../theme/app_theme.dart';
import '../../data/excalidraw_definitions.dart';
import 'excalidraw_painter.dart';
import '../../providers/game_provider.dart';
import 'failure_animations.dart';

/// Minimal component node for the canvas
class ComponentNode extends ConsumerWidget {
  final SystemComponent component;
  final bool isSelected;
  final bool isConnecting;
  final bool isValidTarget;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onDragEnd;
  final bool isEditing;
  final Function(String)? onTextChange;
  final VoidCallback? onEditDone;
  final VoidCallback? onLabelTap;
  final VoidCallback? onLongPress;
  final Function(Offset)? onDragUpdate;

  const ComponentNode({
    super.key,
    required this.component,
    this.isSelected = false,
    this.isConnecting = false,
    this.isValidTarget = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onDragUpdate,
    this.onDragEnd,
    this.isEditing = false,
    this.onTextChange,
    this.onEditDone,
    this.onLabelTap,
  });

  int _configSignature(ComponentConfig config) {
    return Object.hashAll([
      config.instances,
      config.capacity,
      config.autoScale,
      config.minInstances,
      config.maxInstances,
      config.algorithm ?? '',
      config.cacheTtlSeconds,
      config.replication,
      config.replicationFactor,
      config.replicationStrategy ?? '',
      config.sharding,
      config.shardingStrategy ?? '',
      config.partitionCount,
      config.consistentHashing,
      config.regions.join(','),
      config.rateLimiting,
      config.rateLimitRps ?? 0,
      config.circuitBreaker,
      config.retries,
      config.dlq,
      config.quorumRead ?? 0,
      config.quorumWrite ?? 0,
      config.displayMode.name,
      config.replicationType.name,
      config.showSchema,
      config.dbSchema?.hashCode ?? 0,
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // OPTIMIZATION: Watch specific metrics for this component only
    final ephemeralMetrics = ref.watch(simulationMetricsProvider.select((map) => map[component.id]));
    final metrics = ephemeralMetrics ?? component.metrics;
    
    // Watch Cyberpunk Mode & Error Visibility
    final isCyberpunk = ref.watch(canvasProvider.select((s) => s.isCyberpunkMode));
    final showErrorsFlag = ref.watch(canvasProvider.select((s) => s.showErrors));


    final color = component.type.color;
    final isActive = metrics.currentRps > 0;
    final isSketchy = component.type.isSketchy;
    final failures = ref.watch(simulationProvider.select((s) => s.visibleFailures));
    final componentFailures = failures.where((f) => f.componentId == component.id).toList();
    final primaryFailure = _pickPrimaryFailure(componentFailures);
    final componentsList = ref.watch(canvasProvider.select((s) => s.components));
    final componentNameById = <String, String>{
      for (final c in componentsList) c.id: c.customName ?? c.type.displayName,
    };
    String? cascadeUpstream;
    if (primaryFailure != null && primaryFailure.type == FailureType.cascadingFailure) {
      final upstreamIds = primaryFailure.affectedComponents
          .where((id) => id != component.id)
          .toList();
      if (upstreamIds.isNotEmpty) {
        cascadeUpstream = upstreamIds
            .map((id) => componentNameById[id] ?? 'Upstream')
            .join(', ');
      }
    }

    final effectiveInstances = math.max(
      1,
      metrics.readyInstances + (metrics.coldStartingInstances * 0.5).round(),
    );
    final capacity = component.config.capacity * effectiveInstances;
    final loadRatio = capacity > 0 ? metrics.currentRps / capacity : 0.0;
    final loadThresholds = _loadThresholds(component.type);
    final sustainedHighLoad = metrics.highLoadSeconds >= 3.0;
    final glowByLoad = sustainedHighLoad && loadRatio >= 0.8;
    final isDesignTimeFailure =
        primaryFailure != null && _isDesignTimeFailure(primaryFailure.type);
    final hasRuntimeFailure =
        primaryFailure != null && !isDesignTimeFailure && primaryFailure.severity > 0.6;
    
    // Determine visual failure states
    final hasTraffic = metrics.currentRps > 0;
    final connectionExhaustion = metrics.connectionPoolUtilization > 0.9;
    final hasError = (hasTraffic &&
            (metrics.errorRate > 0.05 ||
                metrics.isCircuitOpen ||
                metrics.isThrottled)) ||
        hasRuntimeFailure;
    final isOverloaded = hasTraffic &&
        ((loadRatio > loadThresholds.overload && sustainedHighLoad) ||
            connectionExhaustion);
    final isScaling = metrics.isScaling;
    final isSlow = hasTraffic &&
        (metrics.isSlow ||
            metrics.p95LatencyMs > 1500 ||
            (primaryFailure != null && _isLatencyFailure(primaryFailure.type)));
    final showDetailed = component.config.displayMode == ComponentDisplayMode.detailed;
    final showPressureLabel = !showDetailed &&
        _shouldShowPressureLabel(
          isActive: isActive,
          metrics: metrics,
          loadRatio: loadRatio,
          thresholds: loadThresholds,
          componentFailures: componentFailures,
        );

    // Text components are transparent and just text

    Widget child = AnimatedContainer(
      // ... (keep decoration logic same)
      duration: const Duration(milliseconds: 150),
      width: component.size.width,
      height: component.size.height,
      decoration: BoxDecoration(
        color: (isSketchy && (component.type == ComponentType.rectangle || 
                             component.type == ComponentType.circle || 
                             component.type == ComponentType.diamond ||
                             component.type == ComponentType.arrow || 
                             component.type == ComponentType.line))
            ? Colors.transparent
            : null,
        // ... (keep rest of decoration)
        gradient: (isSketchy && (component.type == ComponentType.rectangle || 
                                component.type == ComponentType.circle || 
                                component.type == ComponentType.diamond || 
                                component.type == ComponentType.arrow || 
                                component.type == ComponentType.line))
            ? null
            : (hasError || isSlow || isOverloaded)
                ? RadialGradient(
                    colors: [
                      (hasError ? AppTheme.error : isOverloaded ? Colors.orange : Colors.amber)
                          .withValues(alpha: 0.25),
                      GetStatusColor(hasError, isOverloaded, isSlow).withValues(alpha: 0.05),
                    ],
                    radius: 0.8,
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isSelected ? AppTheme.surfaceLight : AppTheme.surfaceLight.withValues(alpha: 0.9),
                      isSelected ? AppTheme.surface : AppTheme.surface.withValues(alpha: 0.7),
                    ],
                  ),
        boxShadow: (isSelected ||
                    hasError ||
                    isSlow ||
                    isOverloaded ||
                    glowByLoad ||
                    (!isSketchy && component.type != ComponentType.text))
            ? [
                BoxShadow(
                  color: hasError
                      ? Colors.red.withValues(alpha: 0.4)
                      : isSlow
                          ? Colors.amber.withValues(alpha: 0.3)
                          : (isOverloaded || glowByLoad)
                              ? Colors.orange.withValues(alpha: 0.3)
                              : (isSelected)
                                  ? color.withValues(alpha: isSelected ? 0.3 : 0.15)
                                  : (isCyberpunk
                                      ? color.withValues(alpha: 0.2) // Cyberpunk glow
                                      : Colors.black.withValues(alpha: 0.2)),
                  blurRadius: hasError || isSlow || isOverloaded || glowByLoad
                      ? 16
                      : (isSelected ? 12 : (isCyberpunk ? 8 : 3)),
                  spreadRadius: hasError || isSlow || isOverloaded || glowByLoad
                      ? 4
                      : (isSelected ? 1 : 0),
                  offset: (hasError || isSlow || isSelected) ? Offset.zero : const Offset(0, 2),
                ),
              ] 
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (hasError || isSlow || isOverloaded)
              ? Colors.transparent // Hide boundary when glowing
              : isSelected
                  ? AppTheme.primary
                  : (isSketchy && (component.type == ComponentType.rectangle || 
                                 component.type == ComponentType.circle || 
                                 component.type == ComponentType.diamond ||
                                 component.type == ComponentType.arrow || 
                                 component.type == ComponentType.line))
                      ? AppTheme.border.withValues(alpha: 0.4)
                      : (isConnecting
                          ? AppTheme.secondary.withValues(alpha: 0.5)
                          : (isCyberpunk ? color.withValues(alpha: 0.5) : Colors.transparent)),
          width: hasError || isSlow || isOverloaded ? 0 : (isSelected ? 2.5 : 1),
        ),
      ),
      child: isSketchy 
          ? _buildSketchyContent()
          : _buildStandardContent(
              color,
              isActive,
              metrics,
              hasError,
              isSlow,
              isOverloaded,
              isCyberpunk,
              showErrorsFlag,
              context,
              ref,
              componentFailures,
              primaryFailure,
              loadRatio,
              loadThresholds,
              cascadeUpstream,
              showPressureLabel,
            ),
    );
    
    // Shaking animation - always show when errors exist
    if (hasError || isOverloaded || isSlow) {
      child = ShakingWrapper(child: child);
    }
    
    if (isScaling) {
      child = ScalingPulseWrapper(child: child);
    }
    
    if (!isSketchy && component.type != ComponentType.text) {
      final label = component.customName ?? component.type.displayName;
      final canInlineEdit = onTextChange != null && onEditDone != null;
      final labelGap = showPressureLabel ? 28.0 : 4.0;
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          SizedBox(height: labelGap),
          GestureDetector(
            onTap: (!isEditing && canInlineEdit) ? onLabelTap : null,
            behavior: HitTestBehavior.translucent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.border.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: (isEditing && canInlineEdit)
                  ? _InlineTextEditor(
                      initialText: label,
                      onChange: onTextChange!,
                      onDone: onEditDone!,
                      isCentered: true,
                      maxWidth: math.max(80.0, component.size.width - 20),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ],
      );
    }

    return child;
  }

  // ... (keep _buildTextContent)

  Widget _buildStandardContent(
    Color color, 
    bool isActive,
    ComponentMetrics metrics,
    bool hasError,
    bool isSlow,
    bool isOverloaded,
    bool isCyberpunk,
    bool showErrorsFlag, // Flag to show/hide error indicators
    BuildContext context,
    WidgetRef ref,
    List<FailureEvent> componentFailures,
    FailureEvent? primaryFailure,
    double loadRatio,
    _LoadThresholds loadThresholds,
    String? cascadeUpstream,
    bool showPressureLabel,
  ) {
      final config = component.config;
      final whyTooltip = _buildWhyTooltip(
        metrics: metrics,
        primaryFailure: primaryFailure,
        loadRatio: loadRatio,
        thresholds: loadThresholds,
        cascadeUpstream: cascadeUpstream,
      );
      
      // Determine if we show detailed or standard internal architecture
      final showDetailed = config.displayMode == ComponentDisplayMode.detailed;
      final showInternals = config.sharding || config.replication;
      final configHash = _configSignature(config);

      if (showDetailed) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: _buildConfigPulseOverlay(configHash, color),
            ),
            _buildDetailedView(config, color, isActive, isCyberpunk, context, ref),
          ],
        );
      }

      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: _buildConfigPulseOverlay(configHash, color)),

          // Content
          if (showInternals)
            _buildInternalArchitecture(config, color, isActive, isCyberpunk)
          else
            _buildSimpleIcon(color, isActive),
          
          // ... (keep load bar)
          if (isActive)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: _buildLoadBar(loadRatio, loadThresholds),
            ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack).fadeIn(duration: 200.ms),


          // Status emoji/icon - only if showErrors is enabled
          if (showErrorsFlag && (hasError || isSlow || isOverloaded || componentFailures.isNotEmpty))
            Positioned(
              top: -12,
              right: -12, // Moved to top-right
              child: Tooltip(
                message: whyTooltip,
                child: _buildStatusEmoji(hasError, isSlow, isOverloaded, primaryFailure),
              ),
            ),
            
          // ... (keep pressure label)
          if (showPressureLabel)
             Positioned(
               bottom: -24, // Moved outside bottom
               child: _buildPressureLabel(metrics, primaryFailure, loadRatio, loadThresholds, cascadeUpstream),
             ),
        ],
      );
  }

  Widget _buildSimpleIcon(Color color, bool isActive) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          component.type.icon,
          color: color,
          size: 24,
        ),
        // Schema View (Optional for simple view too)
        if (component.type == ComponentType.database && component.config.showSchema && component.config.dbSchema != null)
          _buildMiniSchema(),
      ],
    );
  }

  /// Build detailed PostgreSQL/Cluster style visualization
  Widget _buildDetailedView(ComponentConfig config, Color color, bool isActive, bool isCyberpunk, BuildContext context, WidgetRef ref) {
    return _GlassContainer(
      isCyberpunk: isCyberpunk,
      child: component.customComponentId != null && 
             ref.read(customComponentProvider.notifier).getById(component.customComponentId!) != null
          ? _buildCustomGraph(ref.read(customComponentProvider.notifier).getById(component.customComponentId!)!, color)
          : component.type == ComponentType.database
              ? _buildDatabaseDetailedView(config, color, isActive, isCyberpunk)
              : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            // Header (icon only)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: color.withOpacity(0.3))),
                    color: color.withOpacity(0.1),
                ),
                child: Row(
                    children: [
                        Icon(component.type.icon, size: 14, color: color),
                        const Spacer(),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                ),
            ),
            
            Expanded(
                child: SingleChildScrollView( 
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Column(
                        children: [
                            // SHARDS ROW
                            if (config.shardConfigs.isNotEmpty) ...[
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: config.shardConfigs.map((s) => _buildDetailNode(
                                        label: s.name,
                                        sublabel: s.keyRange,
                                        icon: Icons.pie_chart_outline,
                                        color: Colors.cyanAccent,
                                    )).toList(),
                                ),
                                _buildVerticalConnector(height: 12, color: color.withOpacity(0.3)),
                            ],
                            
                            // PRIMARY NODE
                            Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    border: Border.all(color: color.withOpacity(0.6), width: 1.5),
                                    borderRadius: BorderRadius.circular(6),
                                    color: color.withOpacity(0.05),
                                    boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8)],
                                ),
                                child: Column(
                                    children: [
                                        Text('PRIMARY NODE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                                        if (config.partitionConfigs.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            ...config.partitionConfigs.map((p) => Container(
                                                margin: const EdgeInsets.only(bottom: 4),
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.05),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                                                ),
                                                child: Row(
                                                    children: [
                                                        const Icon(Icons.table_chart, size: 10, color: Colors.white70),
                                                        const SizedBox(width: 4),
                                                        Expanded(child: Text(p.tableName, style: const TextStyle(fontSize: 9, color: Colors.white))),
                                                        Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                                                            child: Text('${p.partitions.length} partitions', style: const TextStyle(fontSize: 7, color: Colors.blueAccent)),
                                                        ),
                                                    ],
                                                ),
                                            )),
                                        ]
                                    ],
                                ),
                            ),

                            // REPLICAS ROW
                            if (config.replicationType != ReplicationType.none) ...[
                                _buildVerticalConnector(height: 12, color: color.withOpacity(0.3)),
                                Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('REPLICATION: ${config.replicationType.name.toUpperCase()}', 
                                        style: const TextStyle(fontSize: 7, color: Colors.white54, letterSpacing: 0.5)),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: List.generate(
                                        math.min(3, config.replicationFactor), 
                                        (i) => _buildDetailNode(
                                            label: 'Replica ${i+1}', 
                                            icon: Icons.copy, 
                                            color: Colors.greenAccent, 
                                        )
                                    ),
                                ),
                            ],
                        ],
                    ),
                ),
            ),
        ],
      )
    );
  }

  Widget _buildDatabaseDetailedView(
    ComponentConfig config,
    Color color,
    bool isActive,
    bool isCyberpunk,
  ) {
    final shardConfigs = config.shardConfigs;
    final hasShards = config.sharding || shardConfigs.isNotEmpty;
    final shardCount = shardConfigs.isNotEmpty
        ? shardConfigs.length
        : math.min(4, config.partitionCount);

    final replicationEnabled = config.replicationType != ReplicationType.none ||
        (config.replication && config.replicationFactor > 1);
    final replicaCount = replicationEnabled
        ? math.min(5, math.max(1, config.replicationFactor))
        : 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isCyberpunk ? 0.18 : 0.10),
            Colors.black.withValues(alpha: 0.15),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dbHeader(color),
          const SizedBox(height: 8),
          if (hasShards) ...[
            _sectionLabel('SHARDS', color),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: List.generate(shardCount, (index) {
                final shard = shardConfigs.isNotEmpty ? shardConfigs[index] : null;
                final label = shard?.name ?? 'Shard ${index + 1}';
                final range = shard?.keyRange ?? 'Range ${index + 1}';
                return _pillCard(
                  label: label,
                  sublabel: range,
                  icon: Icons.pie_chart_outline,
                  color: Colors.cyanAccent,
                );
              }),
            ),
            const SizedBox(height: 8),
            _thinDivider(color),
            const SizedBox(height: 8),
          ],
          _sectionLabel('PRIMARY', color),
          const SizedBox(height: 6),
          _primaryCard(config, color),
          if (replicationEnabled) ...[
            const SizedBox(height: 8),
            _thinDivider(color),
            const SizedBox(height: 8),
            _replicationBadge(config, color),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: List.generate(replicaCount, (index) {
                return _pillCard(
                  label: 'Replica ${index + 1}',
                  sublabel: null,
                  icon: Icons.copy,
                  color: Colors.greenAccent,
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dbHeader(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(component.type.icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: color.withValues(alpha: 0.8),
      ),
    );
  }

  Widget _thinDivider(Color color) {
    return Center(
      child: Container(
        width: 120,
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              color.withValues(alpha: 0.4),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryCard(ComponentConfig config, Color color) {
    final tables = config.partitionConfigs;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PRIMARY NODE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 6),
          if (tables.isEmpty)
            Text(
              'No partitions configured',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8, color: AppTheme.textMuted.withValues(alpha: 0.8)),
            )
          else
            ...tables.map((p) => _tableRow(p, color)),
        ],
      ),
    );
  }

  Widget _tableRow(PartitionConfig p, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.table_chart, size: 10, color: color.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              p.tableName,
              style: const TextStyle(fontSize: 9, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 0.5),
            ),
            child: Text(
              '${p.partitions.length} parts',
              style: const TextStyle(fontSize: 7, color: Colors.blueAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _replicationBadge(ComponentConfig config, Color color) {
    final label = switch (config.replicationType) {
      ReplicationType.synchronous => 'SYNCHRONOUS',
      ReplicationType.asynchronous => 'ASYNCHRONOUS',
      ReplicationType.streaming => 'STREAMING',
      _ => 'REPLICATION',
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 7,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  Widget _pillCard({
    required String label,
    String? sublabel,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sublabel != null)
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 6,
                color: color.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildDetailNode({required String label, String? sublabel, required IconData icon, required Color color}) {
     return Flexible( // Flex to avoid overflow
       child: Container(
           margin: const EdgeInsets.symmetric(horizontal: 2),
           padding: const EdgeInsets.all(4),
           constraints: const BoxConstraints(minWidth: 40),
           decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              border: Border.all(color: color.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(6),
           ),
           child: Column(
               children: [
                   Icon(icon, size: 12, color: color),
                   const SizedBox(height: 2),
                   Text(label, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                   if (sublabel != null) Text(sublabel, style: TextStyle(fontSize: 6, color: color.withOpacity(0.7)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
               ],
           ),
       ),
     );
  }

  Widget _buildVerticalConnector({required double height, required Color color}) {
      return Center(child: Container(width: 1, height: height, color: color));
  }

  Widget _buildCustomGraph(CustomComponentDefinition def, Color color) {
    if (def.internalNodes.isEmpty) return const SizedBox();

    // Find bounds
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    
    for (var n in def.internalNodes) {
      if (n.relativePosition.dx < minX) minX = n.relativePosition.dx;
      if (n.relativePosition.dy < minY) minY = n.relativePosition.dy;
      if (n.relativePosition.dx > maxX) maxX = n.relativePosition.dx;
      if (n.relativePosition.dy > maxY) maxY = n.relativePosition.dy;
    }
    
    // Normalize and add padding
    final width = maxX - minX + 80;
    final height = maxY - minY + 60;
    
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
           width: width,
           height: height,
           child: Stack(
             children: [
               // Connections relative to minX/minY
               ...def.internalConnections.map((c) {
                  final src = def.internalNodes.firstWhere((n) => n.id == c.sourceNodeId, orElse: () => def.internalNodes.first);
                  final dst = def.internalNodes.firstWhere((n) => n.id == c.targetNodeId, orElse: () => def.internalNodes.first);
                  
                  return Positioned.fill(
                     child: CustomPaint(
                       painter: _SimpleLinePainter(
                          start: src.relativePosition - Offset(minX, minY) + const Offset(40, 30),
                          end: dst.relativePosition - Offset(minX, minY) + const Offset(40, 30),
                          color: color.withOpacity(0.5)
                       )
                     )
                  );
               }),
               // Nodes
               ...def.internalNodes.map((n) {
                  return Positioned(
                    left: n.relativePosition.dx - minX,
                    top: n.relativePosition.dy - minY,
                    child: Container(
                       width: 80, height: 60,
                       decoration: BoxDecoration(
                         color: n.type == ComponentType.shardNode ? Colors.orange.withOpacity(0.2) : 
                                n.type == ComponentType.replicaNode ? Colors.green.withOpacity(0.2) : 
                                n.type == ComponentType.inputNode ? Colors.cyanAccent.withOpacity(0.2) :
                                n.type == ComponentType.outputNode ? Colors.pinkAccent.withOpacity(0.2) :
                                color.withOpacity(0.2),
                         border: Border.all(color: color.withOpacity(0.5)),
                         borderRadius: BorderRadius.circular(6)
                       ),
                       child: Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                           Icon(n.type.icon, size: 16, color: color),
                           const SizedBox(height: 2),
                           Text(n.label, style: TextStyle(fontSize: 9, color: color), overflow: TextOverflow.ellipsis),
                         ],
                       )
                    )
                  );
               })
             ]
           )
        ),
      ),
    );
  }

  Widget _buildInternalArchitecture(ComponentConfig config, Color color, bool isActive, bool isCyberpunk) {
    // Wrap in Glass Container
    return _GlassContainer(
      isCyberpunk: isCyberpunk,
      child: Builder(
        builder: (context) {
          // Priority-based exclusive rendering to avoid overlap
          if (config.sharding) {
            return _buildShardedView(config, color);
          } else if (config.replication) {
            return _buildReplicatedView(config, color);
          }
          // Removed cluster view - visual nodes represent instances
          return const SizedBox.shrink();
        }
      ),
    );
  }

  Widget _buildShardedView(ComponentConfig config, Color color) {
    final partitionCount = math.min(config.partitionCount, 4);
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Router / Balancer
        Icon(Icons.alt_route, size: 12, color: color),
        
        // Distribution Lines
        SizedBox(
          height: 8,
          width: 40 + (partitionCount * 10.0),
          child: CustomPaint(
            painter: _DistributionLinePainter(
              color: color.withValues(alpha: 0.5), 
              count: partitionCount
            ),
          ),
        ),

        // Grid of shards
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(partitionCount, (index) {
                return Column(
                  children: [
                    // Incoming Data Packet (Animated)
                    Container(
                      width: 2, height: 4, 
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
                    ).animate(onPlay: (c) => c.repeat())
                     .slideY(begin: -2, end: 0, duration: (800 + index * 100).ms, curve: Curves.easeIn)
                     .fade(begin: 0, end: 1),

                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: Border.all(color: color.withValues(alpha: 0.6)),
                        borderRadius: BorderRadius.circular(4),
                        color: color.withValues(alpha: 0.1),
                      ),
                      child: Column(
                        children: [
                          Icon(component.type.icon, size: 10, color: color),
                          const SizedBox(height: 1),
                          Text('S${index + 1}', style: const TextStyle(fontSize: 5, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReplicatedView(ComponentConfig config, Color color) {
    // Explicit Leader -> Follower Wiring
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LEADER
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            color: color.withValues(alpha: 0.2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6)]
          ),
          child: Icon(component.type.icon, size: 16, color: color),
        ),
        
        // Connection Lines (Leader to Followers)
        SizedBox(
          height: 16,
          width: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
               // Central Down Line
               Container(width: 1, height: 16, color: color.withValues(alpha: 0.5)),
               // Horizontal Bracket
               Positioned(
                 bottom: 0,
                 child: Container(width: 40, height: 1, color: color.withValues(alpha: 0.5)),
               ),
               // Animated Packet - flowing down
                Container(width: 3, height: 3, decoration: BoxDecoration(color: color, shape: BoxShape.circle))
                  .animate(onPlay: (c) => c.repeat())
                  .slideY(begin: -2.5, end: 2.5, duration: 1000.ms),
            ],
          ),
        ),

        // FOLLOWERS
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             // Follower 1
             _buildFollowerNode(color),
             const SizedBox(width: 12),
             // Follower 2 (or more stacked)
             _buildFollowerNode(color, count: config.replicationFactor > 2 ? config.replicationFactor - 1 : 1),
          ],
        ),
      ],
    );
  }

  Widget _buildFollowerNode(Color color, {int count = 1}) {
    return Column(
      children: [
        // Connecting line from bracket
        Container(width: 1, height: 4, color: color.withValues(alpha: 0.5)),
        
        // Node
        Stack(
          clipBehavior: Clip.none,
          children: [
             if (count > 1) 
               Positioned(
                 left: 2, top: -2,
                 child: Icon(component.type.icon, size: 12, color: color.withValues(alpha: 0.3)),
               ),
             iconContainer(color, 12),
          ],
        ),
        const SizedBox(height: 2),
        const Text('Sync', style: TextStyle(fontSize: 4, color: AppTheme.textMuted)),
      ],
    );
  }
  
  Widget iconContainer(Color color, double size) {
     return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.6)),
            color: color.withValues(alpha: 0.05),
          ),
          child: Icon(component.type.icon, size: size, color: color),
        );
  }

  Widget _buildClusterView(ComponentConfig config, Color color) {
    // Grid of instances
    final displayCount = math.min(config.instances, 4);
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: List.generate(displayCount, (index) {
            return Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(component.type.icon, size: 10, color: color),
            );
          }),
        ),
        if (config.instances > 4)
           Padding(
             padding: const EdgeInsets.only(top: 2),
             child: Text('+${config.instances - 4} more', style: const TextStyle(fontSize: 6, color: AppTheme.textMuted)),
           ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.alt_route, size: 8, color: AppTheme.textMuted),
              const SizedBox(width: 2),
              Text(
                'N=${config.instances}',
                style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          component.customName ?? component.type.displayName,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMiniSchema() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withValues(alpha: 0.9),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: const Text(
          'SCHEMA',
          style: TextStyle(fontSize: 5, fontFamily: 'RobotoMono', color: AppTheme.textMuted),
        ),
      ),
    );
  }

  Widget _buildPressureLabel(
    ComponentMetrics metrics,
    FailureEvent? primaryFailure,
    double loadRatio,
    _LoadThresholds thresholds,
    String? cascadeUpstream,
  ) {
    String label = 'LOAD';
    String value = '${(loadRatio * 100).round()}%';
    double severity = 0.0;

    if (primaryFailure != null) {
      severity = primaryFailure.severity;
      switch (primaryFailure.type) {
        case FailureType.overload:
        case FailureType.trafficOverflow:
          label = 'LOAD';
          value = '${(loadRatio * 100).round()}%';
          break;
        case FailureType.queueOverflow:
        case FailureType.consumerLag:
          label = 'QUEUE';
          value = _formatCompact(metrics.queueDepth);
          break;
        case FailureType.latencyBreach:
        case FailureType.upstreamTimeout:
        case FailureType.slowNode:
          label = 'P95';
          value = '${metrics.p95LatencyMs.round()}ms';
          break;
        case FailureType.connectionExhaustion:
          label = 'CONN';
          value = '${(metrics.connectionPoolUtilization * 100).round()}%';
          break;
        case FailureType.cascadingFailure:
          label = 'CASCADE';
          value = cascadeUpstream != null && cascadeUpstream.isNotEmpty
              ? 'from ${_shortName(cascadeUpstream)}'
              : 'upstream';
          break;
        case FailureType.retryStorm:
          label = 'RETRY';
          value = 'storm';
          break;
        case FailureType.circuitBreakerOpen:
          label = 'CB';
          value = 'open';
          break;
        default:
          label = 'LOAD';
          value = '${(loadRatio * 100).round()}%';
          break;
      }
    } else if (metrics.queueDepth > 100) {
      label = 'QUEUE';
      value = _formatCompact(metrics.queueDepth);
    } else if (metrics.connectionPoolUtilization > 0.6) {
      label = 'CONN';
      value = '${(metrics.connectionPoolUtilization * 100).round()}%';
    } else if (metrics.p95LatencyMs > 1200) {
      label = 'P95';
      value = '${metrics.p95LatencyMs.round()}ms';
    }

    final color = severity > 0.8
        ? AppTheme.error
        : severity > 0.5
            ? AppTheme.warning
            : (loadRatio > thresholds.warning ? AppTheme.warning : AppTheme.textSecondary);

    final tooltip = _buildWhyTooltip(
      metrics: metrics,
      primaryFailure: primaryFailure,
      loadRatio: loadRatio,
      thresholds: thresholds,
      cascadeUpstream: cascadeUpstream,
    );

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 2,
            )
          ]
        ),
        child: Text(
          '$label: $value',
          style: TextStyle(
            fontSize: 6, 
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }

  bool _shouldShowPressureLabel({
    required bool isActive,
    required ComponentMetrics metrics,
    required double loadRatio,
    required _LoadThresholds thresholds,
    required List<FailureEvent> componentFailures,
  }) {
    if (!isActive) return false;
    if (loadRatio > thresholds.warning) return true;
    if (metrics.queueDepth > 100) return true;
    if (metrics.connectionPoolUtilization > 0.6) return true;
    if (componentFailures.isNotEmpty) return true;
    return false;
  }

  Widget _buildLoadBar(double loadRatio, _LoadThresholds thresholds) {
    // Green -> Yellow -> Red gradient based on load
    final color = loadRatio > thresholds.overload
        ? AppTheme.error
        : loadRatio > thresholds.critical
            ? AppTheme.error
            : loadRatio > thresholds.warning
                ? AppTheme.warning
                : AppTheme.success;
            
    // Enhanced Load Bar: Taller and with Glow
    return Container(
      height: 6, // Taller
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.3), width: 0.5),
      ),
      // Smoothly animate the width of the load bar
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: loadRatio.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 200), // Smooth 200ms transition
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                boxShadow: loadRatio > 0.7 ? [
                   BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1),
                ] : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusEmoji(bool hasError, bool isSlow, bool isOverloaded, FailureEvent? primaryFailure) {
    IconData? icon;
    Color color = Colors.transparent;
    
    if (primaryFailure != null && primaryFailure.type == FailureType.cascadingFailure) {
      icon = Icons.call_split;
      color = AppTheme.warning;
    } else if (primaryFailure != null && primaryFailure.type == FailureType.retryStorm) {
      icon = Icons.refresh;
      color = Colors.orange;
    } else if (hasError) {
      icon = Icons.error_outline;
      color = AppTheme.error;
    } else if (isOverloaded) {
      icon = Icons.local_fire_department;
      color = Colors.orange;
    } else if (isSlow) {
      icon = Icons.hourglass_bottom;
      color = Colors.amber;
    }
    
    if (icon == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }

  Widget _buildConfigPulseOverlay(int configHash, Color color) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, animation) {
          final scale = Tween<double>(begin: 0.98, end: 1.02).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        child: Container(
          key: ValueKey(configHash),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.1),
            gradient: RadialGradient(
              radius: 0.9,
              colors: [
                color.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 14,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _algorithmShort(String algorithm) {
    switch (algorithm) {
      case 'round_robin':
        return 'RR';
      case 'least_conn':
        return 'LC';
      case 'ip_hash':
        return 'IP';
      case 'consistent_hashing':
        return 'CH';
      default:
        return algorithm.toUpperCase();
    }
  }


  Widget _buildSketchyContent() {
    // Import definition locally or via helper
    int index = 0;
    switch (component.type) {
      case ComponentType.sketchyService: index = 0; break;
      case ComponentType.sketchyDatabase: index = 1; break;
      case ComponentType.sketchyLogic: index = 2; break;
      case ComponentType.sketchyQueue: index = 3; break;
      case ComponentType.sketchyClient: index = 4; break;
      case ComponentType.rectangle: index = 5; break;
      case ComponentType.circle: index = 6; break;
      case ComponentType.arrow: index = 7; break;
      case ComponentType.line: index = 8; break;
      case ComponentType.diamond: index = 2; break;
      default: index = 0;
    }

    // Unified handling for all sketchy/geometric components
    const isGeometric = true;

    return Stack(
      children: [
        // Shape Layer
        Positioned.fill(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scale(component.flipX ? -1.0 : 1.0, component.flipY ? -1.0 : 1.0),
            child: CustomPaint(
              painter: ExcalidrawPainter(
                elements: excalidrawLibrary[index],
                overrideColor: isSelected ? AppTheme.primary : null,
                scaleToFit: true, // Use auto-scaling
                forceSolidFill: true, // No hachure/patterns
              ),
            ),
          ),
        ),
        
        // Text Layer - Centered for all sketchy shapes
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: isEditing 
              ? _InlineTextEditor(
                  initialText: component.customName ?? '',
                  onChange: onTextChange!,
                  onDone: onEditDone!,
                  isCentered: true,
                  maxWidth: math.max(80.0, component.size.width - 20),
                )
              : Text(
                  component.customName ?? '',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.architectsDaughter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
          ),
        ),
      ],
    );
  }

  String _formatRps(int rps) {
    if (rps >= 1000000) return '${(rps / 1000000).toStringAsFixed(1)}M/s';
    if (rps >= 1000) return '${(rps / 1000).toStringAsFixed(1)}K/s';
    return '$rps/s';
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: component.customName ?? component.type.displayName);
    final presets = component.type.presets;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Configure ${component.type.displayName}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Input
                TextField(
                  controller: controller,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Component Name',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                    hintStyle: TextStyle(color: AppTheme.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
                  ),
                  autofocus: true,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      ref.read(canvasProvider.notifier).renameComponent(component.id, value);
                    }
                    Navigator.pop(context);
                  },
                ),
                
                if (presets.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Quick Select:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((preset) {
                      return ActionChip(
                        label: Text(preset),
                        labelStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                        backgroundColor: AppTheme.surfaceLight,
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onPressed: () {
                          controller.text = preset;
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                 ref.read(canvasProvider.notifier).renameComponent(component.id, controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Color GetStatusColor(bool hasError, bool isOverloaded, bool isSlow) {
    if (hasError) return AppTheme.error;
    if (isOverloaded) return Colors.orange;
    if (isSlow) return Colors.amber;
    return AppTheme.surface;
  }

  _LoadThresholds _loadThresholds(ComponentType type) {
    return switch (type) {
      ComponentType.database ||
      ComponentType.keyValueStore ||
      ComponentType.timeSeriesDb ||
      ComponentType.graphDb ||
      ComponentType.vectorDb ||
      ComponentType.searchIndex ||
      ComponentType.dataWarehouse ||
      ComponentType.dataLake => const _LoadThresholds(
          warning: 0.65,
          critical: 0.8,
          overload: 1.0,
        ),
      ComponentType.cache => const _LoadThresholds(
          warning: 0.75,
          critical: 0.9,
          overload: 1.15,
        ),
      ComponentType.queue ||
      ComponentType.pubsub ||
      ComponentType.stream => const _LoadThresholds(
          warning: 0.7,
          critical: 0.85,
          overload: 1.0,
        ),
      ComponentType.serverless => const _LoadThresholds(
          warning: 0.8,
          critical: 0.9,
          overload: 1.2,
        ),
      _ => const _LoadThresholds(
          warning: 0.7,
          critical: 0.85,
          overload: 1.1,
        ),
    };
  }

  bool _isDatabaseLikeComponent(ComponentType type) {
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

  String _buildWhyTooltip({
    required ComponentMetrics metrics,
    required FailureEvent? primaryFailure,
    required double loadRatio,
    required _LoadThresholds thresholds,
    required String? cascadeUpstream,
  }) {
    const queueLagThreshold = 2000.0;
    const queueOverflowThreshold = 5000.0;
    const slowLatencyThresholdMs = 1500.0;
    const connWarn = 0.6;
    const connCritical = 0.9;

    String detail = '';
    String fix = '';
    if (primaryFailure != null) {
      switch (primaryFailure.type) {
        case FailureType.overload:
        case FailureType.trafficOverflow:
          detail =
              'Load ${(loadRatio * 100).round()}% (warn > ${(thresholds.warning * 100).round()}%, overload > ${(thresholds.overload * 100).round()}%)';
          break;
        case FailureType.queueOverflow:
        case FailureType.consumerLag:
          detail =
              'Queue ${metrics.queueDepth.round()} (lag > ${queueLagThreshold.round()}, overflow > ${queueOverflowThreshold.round()})';
          break;
        case FailureType.latencyBreach:
        case FailureType.upstreamTimeout:
        case FailureType.slowNode:
          detail =
              'P95 ${metrics.p95LatencyMs.round()}ms (slow > ${slowLatencyThresholdMs.round()}ms)';
          break;
        case FailureType.connectionExhaustion:
          detail =
              'Conn ${(metrics.connectionPoolUtilization * 100).round()}% (warn > ${(connWarn * 100).round()}%, critical > ${(connCritical * 100).round()}%)';
          break;
        case FailureType.cascadingFailure:
          detail = cascadeUpstream != null && cascadeUpstream.isNotEmpty
              ? 'Upstream: $cascadeUpstream (severity > 0.6)'
              : 'Upstream dependency failure (severity > 0.6)';
          break;
        case FailureType.retryStorm:
          detail = 'Retry amplification (error rate > 20%)';
          break;
        case FailureType.circuitBreakerOpen:
          detail = 'Circuit opened after repeated failures';
          break;
        default:
          detail = primaryFailure.message;
      }
      fix = _suggestFix(primaryFailure.type, metrics, component.config, component.type);
      if (primaryFailure.recommendation.isNotEmpty &&
          primaryFailure.recommendation != fix) {
        fix = '$fix\nAlt: ${primaryFailure.recommendation}';
      }
      return '${primaryFailure.type.displayName}: ${primaryFailure.message}\nCause: $detail\nFix: $fix';
    }

    FailureType inferredType = FailureType.overload;
    if (metrics.queueDepth > 100) {
      inferredType = FailureType.queueOverflow;
      detail =
          'Queue ${metrics.queueDepth.round()} (lag > ${queueLagThreshold.round()}, overflow > ${queueOverflowThreshold.round()})';
    } else if (metrics.connectionPoolUtilization > connWarn) {
      inferredType = FailureType.connectionExhaustion;
      detail =
          'Conn ${(metrics.connectionPoolUtilization * 100).round()}% (warn > ${(connWarn * 100).round()}%)';
    } else if (metrics.p95LatencyMs > slowLatencyThresholdMs) {
      inferredType = FailureType.latencyBreach;
      detail =
          'P95 ${metrics.p95LatencyMs.round()}ms (slow > ${slowLatencyThresholdMs.round()}ms)';
    } else {
      detail =
          'Load ${(loadRatio * 100).round()}% (warn > ${(thresholds.warning * 100).round()}%)';
    }

    fix = _suggestFix(inferredType, metrics, component.config, component.type);
    return 'Cause: $detail\nFix: $fix';
  }

  String _suggestFix(
    FailureType type,
    ComponentMetrics metrics,
    ComponentConfig config,
    ComponentType componentType,
  ) {
    final autoscaleHint = config.autoScale
        ? 'Increase max instances or per-node capacity'
        : 'Enable autoscaling or add instances/capacity';

    switch (type) {
      case FailureType.overload:
      case FailureType.trafficOverflow:
        if (_isDatabaseLikeComponent(componentType)) {
          return '$autoscaleHint; add read replicas or shard/partition; add cache to offload reads';
        }
        if (componentType == ComponentType.cache) {
          return '$autoscaleHint; increase cache memory, tune TTL, and prewarm hot keys';
        }
        if (componentType == ComponentType.queue ||
            componentType == ComponentType.pubsub ||
            componentType == ComponentType.stream) {
          return 'Scale consumers/workers, increase partitions, and enable backpressure';
        }
        return '$autoscaleHint; add a cache or queue to smooth spikes';
      case FailureType.queueOverflow:
      case FailureType.consumerLag:
        return 'Scale consumers/workers, increase partitions, and add DLQ/backpressure';
      case FailureType.latencyBreach:
      case FailureType.upstreamTimeout:
      case FailureType.slowNode:
        return 'Add capacity, reduce downstream calls, add cache/CDN, and tighten timeouts';
      case FailureType.connectionExhaustion:
        return 'Increase connection pool size, add instances, or use pooling at callers';
      case FailureType.circuitBreakerOpen:
        return 'Fix upstream errors, add fallback, and reduce retry pressure';
      case FailureType.retryStorm:
        return 'Add jittered backoff, cap retries, and enable circuit breaker';
      case FailureType.cacheStampede:
        return 'Increase cache size, add jittered TTL, and prewarm hot keys';
      case FailureType.spof:
        return 'Add redundant node(s) behind a load balancer; enable autoscaling; use multi-AZ';
      case FailureType.dataLoss:
        return 'Enable replication (RF≥2), add backups/snapshots, and test restore';
      case FailureType.scaleUpDelay:
      case FailureType.coldStart:
        return 'Keep min instances higher, pre-warm instances, or use warm pools';
      case FailureType.cascadingFailure:
        return 'Fix upstream dependency; add fallback or queue to isolate failures';
      case FailureType.componentCrash:
        return 'Restart/replace instance and add redundancy';
      default:
        return 'Add capacity or reduce load';
    }
  }

  String _shortName(String value) {
    if (value.length <= 12) return value;
    return '${value.substring(0, 10)}...';
  }

  FailureEvent? _pickPrimaryFailure(List<FailureEvent> failures) {
    if (failures.isEmpty) return null;
    final ordered = List<FailureEvent>.from(failures)
      ..sort((a, b) => b.severity.compareTo(a.severity));
    return ordered.first;
  }

  bool _isOverloadFailure(FailureType type) {
    return type == FailureType.overload ||
        type == FailureType.trafficOverflow ||
        type == FailureType.queueOverflow ||
        type == FailureType.consumerLag ||
        type == FailureType.connectionExhaustion;
  }

  bool _isLatencyFailure(FailureType type) {
    return type == FailureType.latencyBreach ||
        type == FailureType.upstreamTimeout ||
        type == FailureType.slowNode;
  }

  bool _isDesignTimeFailure(FailureType type) {
    return type == FailureType.spof ||
        type == FailureType.dataLoss ||
        type == FailureType.costOverrun;
  }

  String _formatCompact(num value) {
    final numVal = value.toDouble();
    if (numVal >= 1000000) return '${(numVal / 1000000).toStringAsFixed(1)}M';
    if (numVal >= 1000) return '${(numVal / 1000).toStringAsFixed(1)}K';
    return numVal.round().toString();
  }
}

class _LoadThresholds {
  final double warning;
  final double critical;
  final double overload;

  const _LoadThresholds({
    required this.warning,
    required this.critical,
    required this.overload,
  });
}



class _InlineTextEditor extends StatefulWidget {
  final String initialText;
  final Function(String) onChange;
  final VoidCallback onDone;
  final bool isCentered;
  final double maxWidth;

  const _InlineTextEditor({
    required this.initialText,
    required this.onChange,
    required this.onDone,
    this.isCentered = false,
    required this.maxWidth,
  });

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _didComplete = false;

  void _complete() {
    if (_didComplete) return;
    _didComplete = true;
    widget.onDone();
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _complete();
      }
    });
    // Request focus next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.maxWidth,
      child: Material(
        color: Colors.transparent,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textAlign: widget.isCentered ? TextAlign.center : TextAlign.start,
          style: widget.isCentered 
            ? GoogleFonts.architectsDaughter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              )
            : const TextStyle(
                fontSize: 16,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            isDense: true,
          ),
          onChanged: (val) => widget.onChange(val),
          onSubmitted: (_) => _complete(),
          onEditingComplete: _complete,
        ),
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final bool isCyberpunk;
  
  const _GlassContainer({
    required this.child,
    this.isCyberpunk = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isCyberpunk 
            ? AppTheme.neonCyan.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCyberpunk 
              ? AppTheme.neonCyan.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.2), 
          width: isCyberpunk ? 1.5 : 0.5
        ),
        boxShadow: isCyberpunk 
            ? [
                BoxShadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : [],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isCyberpunk ? 0.15 : 0.05),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}

class _DistributionLinePainter extends CustomPainter {
  final Color color;
  final int count;
  
  _DistributionLinePainter({required this.color, required this.count});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
      
    // Center point top
    final centerTop = Offset(size.width / 2, 0);
    // Draw vertical down
    canvas.drawLine(centerTop, Offset(centerTop.dx, size.height * 0.5), paint);
    
    // Draw horizontal bar
    final barY = size.height * 0.5;
    
    // Calculate width of distribution
    // 4 shards -> 3 gaps. 
    // We assume the caller sized the canvas to fit the shards
    
    final spacePerShard = size.width / count;
    final startX = spacePerShard / 2;
    final endX = size.width - (spacePerShard / 2);
    
    canvas.drawLine(Offset(startX, barY), Offset(endX, barY), paint);
    
    // Draw verticals down to shards
    for (int i = 0; i < count; i++) {
      final x = startX + (i * spacePerShard);
      canvas.drawLine(Offset(x, barY), Offset(x, size.height), paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SimpleLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  
  _SimpleLinePainter({required this.start, required this.end, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
      
    canvas.drawLine(start, end, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
