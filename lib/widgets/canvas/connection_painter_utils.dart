import 'dart:math' as math;
import 'dart:ui';
import '../../models/component.dart';
import '../../models/connection.dart';

class ConnectionPathUtils {
  static Path getPathForConnection(
    SystemComponent source,
    SystemComponent target,
    ConnectionType type,
  ) {
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
    
    // Filter out duplicate consecutive points
    List<Offset> uniquePoints = [points[0]];
    for (int i = 1; i < points.length; i++) {
        // Use a small epsilon to detect duplicates/very close points
        if ((points[i] - uniquePoints.last).distance > 0.5) {
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

    return path;
  }
}
