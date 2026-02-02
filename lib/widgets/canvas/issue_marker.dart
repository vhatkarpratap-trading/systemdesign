import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/metrics.dart';
import '../simulation/diagnostics_dialog.dart';

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
            
            // Fix Button
            if (failure.fixType != null) ...[
              const SizedBox(height: 4),
              Consumer(
                builder: (context, ref, child) {
                  return GestureDetector(
                    onTap: () {
                      // Open diagnostics dialog with all failures for this component
                      final simState = ref.read(simulationProvider);
                      final componentFailures = simState.failures
                          .where((f) => f.componentId == failure.componentId)
                          .toList();
                          
                      showDialog(
                        context: context,
                        builder: (context) => ComponentDiagnosticsDialog(
                          componentId: failure.componentId,
                          failures: componentFailures,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            failure.fixType!.icon, 
                            size: 10, 
                            color: Colors.white
                          ),
                          const SizedBox(width: 4),
                          Text(
                            failure.fixType!.label.length > 10 
                              ? 'FIX' 
                              : 'FIX: ${failure.fixType!.label}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate()
                   .fade(delay: 500.ms)
                   .slideY(begin: 0.5, end: 0);
                }
              ),
            ],
          ],
        ),
      ),
    );
  }
}
