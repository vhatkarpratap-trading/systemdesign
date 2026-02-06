import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/component.dart';
import '../../models/metrics.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';

class ComponentHoverPopover extends ConsumerStatefulWidget {
  final SystemComponent component;
  final Widget child;

  const ComponentHoverPopover({
    super.key,
    required this.component,
    required this.child,
  });

  @override
  ConsumerState<ComponentHoverPopover> createState() => _ComponentHoverPopoverState();
}

class _ComponentHoverPopoverState extends ConsumerState<ComponentHoverPopover> {
  final GlobalKey _anchorKey = GlobalKey();
  Timer? _hoverTimer;
  OverlayEntry? _entry;
  bool _isHovered = false;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _removeEntry();
    super.dispose();
  }

  void _handleEnter(PointerEnterEvent _) {
    _isHovered = true;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(seconds: 2), _showEntry);
  }

  void _handleExit(PointerExitEvent _) {
    _isHovered = false;
    _hoverTimer?.cancel();
    _removeEntry();
  }

  void _showEntry() {
    if (!_isHovered || _entry != null || !mounted) return;
    _entry = _buildEntry();
    Overlay.of(context).insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  OverlayEntry _buildEntry() {
    return OverlayEntry(
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
            final anchorBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
            if (overlayBox == null || anchorBox == null) {
              return const SizedBox.shrink();
            }

            final anchor = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
            final size = anchorBox.size;
            const panelWidth = 280.0;
            const estimatedHeight = 240.0;

            double left = anchor.dx + size.width + 12;
            if (left + panelWidth > overlayBox.size.width - 12) {
              left = anchor.dx - panelWidth - 12;
            }

            double top = anchor.dy - 8;
            final maxTop = overlayBox.size.height - 12;
            if (top + estimatedHeight > maxTop) {
              top = max(12, maxTop - estimatedHeight);
            }
            if (top < 12) top = 12;

            final metrics = ref.watch(
              simulationMetricsProvider.select((map) => map[widget.component.id]),
            ) ?? widget.component.metrics;
            final globalMetrics = ref.watch(
              simulationProvider.select((s) => s.globalMetrics),
            );

            return Positioned(
              left: left,
              top: top,
              child: IgnorePointer(
                child: _HoverMetricsCard(
                  component: widget.component,
                  metrics: metrics,
                  globalMetrics: globalMetrics,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: KeyedSubtree(
        key: _anchorKey,
        child: widget.child,
      ),
    );
  }
}

class _HoverMetricsCard extends StatelessWidget {
  final SystemComponent component;
  final ComponentMetrics metrics;
  final GlobalMetrics globalMetrics;

  const _HoverMetricsCard({
    required this.component,
    required this.metrics,
    required this.globalMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveInstances = max(
      1,
      metrics.readyInstances + (metrics.coldStartingInstances * 0.5).round(),
    );
    final capacity = component.config.capacity * effectiveInstances;
    final rho = capacity > 0 ? (metrics.currentRps / capacity) : 0.0;

    final mm1 = _computeQueueingStats(
      lambda: metrics.currentRps.toDouble(),
      mu: component.config.capacity.toDouble(),
      servers: 1,
    );
    final mmc = _computeQueueingStats(
      lambda: metrics.currentRps.toDouble(),
      mu: component.config.capacity.toDouble(),
      servers: max(1, effectiveInstances),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                component.customName ?? component.type.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              _sectionTitle('Component'),
              _metricRow('RPS', _formatNumber(metrics.currentRps)),
              _metricRow('P95', '${metrics.p95LatencyMs.round()}ms'),
              _metricRow('CPU', '${(metrics.cpuUsage * 100).round()}%'),
              _metricRow('Mem', '${(metrics.memoryUsage * 100).round()}%'),
              if (metrics.queueDepth > 0) _metricRow('Queue', _formatCompact(metrics.queueDepth)),
              if (component.type == ComponentType.cache)
                _metricRow('Cache Hit', '${(metrics.cacheHitRate * 100).round()}%'),
              if (metrics.connectionPoolUtilization > 0)
                _metricRow('Conn', '${(metrics.connectionPoolUtilization * 100).round()}%'),
              if (_isDatabaseLike(component.type))
                _metricRow(
                  'Quorum R/W',
                  '${component.config.quorumRead ?? 1}/${component.config.quorumWrite ?? 1}',
                ),
              if (component.config.replication && component.config.replicationFactor > 1)
                _metricRow(
                  'Replication',
                  'RF ${component.config.replicationFactor} ${component.config.replicationType.name}',
                ),
              const SizedBox(height: 8),
              _sectionTitle('Queueing'),
              if (mm1 != null) _metricRow('M/M/1', _formatQueueing(mm1)),
              if (mmc != null) _metricRow('M/M/c', _formatQueueing(mmc)),
              const SizedBox(height: 8),
              _sectionTitle('System'),
              _metricRow('Err Budget', '${(globalMetrics.errorBudgetRemaining * 100).round()}%'),
              _metricRow('Burn Rate', '${globalMetrics.errorBudgetBurnRate.toStringAsFixed(1)}×'),
              _metricRow('Utilization', '${(rho * 100).round()}%'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: AppTheme.textMuted,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _formatCompact(num value) {
    final numVal = value.toDouble();
    if (numVal >= 1000000) return '${(numVal / 1000000).toStringAsFixed(1)}M';
    if (numVal >= 1000) return '${(numVal / 1000).toStringAsFixed(1)}K';
    return numVal.round().toString();
  }

  String _formatQueueing(_QueueingStats stats) {
    if (!stats.isStable) {
      return 'Unstable (ρ ${stats.rho.toStringAsFixed(2)})';
    }
    final latencyMs = stats.waitMs;
    final formatted = latencyMs >= 1000
        ? '${(latencyMs / 1000).toStringAsFixed(2)}s'
        : '${latencyMs.toStringAsFixed(0)}ms';
    return '$formatted (ρ ${stats.rho.toStringAsFixed(2)})';
  }

  bool _isDatabaseLike(ComponentType type) {
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

  _QueueingStats? _computeQueueingStats({
    required double lambda,
    required double mu,
    required int servers,
  }) {
    if (lambda <= 0 || mu <= 0 || servers <= 0) return null;
    final rho = lambda / (mu * servers);
    if (!rho.isFinite) return null;
    if (rho >= 1) {
      return _QueueingStats(
        rho: rho,
        waitMs: double.infinity,
        isStable: false,
      );
    }

    if (servers == 1) {
      final w = 1 / (mu - lambda);
      return _QueueingStats(
        rho: rho,
        waitMs: w * 1000,
        isStable: true,
      );
    }

    final a = lambda / mu;
    double sum = 1.0;
    double term = 1.0;
    for (int n = 1; n < servers; n++) {
      term *= a / n;
      sum += term;
    }

    final numerator = (term * a / servers) / (1 - rho);
    final pWait = numerator / (sum + numerator);
    final wq = pWait / (mu * servers - lambda);
    final w = wq + (1 / mu);

    return _QueueingStats(
      rho: rho,
      waitMs: w * 1000,
      isStable: true,
    );
  }
}

class _QueueingStats {
  final double rho;
  final double waitMs;
  final bool isStable;

  const _QueueingStats({
    required this.rho,
    required this.waitMs,
    required this.isStable,
  });
}
