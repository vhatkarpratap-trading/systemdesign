/// Global metrics for the entire system during simulation
class GlobalMetrics {
  final int totalRps;
  final double avgLatencyMs;
  final double p50LatencyMs;
  final double p95LatencyMs;
  final double p99LatencyMs;
  final double errorRate;
  final double availability;
  final double totalCostPerHour;
  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;

  const GlobalMetrics({
    this.totalRps = 0,
    this.avgLatencyMs = 0.0,
    this.p50LatencyMs = 0.0,
    this.p95LatencyMs = 0.0,
    this.p99LatencyMs = 0.0,
    this.errorRate = 0.0,
    this.availability = 1.0,
    this.totalCostPerHour = 0.0,
    this.totalRequests = 0,
    this.successfulRequests = 0,
    this.failedRequests = 0,
  });

  GlobalMetrics copyWith({
    int? totalRps,
    double? avgLatencyMs,
    double? p50LatencyMs,
    double? p95LatencyMs,
    double? p99LatencyMs,
    double? errorRate,
    double? availability,
    double? totalCostPerHour,
    int? totalRequests,
    int? successfulRequests,
    int? failedRequests,
  }) {
    return GlobalMetrics(
      totalRps: totalRps ?? this.totalRps,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      p50LatencyMs: p50LatencyMs ?? this.p50LatencyMs,
      p95LatencyMs: p95LatencyMs ?? this.p95LatencyMs,
      p99LatencyMs: p99LatencyMs ?? this.p99LatencyMs,
      errorRate: errorRate ?? this.errorRate,
      availability: availability ?? this.availability,
      totalCostPerHour: totalCostPerHour ?? this.totalCostPerHour,
      totalRequests: totalRequests ?? this.totalRequests,
      successfulRequests: successfulRequests ?? this.successfulRequests,
      failedRequests: failedRequests ?? this.failedRequests,
    );
  }

  /// Calculate monthly cost
  double get monthlyCost => totalCostPerHour * 24 * 30;

  /// Format latency for display
  String formatLatency(double ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms.toStringAsFixed(0)}ms';
  }

  /// Format availability as percentage
  String get availabilityString {
    final percentage = availability * 100;
    if (percentage >= 99.99) return '${percentage.toStringAsFixed(3)}%';
    if (percentage >= 99) return '${percentage.toStringAsFixed(2)}%';
    return '${percentage.toStringAsFixed(1)}%';
  }

  /// Format cost for display
  String get costString {
    if (monthlyCost >= 1000) {
      return '\$${(monthlyCost / 1000).toStringAsFixed(1)}K/mo';
    }
    return '\$${monthlyCost.toStringAsFixed(0)}/mo';
  }
}

/// Metrics summary for a simulation run
class SimulationSummary {
  final Duration duration;
  final GlobalMetrics finalMetrics;
  final List<FailureEvent> failures;
  final Map<String, ComponentMetricsSummary> componentMetrics;

  const SimulationSummary({
    required this.duration,
    required this.finalMetrics,
    this.failures = const [],
    this.componentMetrics = const {},
  });
}

/// Summary of metrics for a single component over the simulation
class ComponentMetricsSummary {
  final String componentId;
  final double avgCpuUsage;
  final double maxCpuUsage;
  final int avgRps;
  final int maxRps;
  final double avgLatencyMs;
  final double maxLatencyMs;
  final int totalErrors;

  const ComponentMetricsSummary({
    required this.componentId,
    this.avgCpuUsage = 0.0,
    this.maxCpuUsage = 0.0,
    this.avgRps = 0,
    this.maxRps = 0,
    this.avgLatencyMs = 0.0,
    this.maxLatencyMs = 0.0,
    this.totalErrors = 0,
  });
}

/// A failure event during simulation
class FailureEvent {
  final DateTime timestamp;
  final String componentId;
  final FailureType type;
  final String message;
  final String recommendation;

  const FailureEvent({
    required this.timestamp,
    required this.componentId,
    required this.type,
    required this.message,
    required this.recommendation,
  });
}

/// Types of failures that can occur
enum FailureType {
  overload('Overload', 'Component exceeded capacity'),
  spof('SPOF', 'Single point of failure detected'),
  latencyBreach('Latency Breach', 'SLA violated'),
  dataLoss('Data Loss Risk', 'No replication configured'),
  costOverrun('Cost Overrun', 'Budget exceeded'),
  queueOverflow('Queue Overflow', 'Message queue full');

  final String displayName;
  final String description;

  const FailureType(this.displayName, this.description);
}
