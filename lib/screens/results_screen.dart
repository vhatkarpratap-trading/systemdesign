import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';
import '../models/score.dart';
import '../theme/app_theme.dart';
import 'level_select_screen.dart';

/// Results screen shown after simulation completes
class ResultsScreen extends ConsumerWidget {
  final VoidCallback? onClose;
  const ResultsScreen({super.key, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problem = ref.watch(currentProblemProvider);
    final score = ref.watch(scoreProvider);
    final simState = ref.watch(simulationProvider);

    // If failed, we don't need a score to show the screen
    if (simState.isFailed) {
      return _buildFailureScreen(context, ref, simState.failures);
    }

    if (score == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final passed = score.overall >= 60;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // Result icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: passed
                      ? const LinearGradient(
                          colors: [AppTheme.success, Color(0xFF059669)],
                        )
                      : const LinearGradient(
                          colors: [AppTheme.error, Color(0xFFDC2626)],
                        ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (passed ? AppTheme.success : AppTheme.error)
                          .withValues(alpha: 0.4),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  passed ? Icons.check : Icons.close,
                  size: 48,
                  color: Colors.white,
                ),
              )
                  .animate()
                  .scale(begin: const Offset(0, 0), duration: 400.ms, curve: Curves.elasticOut),

              const SizedBox(height: 24),

              // Title
              Text(
                passed ? 'Great Job!' : 'Keep Trying!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: passed ? AppTheme.success : AppTheme.error,
                ),
              )
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .slideY(begin: 0.2),

              const SizedBox(height: 8),

              Text(
                problem.title,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              )
                  .animate()
                  .fadeIn(delay: 300.ms),

              const SizedBox(height: 40),

              // Overall score circle
              _ScoreCircle(score: score)
                  .animate()
                  .fadeIn(delay: 400.ms)
                  .scale(begin: const Offset(0.8, 0.8)),

              const SizedBox(height: 32),

              // Score breakdown
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppTheme.glassDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Score Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ScoreBar(
                      label: 'Scalability',
                      value: score.scalability,
                      icon: Icons.trending_up,
                      delay: 500,
                    ),
                    const SizedBox(height: 12),
                    _ScoreBar(
                      label: 'Reliability',
                      value: score.reliability,
                      icon: Icons.security,
                      delay: 600,
                    ),
                    const SizedBox(height: 12),
                    _ScoreBar(
                      label: 'Performance',
                      value: score.performance,
                      icon: Icons.speed,
                      delay: 700,
                    ),
                    const SizedBox(height: 12),
                    _ScoreBar(
                      label: 'Cost Efficiency',
                      value: score.cost,
                      icon: Icons.attach_money,
                      delay: 800,
                    ),
                    const SizedBox(height: 12),
                    _ScoreBar(
                      label: 'Simplicity',
                      value: score.simplicity,
                      icon: Icons.auto_awesome,
                      delay: 900,
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: 500.ms)
                  .slideY(begin: 0.1),

              const SizedBox(height: 24),

              // SLA & Budget Verification Checklist
              _ConstraintsChecklist(
                problem: problem,
                metrics: simState.globalMetrics,
                score: score,
              )
                  .animate()
                  .fadeIn(delay: 800.ms)
                  .slideY(begin: 0.1),

              // Failures summary
              if (simState.failures.isNotEmpty) ...[
                const SizedBox(height: 24),
                _FailuresSummary(failures: simState.failures)
                    .animate()
                    .fadeIn(delay: 1000.ms),
              ],

              const SizedBox(height: 32),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Reset and try again
                        ref.read(canvasProvider.notifier).clearCanvas();
                        ref.read(simulationProvider.notifier).reset();
                        ref.read(scoreProvider.notifier).state = null;
                        if (onClose != null) {
                          onClose!();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LevelSelectScreen(),
                          ),
                          (route) => route.isFirst,
                        );
                      },
                      icon: const Icon(Icons.list),
                      label: const Text('All Levels'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(delay: 1100.ms)
                  .slideY(begin: 0.2),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildFailureScreen(BuildContext context, WidgetRef ref, List<dynamic> failures) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Error Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.error, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.error.withValues(alpha: 0.4),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppTheme.error,
                  )
                ).animate().scale(curve: Curves.elasticOut, duration: 500.ms),

                const SizedBox(height: 32),

                // Title
                Text(
                  'System Validation Failed',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 16),
                
                Text(
                  'Critical issues detected in your design.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 48),

                // Failure List
                _FailuresSummary(failures: failures)
                    .animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

                const SizedBox(height: 48),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                         ref.read(canvasProvider.notifier).clearCanvas();
                         ref.read(simulationProvider.notifier).reset();
                         Navigator.pop(context);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset Level'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                         // Go back to fix
                         ref.read(simulationProvider.notifier).reset();
                         Navigator.pop(context);
                      },
                      icon: const Icon(Icons.build),
                      label: const Text('Fix Issues'),
                      style: ElevatedButton.styleFrom(
                         backgroundColor: AppTheme.primary,
                         foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Animated score circle
class _ScoreCircle extends StatelessWidget {
  final dynamic score;

  const _ScoreCircle({required this.score});

  @override
  Widget build(BuildContext context) {
    final overall = score.overall;
    final grade = score.grade;
    final stars = score.stars;

    Color gradeColor;
    if (overall >= 80) {
      gradeColor = AppTheme.success;
    } else if (overall >= 60) {
      gradeColor = AppTheme.warning;
    } else {
      gradeColor = AppTheme.error;
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Background circle
            SizedBox(
              width: 160,
              height: 160,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: overall / 100),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return CircularProgressIndicator(
                    value: value,
                    strokeWidth: 12,
                    backgroundColor: AppTheme.surfaceLight,
                    valueColor: AlwaysStoppedAnimation(gradeColor),
                  );
                },
              ),
            ),
            // Grade letter
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  grade,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: gradeColor,
                  ),
                ),
                Text(
                  '${overall.toInt()}/100',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Stars
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            return Icon(
              i < stars ? Icons.star : Icons.star_border,
              color: i < stars ? AppTheme.warning : AppTheme.textMuted,
              size: 28,
            )
                .animate()
                .fadeIn(delay: Duration(milliseconds: 800 + i * 100))
                .scale(begin: const Offset(0, 0));
          }),
        ),
      ],
    );
  }
}

