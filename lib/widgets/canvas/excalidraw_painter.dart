import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';

/// Renders Excalidraw elements with a hand-drawn, "sketchy" feel.
class ExcalidrawPainter extends CustomPainter {
  final List<Map<String, dynamic>> elements;
  final Color? overrideColor;
  final bool scaleToFit;
  final bool forceSolidFill;

  ExcalidrawPainter({
    required this.elements,
    this.overrideColor,
    this.scaleToFit = false,
    this.forceSolidFill = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (elements.isEmpty) return;

    if (scaleToFit) {
      // 1. Calculate Bounds
      double minX = double.infinity;
      double minY = double.infinity;
      double maxX = double.negativeInfinity;
      double maxY = double.negativeInfinity;

      for (final el in elements) {
        final x = (el['x'] as num).toDouble();
        final y = (el['y'] as num).toDouble();
        final w = (el['width'] as num).toDouble();
        final h = (el['height'] as num).toDouble();
  
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x + w > maxX) maxX = x + w;
        if (y + h > maxY) maxY = y + h;
        
        // Check points for precise bounds if line
        if ((el['type'] == 'line' || el['type'] == 'arrow') && el['points'] != null) {
          final points = (el['points'] as List).cast<List>();
          for (final p in points) {
            final px = x + (p[0] as num).toDouble();
            final py = y + (p[1] as num).toDouble();
            if (px < minX) minX = px;
            if (px > maxX) maxX = px;
            if (py < minY) minY = py;
            if (py > maxY) maxY = py;
          }
        }
      }
      
      if (minX.isFinite) {
          final contentWidth = maxX - minX;
          final contentHeight = maxY - minY;
      
          if (contentWidth > 0 && contentHeight > 0) {
            final scaleX = size.width / contentWidth;
            final scaleY = size.height / contentHeight;
            // Use uniform scaling to avoid distortion similar to BoxFit.contain
            // But here we want to FILL the area roughly
            
            canvas.save();
            canvas.scale(scaleX, scaleY);
            canvas.translate(-minX, -minY);
            
            for (final el in elements) {
              _drawElement(canvas, el);
            }
            canvas.restore();
            return;
          }
      }
    }

    // Default legacy behavior (if not scaled)
    // 1. Calculate Bounds (Repeated but necessary if we fall through or for centering)
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final el in elements) {
      final x = (el['x'] as num).toDouble();
      final y = (el['y'] as num).toDouble();
      final w = (el['width'] as num).toDouble();
      final h = (el['height'] as num).toDouble();

      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x + w > maxX) maxX = x + w;
      if (y + h > maxY) maxY = y + h;
      
