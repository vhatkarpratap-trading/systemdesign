import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/component.dart';
import '../../providers/game_provider.dart';
import '../../simulation/design_validator.dart';
import '../../theme/app_theme.dart';

/// Panel showing hints and validation status
class HintsPanel extends ConsumerWidget {
  const HintsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problem = ref.watch(currentProblemProvider);
    final canvasState = ref.watch(canvasProvider);
    final simState = ref.watch(simulationProvider);

    // Validate current design
    final validation = DesignValidator.validate(
      components: canvasState.components,
      connections: canvasState.connections,
      problem: problem,
    );

    return Container(
      width: 280,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  validation.isValid
                      ? Icons.check_circle_outline
                      : Icons.lightbulb_outline,
                  color: validation.isValid ? AppTheme.success : AppTheme.warning,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    validation.isValid ? 'Optimized' : 'Design Hints',
                    style: TextStyle(
                      color: validation.isValid ? AppTheme.success : AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                // Progress indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _scoreColor(validation.score).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${validation.score}%',
                    style: TextStyle(
                      color: _scoreColor(validation.score),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, color: AppTheme.border),

          // Issues
          if (validation.issues.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Issues',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...validation.issues.take(3).map((issue) => _IssueRow(issue: issue)),
          ],

          // Problem hints
          if (validation.isValid || validation.issues.length < 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Solution Hints',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...problem.hints.take(2).map((hint) => _HintRow(hint: hint)),
          ],

          // Optimal components hint
          if (!simState.isRunning) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Recommended',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _OptimalComponentsRow(
              optimalTypes: problem.optimalComponents,
              currentComponents: canvasState.components,
            ),
          ],
          
          // Auto-Solve Button (Development/Help)
          if (!validation.isValid && !simState.isRunning) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                     ref.read(canvasProvider.notifier).loadSolution(problem);
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 14),
                  label: const Text('Auto-Fix Design'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppTheme.success;
    if (score >= 50) return AppTheme.warning;
    return AppTheme.error;
  }
}

class _IssueRow extends StatelessWidget {
  final ValidationIssue issue;

  const _IssueRow({required this.issue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            DesignValidator.severityIcon(issue.severity),
            color: DesignValidator.severityColor(issue.severity),
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  issue.description,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final String hint;

  const _HintRow({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            color: AppTheme.primary.withValues(alpha: 0.7),
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptimalComponentsRow extends StatelessWidget {
  final List<String> optimalTypes;
  final List<SystemComponent> currentComponents;

  const _OptimalComponentsRow({
    required this.optimalTypes,
    required this.currentComponents,
  });

  @override
  Widget build(BuildContext context) {
    final currentTypes = currentComponents.map((c) => c.type.name).toSet();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: optimalTypes.map((typeName) {
          final hasIt = currentTypes.contains(typeName);
          final type = ComponentType.values.firstWhere(
            (t) => t.name == typeName,
            orElse: () => ComponentType.appServer,
          );
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: hasIt
                  ? AppTheme.success.withValues(alpha: 0.15)
                  : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasIt ? AppTheme.success : AppTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type.icon,
                  size: 10,
                  color: hasIt ? AppTheme.success : AppTheme.textMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  type.displayName,
                  style: TextStyle(
                    fontSize: 9,
                    color: hasIt ? AppTheme.success : AppTheme.textMuted,
                    fontWeight: hasIt ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (hasIt) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.check, size: 10, color: AppTheme.success),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Compact hints toggle button
class HintsToggle extends ConsumerWidget {
  final VoidCallback onTap;
  final bool isExpanded;

  const HintsToggle({
    super.key,
    required this.onTap,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isExpanded ? Icons.close : Icons.lightbulb_outline,
              color: AppTheme.warning,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              isExpanded ? 'Close' : 'Hints',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
