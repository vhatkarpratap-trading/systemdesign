import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:system_design_simulator/models/component.dart';
import 'package:system_design_simulator/models/connection.dart';
import 'package:system_design_simulator/providers/game_provider.dart';
import '../../theme/app_theme.dart';

/// Renders connections between components with elbow paths.
/// Anchors are distributed around all four sides so multiple connectors
/// fan out evenly. Optional lane spreading keeps parallel edges visible.
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
  static const double _laneSpread = 24.0;

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
    final anchors = _buildAnchors(widget.canvasState);

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
            final start = anchors.start[connection.id];
            final end = anchors.end[connection.id];
            if (start == null || end == null) continue;

            // Apply same parallel offset as painter
            final offset = _offsetForPair(start, end, i, list.length);
            final s = start + offset;
            final e = end + offset;

            if (_isPointNearLine(tapPos, s, e)) {
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
            (point.dy - start.dy) * (end.dy - start.dy)) /
        lengthSquared;

    final clampedT = t.clamp(0.0, 1.0);

    final projection = Offset(
      start.dx + clampedT * (end.dx - start.dx),
      start.dy + clampedT * (end.dy - start.dy),
    );

    return (point - projection).distance < threshold;
  }

  Offset _offsetForPair(Offset start, Offset end, int index, int total) {
    if (total <= 1) return Offset.zero;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return Offset.zero;
    final normal = Offset(-dy / len, dx / len);
    final offsetAmount = (index - (total - 1) / 2) * _laneSpread;
    return normal * offsetAmount;
  }
}

class _ConnectionsPainter extends CustomPainter {
  final CanvasState canvasState;
  final double animationValue;
  static const double _laneSpread = 24.0;

  _ConnectionsPainter({
    required this.canvasState,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final anchors = _buildAnchors(canvasState);

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
        final start = anchors.start[connection.id];
        final end = anchors.end[connection.id];
        if (start == null || end == null) continue;

        _paintConnection(
          canvas,
          start,
          end,
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
    Offset start,
    Offset end,
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

    Path path = _buildElbowPath(start, end);

    // Offset parallel lines so multiple protocols are visible
    final offset = _offsetForPair(start, end, index, total);
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

    // 3. Draw Arrows
    final metrics = path.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final metric = metrics.last;

      final endTangent = metric.getTangentForOffset(metric.length);
      if (endTangent != null) {
        _drawArrow(canvas, endTangent.position, endTangent.angle, lineColor);
      }

      if (connection.direction == ConnectionDirection.bidirectional) {
        final startTangent = metric.getTangentForOffset(0);
        if (startTangent != null) {
          _drawArrow(
              canvas, startTangent.position, startTangent.angle + math.pi, lineColor);
        }
      }
    }

    // 5. Label (user-defined pill only)
    _drawLabel(canvas, path, connection, lineColor, protocolCount);
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

  Offset _offsetForPair(Offset start, Offset end, int index, int total) {
    if (total <= 1) return Offset.zero;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return Offset.zero;
    final normal = Offset(-dy / len, dx / len);
    final offsetAmount = (index - (total - 1) / 2) * _laneSpread;
    return normal * offsetAmount;
  }

  void _drawLabel(
      Canvas canvas, Path path, Connection connection, Color color, int protocolCount) {
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

  Path _buildElbowPath(Offset start, Offset end) {
    final path = Path()..moveTo(start.dx, start.dy);
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (dx.abs() > dy.abs()) {
      final midX = (start.dx + end.dx) / 2;
      path.lineTo(midX, start.dy);
      path.lineTo(midX, end.dy);
    } else {
      final midY = (start.dy + end.dy) / 2;
      path.lineTo(start.dx, midY);
      path.lineTo(end.dx, midY);
    }
    path.lineTo(end.dx, end.dy);
    return path;
  }
}

class _Anchors {
  final Map<String, Offset> start;
  final Map<String, Offset> end;
  _Anchors({required this.start, required this.end});
}

_Anchors _buildAnchors(CanvasState state) {
  final Map<String, Offset> start = {};
  final Map<String, Offset> end = {};
  final Map<String, int> sourceCount = {};
  final Map<String, int> targetCount = {};

  final ordered = List<Connection>.from(state.connections)
    ..sort((a, b) {
      final s = a.sourceId.compareTo(b.sourceId);
      if (s != 0) return s;
      final t = a.targetId.compareTo(b.targetId);
      if (t != 0) return t;
      return a.id.compareTo(b.id);
    });

  for (final c in ordered) {
    final source = state.getComponent(c.sourceId);
    final target = state.getComponent(c.targetId);
    if (source == null || target == null) continue;
    start[c.id] = _nextAnchor(source, sourceCount);
    end[c.id] = _nextAnchor(target, targetCount);
  }
  return _Anchors(start: start, end: end);
}

Offset _nextAnchor(SystemComponent c, Map<String, int> map) {
  final idx = map[c.id] ?? 0;
  map[c.id] = idx + 1;
  final w = c.size.width;
  final h = c.size.height;
  final anchors = [
    Offset(c.position.dx + w / 2, c.position.dy), // top
    Offset(c.position.dx + w, c.position.dy + h / 2), // right
    Offset(c.position.dx + w / 2, c.position.dy + h), // bottom
    Offset(c.position.dx, c.position.dy + h / 2), // left
  ];
  return anchors[idx % anchors.length];
}
