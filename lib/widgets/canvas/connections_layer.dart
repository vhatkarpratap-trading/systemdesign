import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:system_design_simulator/models/connection.dart';
import 'package:system_design_simulator/models/component.dart';
import 'package:system_design_simulator/providers/game_provider.dart';
import '../../theme/app_theme.dart';

class ConnectionsLayer extends StatefulWidget {
  final CanvasState canvasState;
  final bool isSimulating;
  final Function(Connection) onTap;

  const ConnectionsLayer({
    super.key,
    required this.canvasState,
    required this.isSimulating,
    required this.onTap,
  });

  @override
  State<ConnectionsLayer> createState() => _ConnectionsLayerState();
}

class _ConnectionsLayerState extends State<ConnectionsLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        if (widget.isSimulating) return;
        
        final tapPos = details.localPosition;
        
        // Find tapped connection
        for (final connection in widget.canvasState.connections) {
           final source = widget.canvasState.getComponent(connection.sourceId);
           final target = widget.canvasState.getComponent(connection.targetId);

           if (source == null || target == null) continue;

            // Smart Anchors Logic (Mirrored for Hit Testing)
            final sourceCenter = Offset(source.position.dx + 40, source.position.dy + 32);
            final targetCenter = Offset(target.position.dx + 40, target.position.dy + 32);

            final dx = targetCenter.dx - sourceCenter.dx;
            final dy = targetCenter.dy - sourceCenter.dy;
            final isHorizontal = dx.abs() > dy.abs();

            Offset start;
            Offset end;

            if (isHorizontal) {
              if (dx > 0) {
                // Source -> Target (Left to Right)
                start = Offset(source.position.dx + 80, source.position.dy + 32);
                end = Offset(target.position.dx, target.position.dy + 32);
              } else {
                // Target -> Source (Right to Left)
                start = Offset(source.position.dx, source.position.dy + 32);
                end = Offset(target.position.dx + 80, target.position.dy + 32);
              }
            } else {
              if (dy > 0) {
                // Source Top -> Target Bottom (Downwards)
                start = Offset(source.position.dx + 40, source.position.dy + 64);
                end = Offset(target.position.dx + 40, target.position.dy);
              } else {
                // Source Bottom -> Target Top (Upwards)
                start = Offset(source.position.dx + 40, source.position.dy);
                end = Offset(target.position.dx + 40, target.position.dy + 64);
              }
            }
           
           if (_isPointNearLine(tapPos, start, end)) {
             widget.onTap(connection);
             return;
           }
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ConnectionsPainter(
              canvasState: widget.canvasState,
              animationValue: _controller.value,
            ),
          );
        },
      ),
    );
  }

  bool _isPointNearLine(Offset point, Offset start, Offset end) {
    const threshold = 20.0; // Hit radius
    
    final lengthSquared = (end.dx - start.dx) * (end.dx - start.dx) + 
                          (end.dy - start.dy) * (end.dy - start.dy);
    
    if (lengthSquared == 0) return (point - start).distance < threshold;

    // Project point onto line segment clamped
    final t = ((point.dx - start.dx) * (end.dx - start.dx) + 
               (point.dy - start.dy) * (end.dy - start.dy)) / lengthSquared;
               
    final clampedT = t.clamp(0.0, 1.0);
    
    final projection = Offset(
      start.dx + clampedT * (end.dx - start.dx),
      start.dy + clampedT * (end.dy - start.dy),
    );
    
    return (point - projection).distance < threshold;
  }
}

class _ConnectionsPainter extends CustomPainter {
  final CanvasState canvasState;
  final double animationValue;

  _ConnectionsPainter({
    required this.canvasState,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final connection in canvasState.connections) {
      final source = canvasState.getComponent(connection.sourceId);
      final target = canvasState.getComponent(connection.targetId);

      if (source == null || target == null) continue;

      _paintConnection(canvas, source, target, connection);
    }
  }

