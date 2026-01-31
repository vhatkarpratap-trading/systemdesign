import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/metrics.dart'; // For FailureEvent

class FailureOverlay extends ConsumerWidget {
  const FailureOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simulationState = ref.watch(simulationProvider);
    
    // Only show if in failed state
    if (!simulationState.isFailed) {
      return const SizedBox.shrink();
    }

    final firstFailure = simulationState.failures.isNotEmpty 
        ? simulationState.failures.first 
        : null;

    if (firstFailure == null) return const SizedBox.shrink();

    return Container(
      color: Colors.black.withOpacity(0.85), // High contrast modal background
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.error, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.error.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppTheme.error,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                'System Validation Failed',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      firstFailure.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (firstFailure.recommendation != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tip: ${firstFailure.recommendation}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      // Reset and retry
                      ref.read(simulationProvider.notifier).reset();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: const Text('RETRY'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Just close overlay to allow fixing
                      ref.read(simulationProvider.notifier).stop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: const Text('FIX ISSUE'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
