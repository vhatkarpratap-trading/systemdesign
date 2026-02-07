import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:system_design_simulator/models/connection.dart';
import 'package:system_design_simulator/models/component.dart';
import 'package:system_design_simulator/providers/game_provider.dart';
import 'connection_painter_utils.dart'; // Added
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
        final tapPos = details.localPosition;
        // Group to mirror painter offsets
        final Map<String, List<Connection>> groups = {};
        for (final c in widget.canvasState.connections) {
          final key = '${c.sourceId}->${c.targetId}';
          groups.putIfAbsent(key, () => []).add(c);
        }

        for (final entry in groups.entries) {
          final list = entry.value;
          for (int i = 0; i < list.length; i++) {
            final connection = list[i];
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

            // Apply same parallel offset as painter
            final offset = _offsetForPair(source, target, i, list.length);
            start += offset;
            end += offset;
           
           if (_isPointNearLine(tapPos, start, end)) {
             widget.onTap(connection);
             return;
           }
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

  Offset _offsetForPair(SystemComponent source, SystemComponent target, int index, int total) {
    if (total <= 1) return Offset.zero;
    final srcCenter = Offset(source.position.dx + source.size.width / 2, source.position.dy + source.size.height / 2);
    final tgtCenter = Offset(target.position.dx + target.size.width / 2, target.position.dy + target.size.height / 2);
    final dx = tgtCenter.dx - srcCenter.dx;
    final dy = tgtCenter.dy - srcCenter.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return Offset.zero;
    final normal = Offset(-dy / len, dx / len);
    const spread = 14.0;
    final offsetAmount = (index - (total - 1) / 2) * spread;
    return normal * offsetAmount;
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
    // Group connections by oriented pair to offset parallels
    final Map<String, List<Connection>> groups = {};
    for (final c in canvasState.connections) {
      final key = '${c.sourceId}->${c.targetId}';
      groups.putIfAbsent(key, () => []).add(c);
    }

    groups.forEach((_, list) {
      // Count per-protocol within this pair for label context
      final Map<ConnectionProtocol, int> protocolCounts = {};
      for (final c in list) {
        protocolCounts[c.protocol] = (protocolCounts[c.protocol] ?? 0) + 1;
      }

      final sorted = List<Connection>.from(list)
        ..sort((a, b) => a.protocol.index.compareTo(b.protocol.index));

      for (int i = 0; i < sorted.length; i++) {
        final connection = sorted[i];
        final source = canvasState.getComponent(connection.sourceId);
        final target = canvasState.getComponent(connection.targetId);
        if (source == null || target == null) continue;

        _paintConnection(
          canvas,
          source,
          target,
          connection,
          index: i,
          total: sorted.length,
          protocolCount: protocolCounts[connection.protocol] ?? 1,
        );
      }
    });
  }

  void _paintConnection(
    Canvas canvas, 
    SystemComponent source, 
    SystemComponent target, 
    Connection connection, {
    required int index,
    required int total,
    required int protocolCount,
  }) {
    // 1. Determine Color & Style
    final traffic = connection.trafficFlow;
    final protocolColor = _colorForProtocol(connection.protocol);
    final lineColor = _colorAdjustedForTraffic(protocolColor, traffic);
    double strokeWidth = traffic > 0.5 ? 3.0 : 2.4;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    Path path = ConnectionPathUtils.getPathForConnection(source, target, connection.type);

    // Offset parallel lines so multiple protocols are visible
    final offset = _offsetForPair(source, target, index, total);
    if (offset != Offset.zero) {
      path = path.shift(offset);
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

    // 5. Label (user-defined pill only)
    _drawLabel(canvas, path, connection, lineColor, protocolCount);

    // 4. Draw Traffic Packets (Legacy removed in favor of TrafficLayer)
    // if (traffic > 0) {
    //   _drawPackets(canvas, path, lineColor, traffic);
    // }
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

    const arrowSize = 12.0;
    const arrowAngle = math.pi / 5;

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
    
    final pathMetric = pathMetrics.fold<PathMetric>(
        pathMetrics.first, 
        (prev, curr) => curr.length > prev.length ? curr : prev
    ); 
    
    final pathLength = pathMetric.length;

    final packetPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Enhanced Data Flow: 
    // More packets = Higher Traffic
    // 0.1 load = 2 packets
    // 1.0 load = 15 packets (Busy Highway)
    final basePackets = (traffic * 20).ceil();
    final packetCount = math.max(2, basePackets);
    
    for (int i = 0; i < packetCount; i++) {
      // Staggered movement
      final offset = (animationValue + i / packetCount) % 1.0;
      final distance = offset * pathLength;
      final tangent = pathMetric.getTangentForOffset(distance);
      
      if (tangent != null) {
        // Size varies slightly for organic look
        final size = 3.0 + (i % 2); 
        canvas.drawCircle(tangent.position, size, packetPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.canvasState != canvasState;
  }

  Color _colorForProtocol(ConnectionProtocol protocol) {
    switch (protocol) {
      case ConnectionProtocol.http:
        return AppTheme.primary;
      case ConnectionProtocol.grpc:
        return AppTheme.success;
      case ConnectionProtocol.websocket:
        return AppTheme.warning;
      case ConnectionProtocol.tcp:
        return AppTheme.textSecondary;
      case ConnectionProtocol.udp:
        return AppTheme.neonCyan;
      case ConnectionProtocol.custom:
      default:
        return AppTheme.neonMagenta;
    }
  }

  Color _colorAdjustedForTraffic(Color base, double traffic) {
    if (traffic <= 0.0) return base.withValues(alpha: 0.55);
    if (traffic > 0.8) return AppTheme.error;
    if (traffic > 0.6) return AppTheme.warning;
    return base;
  }

  Offset _offsetForPair(SystemComponent source, SystemComponent target, int index, int total) {
    if (total <= 1) return Offset.zero;
    final srcCenter = Offset(source.position.dx + source.size.width / 2, source.position.dy + source.size.height / 2);
    final tgtCenter = Offset(target.position.dx + target.size.width / 2, target.position.dy + target.size.height / 2);
    final dx = tgtCenter.dx - srcCenter.dx;
    final dy = tgtCenter.dy - srcCenter.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return Offset.zero;
    final normal = Offset(-dy / len, dx / len);
    const spread = 14.0;
    final offsetAmount = (index - (total - 1) / 2) * spread;
    return normal * offsetAmount;
  }

  void _drawLabel(Canvas canvas, Path path, Connection connection, Color color, int protocolCount) {
    final label = connection.label;
    if (label == null || label.isEmpty) return; // Only show if user added one
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final midTangent = metric.getTangentForOffset(metric.length / 2);
    if (midTangent == null) return;

    final countPart = protocolCount > 1 ? ' • ${protocolCount} APIs' : '';
    final text = '$label$countPart';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final size = painter.size + Offset(padding.horizontal, padding.vertical);
    final rect = Rect.fromCenter(
      center: midTangent.position,
      width: size.width,
      height: size.height,
    );

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    final bgPaint = Paint()..color = color.withValues(alpha: 0.9);
    canvas.drawRRect(rrect, bgPaint);
    painter.paint(canvas, rect.topLeft + Offset(padding.left, padding.top));
  }
}
