import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class GuideOverlay extends StatelessWidget {
  final VoidCallback onDismiss;

  const GuideOverlay({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {}, // Prevent tap on card from dismissing
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: AppTheme.glassDecoration(
              opacity: 0.95,
              borderRadius: 16,
            ).copyWith(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school, color: AppTheme.primary, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      'Canvas Guide',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onDismiss,
                      icon: const Icon(Icons.close, size: 20),
                      color: AppTheme.textMuted,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _GuideItem(
                  icon: Icons.drag_indicator,
                  title: 'Drag & Drop',
                  description: 'Drag components from the "Toolbox" at the bottom.',
                ),
                const SizedBox(height: 16),
                _GuideItem(
                  icon: Icons.gesture,
                  title: 'Connect',
                  description: 'Tap a component, then tap another to link them.',
                ),
                const SizedBox(height: 16),
                _GuideItem(
                  icon: Icons.edit,
                  title: 'Rename',
                  description: 'Double-tap any component to give it a custom name.',
                ),
                const SizedBox(height: 16),
                _GuideItem(
                  icon: Icons.open_with,
                  title: 'Navigate',
                  description: 'Pan with one finger, pinch to zoom.',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _GuideItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
