import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
              ],
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

  MetricStatus _getCostStatus(double current, double budget) {
    if (current <= budget) return MetricStatus.good;
    if (current <= budget * 1.2) return MetricStatus.warning;
    return MetricStatus.critical;
  }
}

enum MetricStatus { good, warning, critical }

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
