import 'package:flutter/material.dart';

class TrafficParticle {
  final String id;
  final String connectionId;
  final double progress; // 0.0 to 1.0
  final double speed; // progress per tick
  final Color color;
  final bool isReverse; // If true, moves from target to source (not used yet, but good for ack)

  TrafficParticle({
    required this.id,
    required this.connectionId,
    required this.progress,
    required this.speed,
    required this.color,
    this.isReverse = false,
  });

  TrafficParticle copyWith({
    String? id,
    String? connectionId,
    double? progress,
    double? speed,
    Color? color,
    bool? isReverse,
  }) {
    return TrafficParticle(
      id: id ?? this.id,
      connectionId: connectionId ?? this.connectionId,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      color: color ?? this.color,
      isReverse: isReverse ?? this.isReverse,
    );
  }
}
