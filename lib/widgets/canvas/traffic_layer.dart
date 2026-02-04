import 'dart:ui'; // For PathMetric
import 'package:flutter/material.dart';
import 'connection_painter_utils.dart'; // Added
import '../../models/traffic_particle.dart';
import '../../models/connection.dart';
import '../../models/component.dart';

class TrafficLayer extends CustomPainter {
  final List<TrafficParticle> particles;
  final List<Connection> connections;
  final List<SystemComponent> components;

  TrafficLayer({
    required this.particles,
    required this.connections,
    required this.components,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    
    // Map for O(1) lookup
    final componentMap = {for (var c in components) c.id: c};
    final connectionMap = {for (var c in connections) c.id: c};
    
    // Cache path metrics for each connection to avoid re-calcing for every particle
    final Map<String, PathMetric?> pathMetricsCache = {};

    for (final particle in particles) {
      final connection = connectionMap[particle.connectionId];
      if (connection == null) continue;

      // Get or compute PathMetric
      if (!pathMetricsCache.containsKey(connection.id)) {
          final startNode = componentMap[connection.sourceId];
          final endNode = componentMap[connection.targetId];
          
          if (startNode != null && endNode != null) {
              final path = ConnectionPathUtils.getPathForConnection(startNode, endNode, connection.type);
              final metrics = path.computeMetrics().toList();
              // Use the longest contour if multiple (should be single for connection)
              if (metrics.isNotEmpty) {
                  pathMetricsCache[connection.id] = metrics.fold<PathMetric>(
                      metrics.first, 
                      (prev, curr) => curr.length > prev.length ? curr : prev
                  );
              } else {
                  pathMetricsCache[connection.id] = null;
              }
          } else {
              pathMetricsCache[connection.id] = null;
          }
      }
      
      final metric = pathMetricsCache[connection.id];
      if (metric == null) continue;

      // Calculate position along the path
      final distance = metric.length * particle.progress;
      final tangent = metric.getTangentForOffset(distance);

      if (tangent != null) {
        paint.color = particle.color;
        canvas.drawCircle(tangent.position, 3.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(TrafficLayer oldDelegate) {
    return true; // Always repaint as particles move every frame
  }
}
