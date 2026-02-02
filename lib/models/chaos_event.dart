import 'package:flutter/material.dart';

/// Types of chaos events that can be injected into simulation
enum ChaosType {
  trafficSpike('Traffic Spike', Icons.flash_on, '⚡'),
  networkLatency('Network Lag', Icons.schedule, '🐌'),
  networkPartition('Network Partition', Icons.power_off, '🔌'),
  databaseSlowdown('DB Slowdown', Icons.storage, '💾'),
  cacheMissStorm('Cache Invalidation', Icons.delete_sweep, '💥'),
  componentCrash('Random Failure', Icons.cancel, '💀');

  final String label;
  final IconData icon;
  final String emoji;

  const ChaosType(this.label, this.icon, this.emoji);
}

/// Represents an active chaos event affecting the simulation
class ChaosEvent {
  final String id;
  final ChaosType type;
  final DateTime startTime;
  final Duration duration;
  final Map<String, dynamic> parameters;

  const ChaosEvent({
    required this.id,
    required this.type,
    required this.startTime,
    required this.duration,
    this.parameters = const {},
  });

  /// Time remaining before this chaos event expires
  Duration get timeRemaining {
    final elapsed = DateTime.now().difference(startTime);
    return duration - elapsed;
  }

  /// Whether this chaos event is still active
  bool get isActive => timeRemaining.inMilliseconds > 0;

  /// Progress from 0.0 to 1.0
  double get progress {
    final elapsed = DateTime.now().difference(startTime);
    return (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  ChaosEvent copyWith({
    String? id,
    ChaosType? type,
    DateTime? startTime,
    Duration? duration,
    Map<String, dynamic>? parameters,
  }) {
    return ChaosEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      parameters: parameters ?? this.parameters,
    );
  }
}

/// Multipliers applied to simulation based on active chaos events
class ChaosMultipliers {
  final double trafficMultiplier;
  final double latencyMultiplier;
  final double failureRateMultiplier;
  final double databaseLatencyMultiplier;
  final double cacheHitRate;
  final Set<String> disconnectedComponents;

  const ChaosMultipliers({
    this.trafficMultiplier = 1.0,
    this.latencyMultiplier = 1.0,
    this.failureRateMultiplier = 1.0,
    this.databaseLatencyMultiplier = 1.0,
    this.cacheHitRate = 0.95,
    this.disconnectedComponents = const {},
  });

  static const normal = ChaosMultipliers();

  ChaosMultipliers copyWith({
    double? trafficMultiplier,
    double? latencyMultiplier,
    double? failureRateMultiplier,
    double? databaseLatencyMultiplier,
    double? cacheHitRate,
    Set<String>? disconnectedComponents,
  }) {
    return ChaosMultipliers(
      trafficMultiplier: trafficMultiplier ?? this.trafficMultiplier,
      latencyMultiplier: latencyMultiplier ?? this.latencyMultiplier,
      failureRateMultiplier: failureRateMultiplier ?? this.failureRateMultiplier,
      databaseLatencyMultiplier: databaseLatencyMultiplier ?? this.databaseLatencyMultiplier,
      cacheHitRate: cacheHitRate ?? this.cacheHitRate,
      disconnectedComponents: disconnectedComponents ?? this.disconnectedComponents,
    );
  }
}
