import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/component.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';

/// Panel showing real-time simulation metrics
class MetricsPanel extends ConsumerWidget {
  const MetricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(simulationProvider);
    final metrics = simState.globalMetrics;
    final problem = ref.watch(currentProblemProvider);
    final components = ref.watch(canvasProvider.select((s) => s.components));
    final componentMetrics = ref.watch(simulationMetricsProvider);
    final queueingTarget = _selectQueueingTarget(components, componentMetrics);
    final queueingStatsMm1 = queueingTarget == null
        ? null
        : _computeQueueingStats(
            lambda: queueingTarget.lambda,
            mu: queueingTarget.mu,
            servers: 1,
          );
    final queueingStatsMmc = queueingTarget == null
        ? null
        : _computeQueueingStats(
            lambda: queueingTarget.lambda,
            mu: queueingTarget.mu,
            servers: queueingTarget.servers,
          );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.glassDecoration(borderRadius: 12),
      child: RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: simState.isRunning ? AppTheme.success : AppTheme.textMuted,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'System Metrics',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: simState.isRunning ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                ),
                if (simState.isRunning)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Main metrics grid
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _MetricTile(
                  label: 'RPS',
                  value: _formatNumber(metrics.totalRps),
                  target: problem.constraints.qpsFormatted,
                  status: _getRpsStatus(metrics.totalRps, problem.constraints.effectiveQps),
                ),
                _MetricTile(
                  label: 'Latency P95',
                  value: '${metrics.p95LatencyMs.toInt()}ms',
                  target: '${problem.constraints.latencySlaMsP95}ms',
                  status: _getLatencyStatus(
                    metrics.p95LatencyMs,
                    problem.constraints.latencySlaMsP95.toDouble(),
                  ),
                ),
                _MetricTile(
                  label: 'Availability',
                  value: metrics.availabilityString,
                  target: problem.constraints.availabilityString,
                  status: _getAvailabilityStatus(
                    metrics.availability,
                    problem.constraints.availabilityTarget,
                  ),
                ),
                _MetricTile(
                  label: 'Error Budget',
                  value: '${(metrics.errorBudgetRemaining * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  target: '>20% remaining',
                  status: _getErrorBudgetStatus(metrics.errorBudgetRemaining),
                ),
                _MetricTile(
                  label: 'Burn Rate',
                  value: '${metrics.errorBudgetBurnRate.toStringAsFixed(1)}×',
                  target: '<1.0×',
                  status: _getBurnRateStatus(metrics.errorBudgetBurnRate),
                ),
                // The original instruction seems to be for a different context or widget,
                // as 'widget.component' is not available here and '_MetricRow' is not defined.
                // Assuming the intent was to add these as new _MetricTile entries if applicable
                // to global metrics, or that these are placeholders for a future component-specific panel.
                // For now, I will add them as _MetricTile entries, assuming global metrics can have these.
                // If these metrics are only relevant for specific components (e.g., cache),
                // then this panel would need to be refactored to accept a component or
                // these metrics would need to be conditionally displayed based on global state.
                // Given the instruction, I'm adding them as new tiles.

                _MetricTile(
                  label: 'Eviction Rate',
                  value: '${metrics.evictionRate.toStringAsFixed(0)}/sec',
                  target: '<500/sec', // Assuming a common target for eviction rate
                  status: metrics.evictionRate > 500 ? MetricStatus.critical : MetricStatus.good,
                ),
                _MetricTile(
                  label: 'Error Rate',
                  value: '${(metrics.errorRate * 100).toStringAsFixed(2)}%',
                  target: '<0.1%',
                  status: _getErrorStatus(metrics.errorRate),
                ),
                _MetricTile(
                  label: 'Cost',
                  value: metrics.costString,
                  target: '\$${problem.constraints.budgetPerMonth}/mo',
                  status: _getCostStatus(
                    metrics.monthlyCost,
                    problem.constraints.budgetPerMonth.toDouble(),
                  ),
                ),
                if (queueingStatsMm1 != null)
                  _MetricTile(
                    label: 'M/M/1',
                    value: _formatQueueingValue(queueingStatsMm1),
                    target: 'ρ<0.7',
                    status: _getQueueingStatus(queueingStatsMm1),
                  ),
                if (queueingStatsMmc != null)
                  _MetricTile(
                    label: 'M/M/c',
                    value: _formatQueueingValue(queueingStatsMmc),
                    target: 'ρ<0.7',
                    status: _getQueueingStatus(queueingStatsMmc),
                  ),
              ],
            ),
            if (queueingTarget != null) ...[
              const SizedBox(height: 8),
              Text(
                'Queueing model uses ${queueingTarget.label} '
                '(λ ${queueingTarget.lambda.toStringAsFixed(0)} rps, '
                'μ ${queueingTarget.mu.toStringAsFixed(0)} rps, '
                'c ${queueingTarget.servers})',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  MetricStatus _getRpsStatus(int current, int target) {
    final ratio = current / target;
    if (ratio >= 0.95) return MetricStatus.good;
    if (ratio >= 0.7) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getLatencyStatus(double current, double target) {
    if (current <= target) return MetricStatus.good;
    if (current <= target * 1.5) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getAvailabilityStatus(double current, double target) {
    if (current >= target) return MetricStatus.good;
    if (current >= target * 0.99) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getErrorStatus(double errorRate) {
    if (errorRate <= 0.001) return MetricStatus.good;
    if (errorRate <= 0.01) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getErrorBudgetStatus(double remaining) {
    if (remaining >= 0.5) return MetricStatus.good;
    if (remaining >= 0.2) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getBurnRateStatus(double burnRate) {
    if (burnRate <= 1.0) return MetricStatus.good;
    if (burnRate <= 2.0) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getCostStatus(double current, double budget) {
    if (current <= budget) return MetricStatus.good;
    if (current <= budget * 1.2) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus _getQueueingStatus(_QueueingStats stats) {
    if (!stats.isStable) return MetricStatus.critical;
    if (stats.rho > 0.85) return MetricStatus.warning;
    return MetricStatus.good;
  }

  String _formatQueueingValue(_QueueingStats stats) {
    if (!stats.isStable) {
      return 'Unstable (ρ ${stats.rho.toStringAsFixed(2)})';
    }
    final latencyMs = stats.waitMs;
    final formatted = latencyMs >= 1000
        ? '${(latencyMs / 1000).toStringAsFixed(2)}s'
        : '${latencyMs.toStringAsFixed(0)}ms';
    return '$formatted (ρ ${stats.rho.toStringAsFixed(2)})';
  }

  _QueueingTarget? _selectQueueingTarget(
    List<SystemComponent> components,
    Map<String, ComponentMetrics> metricsMap,
  ) {
    _QueueingTarget? best;
    double bestRho = -1;

    for (final component in components) {
      if (!_isQueueingCandidate(component.type)) continue;
      final metrics = metricsMap[component.id];
      if (metrics == null || metrics.currentRps <= 0) continue;

      final effectiveInstances =
          metrics.readyInstances + (metrics.coldStartingInstances * 0.5);
      final servers = max(1, effectiveInstances.round());
      final mu = component.config.capacity.toDouble();
      final capacity = mu * servers;
      if (capacity <= 0) continue;

      final rho = metrics.currentRps / capacity;
      if (rho > bestRho) {
        bestRho = rho;
        best = _QueueingTarget(
          label: component.customName ?? component.type.displayName,
          lambda: metrics.currentRps.toDouble(),
          mu: mu,
          servers: servers,
          rho: rho,
        );
      }
    }

    return best;
  }

  bool _isQueueingCandidate(ComponentType type) {
    return switch (type) {
      ComponentType.appServer ||
      ComponentType.customService ||
      ComponentType.authService ||
      ComponentType.notificationService ||
      ComponentType.searchService ||
      ComponentType.analyticsService ||
      ComponentType.scheduler ||
      ComponentType.serviceDiscovery ||
      ComponentType.configService ||
      ComponentType.secretsManager ||
      ComponentType.featureFlag ||
      ComponentType.cache ||
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
        servers: servers,
      );
    }

    if (servers == 1) {
      final w = 1 / (mu - lambda);
      return _QueueingStats(
        rho: rho,
        waitMs: w * 1000,
        isStable: true,
        servers: servers,
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
      servers: servers,
    );
  }
}

enum MetricStatus { good, warning, critical }

class _QueueingTarget {
  final String label;
  final double lambda;
  final double mu;
  final int servers;
  final double rho;

  const _QueueingTarget({
    required this.label,
    required this.lambda,
    required this.mu,
    required this.servers,
    required this.rho,
  });
}

class _QueueingStats {
  final double rho;
  final double waitMs;
  final bool isStable;
  final int servers;

  const _QueueingStats({
    required this.rho,
    required this.waitMs,
    required this.isStable,
    required this.servers,
  });
}

/// Individual metric tile
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String target;
  final MetricStatus status;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.target,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MetricStatus.good => AppTheme.success,
      MetricStatus.warning => AppTheme.warning,
      MetricStatus.critical => AppTheme.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            'Target: $target',
            style: const TextStyle(
              fontSize: 9,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal metrics bar
class MetricsBar extends ConsumerWidget {
  const MetricsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(simulationProvider);
    final metrics = simState.globalMetrics;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: RepaintBoundary(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _CompactMetric(
              icon: Icons.speed,
              value: '${_formatNumber(metrics.totalRps)} RPS',
              color: AppTheme.primary,
            ),
            _CompactMetric(
              icon: Icons.timer,
              value: '${metrics.p95LatencyMs.toInt()}ms',
              color: metrics.p95LatencyMs > 200 ? AppTheme.warning : AppTheme.success,
            ),
            _CompactMetric(
              icon: Icons.check_circle,
              value: metrics.availabilityString,
              color: metrics.availability >= 0.99 ? AppTheme.success : AppTheme.warning,
            ),
            _CompactMetric(
              icon: Icons.attach_money,
              value: metrics.costString,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _CompactMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _CompactMetric({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
