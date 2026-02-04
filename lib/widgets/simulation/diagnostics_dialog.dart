import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/metrics.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';

class ComponentDiagnosticsDialog extends ConsumerWidget {
  final String componentId;
  final List<FailureEvent> failures;

  const ComponentDiagnosticsDialog({
    super.key,
    required this.componentId,
    required this.failures,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get component details
    final systemState = ref.read(canvasProvider);
    final component = systemState.getComponent(componentId);
    
    if (component == null) return const SizedBox.shrink();

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.health_and_safety, color: AppTheme.error, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Component Diagnostics',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        component.customName ?? component.type.displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
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
            const SizedBox(height: 24),
            
            if (failures.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No active issues detected.', style: TextStyle(color: AppTheme.textMuted)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: failures.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final failure = failures[index];
                    return _IssueCard(failure: failure);
                  },
                ),
              ),
              
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueCard extends ConsumerWidget {
  final FailureEvent failure;

  const _IssueCard({required this.failure});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: AppTheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failure.type.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (failure.severity > 0.7)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CRITICAL',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            failure.message,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          if (failure.recommendation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Tip: ${failure.recommendation}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
          if (failure.fixType != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Apply fix
                  ref.read(canvasProvider.notifier).applyFix(
                    failure.fixType!, 
                    failure.componentId,
                  );
                  
                  // Reset simulation to verify fix - REMOVED for continuity
                  // ref.read(simulationProvider.notifier).reset();
                  
                  // Close dialog
                  Navigator.of(context).pop();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Applied fix: ${failure.fixType!.label}'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: Icon(failure.fixType!.icon, size: 16),
                label: Text('Fix: ${failure.fixType!.label}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
