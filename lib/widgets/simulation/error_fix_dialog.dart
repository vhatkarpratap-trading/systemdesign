import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/metrics.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';
import 'diagnostics_dialog.dart';

/// Quick fix dialog for a single error
class ErrorFixDialog extends ConsumerWidget {
  final FailureEvent failure;

  const ErrorFixDialog({
    super.key,
    required this.failure,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvasState = ref.read(canvasProvider);
    final component = canvasState.getComponent(failure.componentId);
    
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.error,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failure.type.displayName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (component != null)
                        Text(
                          component.customName ?? component.type.displayName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Error Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failure.message,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (failure.recommendation.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            failure.recommendation,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Action Buttons
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 12,
              children: [
                // View Full Diagnostics (if component exists)
                if (component != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
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
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('VIEW DETAILS'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                    ),
                  ),
                
                // Apply Fix Button (if fixable)
                if (failure.fixType != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      // Apply fix (updates canvas state, which next simulation tick will pick up)
                      ref.read(canvasProvider.notifier).applyFix(
                        failure.fixType!,
                        failure.componentId,
                      );
                      
                      // Close dialog - simulation continues running
                      Navigator.of(context).pop();
                      
                      // Show confirmation
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Applied: ${failure.fixType!.label}'),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(failure.fixType!.icon, size: 18),
                    label: Text('FIX: ${failure.fixType!.label.toUpperCase()}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: 2,
                    ),
                  )
                else
                  // No fix available - show close button
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textMuted.withValues(alpha: 0.2),
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: 0,
                    ),
                    child: const Text('CLOSE'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
