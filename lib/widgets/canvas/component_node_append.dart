import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final bool isCyberpunk;
  
  const _GlassContainer({
    required this.child,
    this.isCyberpunk = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isCyberpunk 
            ? AppTheme.neonCyan.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCyberpunk 
              ? AppTheme.neonCyan.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.2), 
          width: isCyberpunk ? 1.5 : 0.5
        ),
        boxShadow: isCyberpunk 
            ? [
                BoxShadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : [],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isCyberpunk ? 0.15 : 0.05),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}

class _DistributionLinePainter extends CustomPainter {
  final Color color;
  final int count;
  
  _DistributionLinePainter({required this.color, required this.count});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
      
    // Center point top
    final centerTop = Offset(size.width / 2, 0);
    // Draw vertical down
    canvas.drawLine(centerTop, Offset(centerTop.dx, size.height * 0.5), paint);
    
    // Draw horizontal bar
    final barY = size.height * 0.5;
    
    // Calculate width of distribution
    // 4 shards -> 3 gaps. 
    // We assume the caller sized the canvas to fit the shards
    
    final spacePerShard = size.width / count;
    final startX = spacePerShard / 2;
    final endX = size.width - (spacePerShard / 2);
    
    canvas.drawLine(Offset(startX, barY), Offset(endX, barY), paint);
    
    // Draw verticals down to shards
    for (int i = 0; i < count; i++) {
      final x = startX + (i * spacePerShard);
      canvas.drawLine(Offset(x, barY), Offset(x, size.height), paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
