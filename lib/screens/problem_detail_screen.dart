import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/problem.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';

class ProblemDetailScreen extends ConsumerWidget {
  final Problem problem;

  const ProblemDetailScreen({super.key, required this.problem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      problem.title,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ).animate().fadeIn().slideY(begin: 0.1),
                    
                    const SizedBox(height: 16),
                    
                    // Difficulty & Tags
                    Row(
                      children: [
                        _DifficultyTag(difficulty: problem.difficulty),
                        const SizedBox(width: 12),
                        _ConstraintTag(
                          icon: Icons.people,
                          label: problem.constraints.dauFormatted,
                        ),
                        const SizedBox(width: 8),
                        _ConstraintTag(
                          icon: Icons.speed,
                          label: problem.constraints.qpsFormatted,
                        ),
                      ],
                    ).animate().fadeIn(delay: 100.ms),

                    const SizedBox(height: 32),

                    // Description
                    _SectionHeader(title: 'Mission Brief', delay: 200.ms),
                    const SizedBox(height: 12),
                    Text(
                      problem.description,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: AppTheme.textSecondary,
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 32),

                    // Objectives / Requirements
                    _SectionHeader(title: 'Key Objectives', delay: 300.ms),
                    const SizedBox(height: 12),
                    _RequirementRow(
                      label: 'Latency (P95)',
                      value: '${problem.constraints.latencySlaMsP95}ms',
                      delay: 300.ms,
                    ),
                    _RequirementRow(
                      label: 'Availability',
                      value: problem.constraints.availabilityString,
                      delay: 350.ms,
                    ),
                    _RequirementRow(
                      label: 'Budget',
                      value: '\$${problem.constraints.budgetPerMonth}/mo',
                      delay: 400.ms,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Tip
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, color: AppTheme.primary),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Tip: Consider using caching layers to reduce database load and improve latency.',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 500.ms),
                  ],
                ),
              ),
            ),
            
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _startLevel(context, ref, problem),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Start System Design',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ).animate().slideY(begin: 1, duration: 400.ms, curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }

  Future<void> _startLevel(BuildContext context, WidgetRef ref, Problem problem) async {
    // Set the current problem
    ref.read(currentProblemProvider.notifier).state = problem;
    
    // Reset simulation
    ref.read(simulationProvider.notifier).reset();
    ref.read(scoreProvider.notifier).state = null;

    // Load progress (or default)
    await ref.read(canvasProvider.notifier).loadForProblem(problem);

    // Navigate to game screen
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const GameScreen(),
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Duration delay;

  const _SectionHeader({required this.title, required this.delay});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: AppTheme.textMuted,
      ),
    ).animate().fadeIn(delay: delay);
  }
}

class _ConstraintTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ConstraintTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DifficultyTag extends StatelessWidget {
  final int difficulty;

  const _DifficultyTag({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      1 => AppTheme.success,
      2 => const Color(0xFF4ADE80),
      3 => AppTheme.warning,
      4 => const Color(0xFFF97316),
      5 => AppTheme.error,
      _ => AppTheme.textMuted,
    };

    final label = switch (difficulty) {
      1 => 'Easy',
      2 => 'Medium',
      3 => 'Hard',
      4 => 'Expert',
      5 => 'Master',
      _ => 'Unknown',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final String label;
  final String value;
  final Duration delay;

  const _RequirementRow({
    required this.label,
    required this.value,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: AppTheme.success.withValues(alpha: 0.8)),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay).slideX(begin: 0.1);
  }
}
