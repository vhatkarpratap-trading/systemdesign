import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/problems.dart';
import '../models/problem.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';
import 'problem_detail_screen.dart';

/// Level selection screen
class LevelSelectScreen extends ConsumerWidget {
  const LevelSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Select Level'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Practice Problems',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start with simpler systems and progress to complex architectures',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),

                // Level grid (responsive)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate grid columns based on width
                      final crossAxisCount = constraints.maxWidth >= 800
                          ? 3
                          : constraints.maxWidth >= 500
                              ? 2
                              : 1;

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: crossAxisCount == 1 ? 3.0 : 2.2,
                        ),
                        itemCount: Problems.all.length,
                        itemBuilder: (context, index) {
                          final problem = Problems.all[index];
                          return _LevelCard(
                            problem: problem,
                            index: index,
                            isCompact: crossAxisCount > 1,
                            onTap: problem.isUnlocked
                                ? () => _startLevel(context, ref, problem)
                                : null,
                          )
                              .animate()
                              .fadeIn(delay: Duration(milliseconds: 50 * index))
                              .scale(begin: const Offset(0.95, 0.95));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startLevel(BuildContext context, WidgetRef ref, Problem problem) {
    // Navigate to problem detail screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProblemDetailScreen(problem: problem),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final Problem problem;
  final int index;
  final VoidCallback? onTap;
  final bool isCompact;

  const _LevelCard({
    required this.problem,
    required this.index,
    this.onTap,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked = !problem.isUnlocked;

    return MouseRegion(
      cursor: isLocked ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          decoration: BoxDecoration(
            color: isLocked ? AppTheme.surface.withValues(alpha: 0.5) : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLocked
                  ? AppTheme.textMuted.withValues(alpha: 0.2)
                  : _getDifficultyColor(problem.difficulty).withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: isLocked
                ? null
                : [
                    BoxShadow(
                      color: _getDifficultyColor(problem.difficulty).withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isCompact ? _buildCompactLayout(isLocked) : _buildFullLayout(isLocked),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(bool isLocked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Level number (smaller for compact)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: isLocked
                    ? null
                    : LinearGradient(
                        colors: [
                          _getDifficultyColor(problem.difficulty),
                          _getDifficultyColor(problem.difficulty).withValues(alpha: 0.7),
                        ],
                      ),
                color: isLocked ? AppTheme.surfaceLight : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: isLocked
                    ? Icon(
                        Icons.lock,
                        color: AppTheme.textMuted.withValues(alpha: 0.5),
                        size: 16,
                      )
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                problem.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isLocked ? AppTheme.textMuted : AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Difficulty badge
        _DifficultyBadge(difficulty: problem.difficulty),
      ],
    );
  }

  Widget _buildFullLayout(bool isLocked) {
    return Row(
      children: [
        // Level number
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: isLocked
                ? null
                : LinearGradient(
                    colors: [
                      _getDifficultyColor(problem.difficulty),
                      _getDifficultyColor(problem.difficulty).withValues(alpha: 0.7),
                    ],
                  ),
            color: isLocked ? AppTheme.surfaceLight : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: isLocked
                ? Icon(
                    Icons.lock,
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                    size: 20,
                  )
                : Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),

        const SizedBox(width: 16),

        // Level info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                problem.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isLocked ? AppTheme.textMuted : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                problem.description,
                style: TextStyle(
                  fontSize: 12,
                  color: isLocked
                      ? AppTheme.textMuted.withValues(alpha: 0.5)
                      : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Difficulty
                  _DifficultyBadge(difficulty: problem.difficulty),
                  const SizedBox(width: 8),
                  // DAU
                  _InfoBadge(
                    icon: Icons.people_outline,
                    text: problem.constraints.dauFormatted,
                    isLocked: isLocked,
                  ),
                  const SizedBox(width: 8),
                  // Availability
                  _InfoBadge(
                    icon: Icons.verified_outlined,
                    text: problem.constraints.availabilityString,
                    isLocked: isLocked,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Arrow
        Icon(
          Icons.chevron_right,
          color: isLocked ? AppTheme.textMuted.withValues(alpha: 0.3) : AppTheme.primary,
        ),
      ],
    );
  }

  Color _getDifficultyColor(int difficulty) {
    return switch (difficulty) {
      1 => AppTheme.success,
      2 => const Color(0xFF4ADE80),
      3 => AppTheme.warning,
      4 => const Color(0xFFF97316),
      5 => AppTheme.error,
      _ => AppTheme.textMuted,
    };
  }
}

class _DifficultyBadge extends StatelessWidget {
  final int difficulty;

  const _DifficultyBadge({required this.difficulty});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(
            difficulty,
            (i) => Icon(
              Icons.star,
              size: 10,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isLocked;

  const _InfoBadge({
    required this.icon,
    required this.text,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: isLocked ? AppTheme.textMuted.withValues(alpha: 0.5) : AppTheme.textSecondary,
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: isLocked ? AppTheme.textMuted.withValues(alpha: 0.5) : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