      // Check points for precise bounds if line
      if ((el['type'] == 'line' || el['type'] == 'arrow') && el['points'] != null) {
        final points = (el['points'] as List).cast<List>();
        for (final p in points) {
          final px = x + (p[0] as num).toDouble();
          final py = y + (p[1] as num).toDouble();
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
        }
      }
    }

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;

    if (contentWidth <= 0 || contentHeight <= 0) return;

    // 2. Scale to Fit Target Size
    final scaleX = size.width / contentWidth;
    final scaleY = size.height / contentHeight;
    final scale = math.min(scaleX, scaleY) * 0.95; // 95% fit for padding

    // Center alignment
    final offsetX = (size.width - (contentWidth * scale)) / 2;
    final offsetY = (size.height - (contentHeight * scale)) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    canvas.translate(-minX, -minY);

    // 3. Draw Elements
    for (final el in elements) {
      _drawElement(canvas, el);
    }

    canvas.restore();
  }

  void _drawElement(Canvas canvas, Map<String, dynamic> el) {
    final type = el['type'];
    final strokeColorHex = el['strokeColor'] as String? ?? '#000000';
    final bgColorHex = el['backgroundColor'] as String? ?? 'transparent';
    final rawFillStyle = el['fillStyle'] as String? ?? 'solid';
    final fillStyle = forceSolidFill ? 'solid' : rawFillStyle;
    
    final strokeColor = overrideColor ?? _parseColor(strokeColorHex);
    final bgColor = _parseColor(bgColorHex);

    final paintStroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (el['strokeWidth'] as num?)?.toDouble() ?? 2.0;

    final x = (el['x'] as num).toDouble();
    final y = (el['y'] as num).toDouble();
    final w = (el['width'] as num).toDouble();
    final h = (el['height'] as num).toDouble();

    switch (type) {
      case 'rectangle':
        final rect = Rect.fromLTWH(x, y, w, h);
        if (bgColor != Colors.transparent) _drawHachureFill(canvas, rect, bgColor, fillStyle);
        _drawSketchyRect(canvas, rect, paintStroke);
        break;

      case 'ellipse':
        final rect = Rect.fromLTWH(x, y, w, h);
        if (bgColor != Colors.transparent) _drawHachureFill(canvas, rect, bgColor, fillStyle);
        _drawSketchyEllipse(canvas, rect, paintStroke);
        break;

      case 'diamond':
        final rect = Rect.fromLTWH(x, y, w, h);
        if (bgColor != Colors.transparent) _drawHachureFill(canvas, rect, bgColor, fillStyle);
        _drawSketchyDiamond(canvas, rect, paintStroke);
        break;

      case 'arrow':
      case 'line':
        if (el['points'] != null) {
          final points = (el['points'] as List).cast<List>();
          if (points.isNotEmpty) {
             final List<Offset> sketchPoints = points.map((p) => Offset(x + (p[0] as num).toDouble(), y + (p[1] as num).toDouble())).toList();
             _drawSketchyPolyline(canvas, sketchPoints, paintStroke);

             if (el['endArrowhead'] == 'arrow' && points.length >= 2) {
                final p1 = points[points.length - 2];
                final p2 = points.last;
                _drawSketchyArrowhead(canvas, x + p1[0], y + p1[1], x + p2[0], y + p2[1], paintStroke.color);
             }
          }
        }
        break;
      
      case 'text':
        final text = el['text'] as String? ?? '';
        final fontSize = (el['fontSize'] as num?)?.toDouble() ?? 16.0;
        _drawSketchyText(canvas, x, y, text, fontSize, paintStroke.color);
        break;
    }
  }

  void _drawSketchyRect(Canvas canvas, Rect rect, Paint paint) {
    _drawSketchyPolyline(canvas, [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
      rect.topLeft,
    ], paint);
  }

  void _drawSketchyEllipse(Canvas canvas, Rect rect, Paint paint) {
    final random = math.Random(rect.topLeft.hashCode);
    for (int i = 0; i < 2; i++) {
      final jitter = (random.nextDouble() - 0.5) * 3.0; // Increased jitter
      final jitterRect = rect.inflate(jitter);
      canvas.drawOval(jitterRect, paint);
    }
  }

  void _drawSketchyDiamond(Canvas canvas, Rect rect, Paint paint) {
    final x = rect.left;
    final y = rect.top;
    final w = rect.width;
    final h = rect.height;
    
    _drawSketchyPolyline(canvas, [
      Offset(x + w / 2, y),
      Offset(x + w, y + h / 2),
      Offset(x + w / 2, y + h),
      Offset(x, y + h / 2),
      Offset(x + w / 2, y),
    ], paint);
  }

  void _drawSketchyPolyline(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    
    final random = math.Random(points.first.hashCode);
    
    // Draw twice for the sketchy effect
    for (int i = 0; i < 2; i++) {
      final path = Path();
      path.moveTo(
        points[0].dx + (random.nextDouble() - 0.5) * 3.0,
        points[0].dy + (random.nextDouble() - 0.5) * 3.0,
      );
      
      for (int j = 1; j < points.length; j++) {
        final p1 = points[j - 1];
        final p2 = points[j];
        
        final dist = (p2 - p1).distance;
        if (dist > 10) { // More points for smoother wobble
          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          final jitterX = (random.nextDouble() - 0.5) * 3.0;
          final jitterY = (random.nextDouble() - 0.5) * 3.0;
          path.lineTo(mid.dx + jitterX, mid.dy + jitterY);
        }
        
        path.lineTo(
          p2.dx + (random.nextDouble() - 0.5) * 3.0,
          p2.dy + (random.nextDouble() - 0.5) * 3.0,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawSketchyArrowhead(Canvas canvas, double x1, double y1, double x2, double y2, Color color) {
    const double arrowSize = 14.0; // Slightly larger
    final double angle = math.atan2(y2 - y1, x2 - x1);
    final random = math.Random((x2 + y2).toInt());
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 // Thicker
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 2; i++) {
        final jitter = (random.nextDouble() - 0.5) * 3.0;
        final path = Path();
        path.moveTo(x2, y2);
        path.lineTo(
            x2 - arrowSize * math.cos(angle - math.pi / 6) + jitter, 
            y2 - arrowSize * math.sin(angle - math.pi / 6) + jitter
        );
        path.moveTo(x2, y2);
        path.lineTo(
            x2 - arrowSize * math.cos(angle + math.pi / 6) + jitter, 
            y2 - arrowSize * math.sin(angle + math.pi / 6) + jitter
        );
        canvas.drawPath(path, paint);
    }
  }

  void _drawHachureFill(Canvas canvas, Rect rect, Color color, String fillStyle) {
    if (fillStyle == 'solid') {
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.3));
      return;
    }
    
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4) // More opaque
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5; // Thicker lines

    final double step = 10.0; // Wider spacing for cleaner look
    final random = math.Random(rect.topLeft.hashCode);

    canvas.save();
    canvas.clipRect(rect);
    
    for (double i = -rect.height; i < rect.width; i += step) {
      final jitter = (random.nextDouble() - 0.5) * 3.0;
      canvas.drawLine(
        Offset(rect.left + i + jitter, rect.top),
        Offset(rect.left + i + rect.height + jitter, rect.bottom),
        paint,
      );
    }
    
    if (fillStyle == 'cross-hatch') {
        for (double i = 0; i < rect.width + rect.height; i += step) {
          final jitter = (random.nextDouble() - 0.5) * 3.0;
          canvas.drawLine(
            Offset(rect.left + i + jitter, rect.bottom),
            Offset(rect.left + i - rect.height + jitter, rect.top),
            paint,
          );
        }
    }
    canvas.restore();
  }

  void _drawSketchyText(Canvas canvas, double x, double y, String text, double fontSize, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.architectsDaughter(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(0.015 * (math.Random(text.hashCode).nextDouble() - 0.5)); 
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  Color _parseColor(String hex) {
    if (hex == 'transparent') return Colors.transparent;
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  @override
  bool shouldRepaint(covariant ExcalidrawPainter oldDelegate) {
    return oldDelegate.elements != elements || oldDelegate.overrideColor != overrideColor;
  }
}
