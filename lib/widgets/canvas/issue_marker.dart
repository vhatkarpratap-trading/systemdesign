import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';
import '../../models/metrics.dart';

class IssueMarker extends StatelessWidget {
  final FailureEvent failure;
  final Offset position;

  const IssueMarker({
    super.key,
    required this.failure,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 12,
      top: position.dy - 60, // Position above the component
      child: Tooltip(
        message: failure.message,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                failure.type.toString().split('.').last.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ).animate(onPlay: (controller) => controller.repeat())
             .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 800.ms, curve: Curves.easeInOut)
             .then()
             .scale(begin: const Offset(1.1, 1.1), end: const Offset(0.9, 0.9), duration: 800.ms, curve: Curves.easeInOut),
            
            const SizedBox(height: 4),
            
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.priority_high,
                color: Colors.white,
                size: 16,
              ),
            ).animate(onPlay: (controller) => controller.repeat())
             .shimmer(duration: 1500.ms, color: Colors.white.withOpacity(0.5))
             .shake(hz: 2, curve: Curves.easeInOut),
          ],
        ),
      ),
    );
  }
}
