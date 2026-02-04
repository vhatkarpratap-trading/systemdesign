import 'package:flutter/material.dart';

/// Global metrics for the entire system during simulation
class GlobalMetrics {
  final int totalRps;
  final double avgLatencyMs;
  final double p50LatencyMs;
  final double p95LatencyMs;
  final double p99LatencyMs;
  final double evictionRate; // Evictions per second (for caches)
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
    this.evictionRate = 0.0,
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
  
  // Enhanced context for production reality
  final double severity; // 0.0-1.0, how severe is the impact on users
  final List<String> affectedComponents; // For cascading failures
  final Duration? expectedRecoveryTime; // How long until recovery
  final bool userVisible; // Does this impact end users directly?
  
  // Actionable Fixes
  final FixType? fixType;

  const FailureEvent({
    required this.timestamp,
    required this.componentId,
    required this.type,
    required this.message,
    required this.recommendation,
    this.severity = 0.5,
    this.affectedComponents = const [],
    this.expectedRecoveryTime,
    this.userVisible = true,
    this.fixType,
  });
}

/// Types of automated fixes that can be applied
enum FixType {
  enableAutoscaling('Enable Autoscaling', Icons.trending_up),
  addCircuitBreaker('Add Circuit Breaker', Icons.flash_off),
  increaseReplicas('Increase Replicas', Icons.copy),
  enableReplication('Enable Replication', Icons.storage),
  enableRateLimiting('Enable Rate Limiting', Icons.speed),
  increaseConnectionPool('Increase Connections', Icons.cable),
  addDlq('Add Dead Letter Queue', Icons.mail_outline);

  final String label;
  final IconData icon;

  const FixType(this.label, this.icon);
}

/// Types of failures that can occur
enum FailureType {
  // Capacity & Performance
  overload('Overload', 'Component exceeded capacity'),
  trafficOverflow('Traffic Overflow', 'Incoming traffic exceeds component capacity'),
  spof('SPOF', 'Single point of failure detected'),
  latencyBreach('Latency Breach', 'SLA violated'),
  dataLoss('Data Loss Risk', 'No replication configured'),
  costOverrun('Cost Overrun', 'Budget exceeded'),
  queueOverflow('Queue Overflow', 'Message queue full'),
  
  // Network & Infrastructure
  networkPartition('Network Partition', 'Region isolated from rest of system'),
  slowNode('Slow Node', 'Node responding 10-100× slower'),
  connectionExhaustion('Connection Pool Full', 'No available connections'),
  dnsFailure('DNS Resolution Failed', 'Cannot resolve service address'),
  
  // Cascading & Dependencies
  cascadingFailure('Cascading Failure', 'Upstream failure propagated'),
  circuitBreakerOpen('Circuit Breaker Open', 'Too many failures, circuit opened'),
  retryStorm('Retry Storm', 'Excessive retries overwhelming system'),
  thunderingHerd('Thundering Herd', 'Synchronized traffic spike'),
  
  // Autoscaling & Capacity
  scaleUpDelay('Scale-Up Delay', 'Waiting for new instances to provision'),
  coldStart('Cold Start Penalty', 'New instance warming up'),
  rebalancing('Rebalancing', 'Traffic redistributing across nodes'),
  
  // Data Consistency
  staleRead('Stale Read', 'Reading outdated data from replica'),
  lostUpdate('Lost Update', 'Concurrent write conflict'),
  readAfterWriteFailure('Read-After-Write Failed', 'Cannot read own write'),
  duplicateDelivery('Duplicate Message', 'At-least-once delivery side effect'),
  replicationLag('Replication Lag', 'Replica falling behind primary'),
  
  // Operational
  badDeployment('Bad Deployment', 'Recent deploy introduced errors'),
  schemaMigration('Schema Migration Issue', 'Database schema incompatibility'),
  configDrift('Configuration Drift', 'Inconsistent config across instances'),
  cacheStampede('Cache Stampede', 'Mass cache miss causing DB overload'),
  componentCrash('Component Crash', 'Process terminated unexpectedly'),
  
  // Differentiated Failures (New)
  diskIoSaturation('Disk I/O Saturation', 'IOPS limit reached, requests queuing'),
  upstreamTimeout('Upstream Timeout', '504 Gateway Timeout - Upstream too slow'),
  consumerLag('Consumer Lag', 'Processing rate slower than ingestion rate'),
  threadStarvation('Thread Starvation', 'All worker threads busy, new requests blocked');

  final String displayName;
  final String description;

  const FailureType(this.displayName, this.description);
}