/// Score bar for breakdown
class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final int delay;

  const _ScoreBar({
    required this.label,
    required this.value,
    required this.icon,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    Color barColor;
    if (value >= 80) {
      barColor = AppTheme.success;
    } else if (value >= 60) {
      barColor = AppTheme.warning;
    } else {
      barColor = AppTheme.error;
    }

    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value / 100),
              duration: Duration(milliseconds: 1000 + delay),
              curve: Curves.easeOutCubic,
              builder: (context, animValue, child) {
                return LinearProgressIndicator(
                  value: animValue,
                  backgroundColor: AppTheme.surfaceLight,
                  valueColor: AlwaysStoppedAnimation(barColor),
                  minHeight: 8,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 40,
          child: Text(
            '${value.toInt()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: barColor,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Failures summary card
class _FailuresSummary extends StatelessWidget {
  final List<dynamic> failures;

  const _FailuresSummary({required this.failures});

  @override
  Widget build(BuildContext context) {
    // Group failures by type
    final failureGroups = <String, List<dynamic>>{};
    for (final f in failures) {
      final type = f.type.displayName;
      failureGroups[type] ??= [];
      failureGroups[type]!.add(f);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: AppTheme.error, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Issues Detected',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${failures.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...failureGroups.entries.take(4).map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '×${entry.value.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }),

          
          if (failures.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...failures.where((f) => f.fixType != null).take(2).map((f) {
              return Padding(
                 padding: const EdgeInsets.only(bottom: 8),
                 child: Consumer(
                   builder: (context, ref, _) {
                     return ElevatedButton.icon(
                       onPressed: () {
                         ref.read(canvasProvider.notifier).applyFix(f.fixType!, f.componentId);
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text('Applied fix: ${f.fixType!.label}')),
                         );
                       },
                       icon: Icon(f.fixType!.icon, size: 16),
                       label: Text('Fix: ${f.fixType!.label}'),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: AppTheme.primary,
                         foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                         minimumSize: const Size(0, 36),
                       ),
                     );
                   }
                 ),
              );
            }),
          ]
        ],
      ),
    );
  }

}

/// SLA & Budget Verification Checklist
class _ConstraintsChecklist extends StatelessWidget {
  final dynamic problem;
  final dynamic metrics;
  final Score score;

  const _ConstraintsChecklist({
    required this.problem,
    required this.metrics,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SLA & Budget Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          
          // DAU / QPS Target
          _ConstraintItem(
            label: 'Scale (DAU / QPS)',
            value: '${problem.constraints.dauFormatted} / ${problem.constraints.qpsFormatted}',
            current: '${metrics.totalRps} RPS',
            isPassed: score.scalability >= 90,
            icon: Icons.people_outline,
          ),
          
          const Divider(height: 24, color: AppTheme.border),
          
          // Latency SLA
          _ConstraintItem(
            label: 'Latency SLA (P95)',
            value: '< ${problem.constraints.latencySlaMsP95}ms',
            current: '${metrics.p95LatencyMs.toInt()}ms',
            isPassed: score.performance >= 80,
            icon: Icons.timer_outlined,
          ),
          
          const Divider(height: 24, color: AppTheme.border),
          
          // Availability SLA
          _ConstraintItem(
            label: 'Availability SLA',
            value: problem.constraints.availabilityString,
            current: metrics.availabilityString,
            isPassed: score.reliability >= 80,
            icon: Icons.check_circle_outline,
          ),
          
          const Divider(height: 24, color: AppTheme.border),
          
          // Budget Constraint
          _ConstraintItem(
            label: 'Monthly Budget',
            value: '\$${problem.constraints.budgetPerMonth}',
            current: metrics.costString,
            isPassed: score.cost >= 70,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
      ),
    );
  }
}

class _ConstraintItem extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final bool isPassed;
  final IconData icon;

  const _ConstraintItem({
    required this.label,
    required this.value,
    required this.current,
    required this.isPassed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isPassed ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isPassed ? AppTheme.success : AppTheme.error,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Target: $value',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              current,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isPassed ? AppTheme.success : AppTheme.error,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPassed ? Icons.check_circle : Icons.cancel,
                  size: 12,
                  color: isPassed ? AppTheme.success : AppTheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  isPassed ? 'PASSED' : 'FAILED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isPassed ? AppTheme.success : AppTheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