  void _paintConnection(
    Canvas canvas, 
    SystemComponent source, 
    SystemComponent target, 
    Connection connection
  ) {
    // 1. Determine Color & Style
    final traffic = connection.trafficFlow;
    Color lineColor;
    double strokeWidth;

    if (traffic > 0.8) {
      lineColor = AppTheme.error;
      strokeWidth = 3.0;
    } else if (traffic > 0.5) {
      lineColor = AppTheme.warning;
      strokeWidth = 2.5;
    } else if (traffic > 0) {
      lineColor = AppTheme.primary;
      strokeWidth = 2.0;
    } else {
      lineColor = AppTheme.textSecondary;
      strokeWidth = 2.5;
    }

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    
    // Smart Anchors: Calculate intersection points based on centers
    final sourceCenter = Offset(
      source.position.dx + source.size.width / 2, 
      source.position.dy + source.size.height / 2
    );
    final targetCenter = Offset(
      target.position.dx + target.size.width / 2, 
      target.position.dy + target.size.height / 2
    );

    final dx = targetCenter.dx - sourceCenter.dx;
    final dy = targetCenter.dy - sourceCenter.dy;
    final isHorizontal = dx.abs() > dy.abs();

    Offset startPoint;
    Offset endPoint;

    if (isHorizontal) {
      if (dx > 0) {
        // Source -> Target (Left to Right)
        startPoint = Offset(source.position.dx + source.size.width, sourceCenter.dy);
        endPoint = Offset(target.position.dx, targetCenter.dy);
      } else {
        // Target -> Source (Right to Left)
        startPoint = Offset(source.position.dx, sourceCenter.dy);
        endPoint = Offset(target.position.dx + target.size.width, targetCenter.dy);
      }
    } else {
      if (dy > 0) {
        // Downwards
        startPoint = Offset(sourceCenter.dx, source.position.dy + source.size.height);
        endPoint = Offset(targetCenter.dx, target.position.dy);
      } else {
        // Upwards
        startPoint = Offset(sourceCenter.dx, source.position.dy);
        endPoint = Offset(targetCenter.dx, target.position.dy + target.size.height);
      }
    }
    
    // Orthogonal Routing (Elbow) with Radius
    final midX = (startPoint.dx + endPoint.dx) / 2;
    final midY = (startPoint.dy + endPoint.dy) / 2;
    
    // Define the sequence of points (Corners)
    List<Offset> points = [startPoint];
    
    if (isHorizontal) {
      if ((dx > 0 && endPoint.dx > startPoint.dx) || (dx < 0 && endPoint.dx < startPoint.dx)) {
        // Standard Elbow: Horizontal -> Vertical -> Horizontal
        points.add(Offset(midX, startPoint.dy));
        points.add(Offset(midX, endPoint.dy));
      } else {
        // Simple 3-segment fallback
         points.add(Offset(midX, startPoint.dy));
         points.add(Offset(midX, endPoint.dy));
      }
    } else {
       // Vertical Routing: Vertical -> Horizontal -> Vertical
       points.add(Offset(startPoint.dx, midY));
       points.add(Offset(endPoint.dx, midY));
    }
    points.add(endPoint);
    
    // 1.5 Filter out duplicate consecutive points to avoid division by zero in path math
    List<Offset> uniquePoints = [points[0]];
    for (int i = 1; i < points.length; i++) {
        if ((points[i] - uniquePoints.last).distance > 0.1) {
            uniquePoints.add(points[i]);
        }
    }
    points = uniquePoints;

    // Build Rounded Path
    const radius = 16.0;
    path.moveTo(points[0].dx, points[0].dy);
    
    if (points.length > 1) {
      for (int i = 1; i < points.length - 1; i++) {
          final p0 = points[i-1];
          final p1 = points[i];
          final p2 = points[i+1];
          
          final v1 = (p1 - p0);
          final len1 = v1.distance;
          final v2 = (p2 - p1);
          final len2 = v2.distance;
          
          if (len1 > 0.1 && len2 > 0.1) {
            // Clamp radius for short segments
            final r = math.min(radius, math.min(len1 / 2, len2 / 2));
            
            final startArc = p1 - (v1 / len1) * r;
            final endArc = p1 + (v2 / len2) * r;
            
            path.lineTo(startArc.dx, startArc.dy);
            path.quadraticBezierTo(p1.dx, p1.dy, endArc.dx, endArc.dy);
          } else {
            path.lineTo(p1.dx, p1.dy);
          }
      }
      path.lineTo(points.last.dx, points.last.dy);
    }

    // 2. Draw Line (Dashed/Solid)
    if (connection.type == ConnectionType.async || 
        connection.type == ConnectionType.replication) {
      _drawDashedLine(canvas, path, paint);
    } else {
      canvas.drawPath(path, paint);
    }

    // 3. Draw Arrows (using Path Metrics for correct angle)
    final metrics = path.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final metric = metrics.last;
      
      // End Arrow (Standard)
      final endTangent = metric.getTangentForOffset(metric.length);
      if (endTangent != null) {
        _drawArrow(canvas, endTangent.position, endTangent.angle, lineColor);
      }

      // Start Arrow (Bidirectional)
      if (connection.direction == ConnectionDirection.bidirectional) {
        final startTangent = metric.getTangentForOffset(0);
        if (startTangent != null) {
           _drawArrow(canvas, startTangent.position, startTangent.angle + math.pi, lineColor);
        }
      }
    }

    // 4. Draw Traffic Packets
    if (traffic > 0) {
      _drawPackets(canvas, path, lineColor, traffic);
    }
  }

  void _drawDashedLine(Canvas canvas, Path path, Paint paint) {
    final Path dashPath = Path();
    double dashWidth = 8.0;
    double dashSpace = 5.0;
    double distance = 0.0;
    
    for (PathMetric pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        dashPath.addPath(
          pathMetric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  void _drawArrow(Canvas canvas, Offset tip, double angle, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowSize = 8.0;
    const arrowAngle = math.pi / 6;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - arrowSize * math.cos(angle - arrowAngle),
        tip.dy - arrowSize * math.sin(angle - arrowAngle),
      )
      ..lineTo(
        tip.dx - arrowSize * math.cos(angle + arrowAngle),
        tip.dy - arrowSize * math.sin(angle + arrowAngle),
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawPackets(Canvas canvas, Path path, Color color, double traffic) {
     final pathMetrics = path.computeMetrics().toList();
    if (pathMetrics.isEmpty) return;
    
    // Check if we need to account for multiple segments in rounded path
    // Just finding the longest metric usually works for the main route
    final pathMetric = pathMetrics.fold<PathMetric>(
        pathMetrics.first, 
        (prev, curr) => curr.length > prev.length ? curr : prev
    ); 
    
    final pathLength = pathMetric.length;

    final packetPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final packetCount = traffic > 0.5 ? 3 : 2;
    
    for (int i = 0; i < packetCount; i++) {
      final offset = (animationValue + i / packetCount) % 1.0;
      final distance = offset * pathLength;
      final tangent = pathMetric.getTangentForOffset(distance);
      
      if (tangent != null) {
        canvas.drawCircle(tangent.position, 3.0, packetPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.canvasState != canvasState;
  }
}
