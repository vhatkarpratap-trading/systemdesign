import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/component.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';

/// Toolbox display mode
enum ToolboxMode {
  horizontal, // Bottom bar on mobile
  sidebar,    // Side panel on web/desktop
}

/// Minimal component toolbox with responsive layout support
class ComponentToolbox extends ConsumerWidget {
  final ToolboxMode mode;

  const ComponentToolbox({
    super.key,
    this.mode = ToolboxMode.horizontal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(toolboxVisibleProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    if (!isVisible && mode == ToolboxMode.horizontal) {
      return const SizedBox.shrink();
    }

    final components = ComponentType.values.where((type) {
      if (selectedCategory == null) return true;
      return type.category == selectedCategory;
    }).toList();

    if (mode == ToolboxMode.sidebar) {
      return _SidebarToolbox(
        components: components,
        selectedCategory: selectedCategory,
      );
    }

    return _HorizontalToolbox(
      components: components,
      selectedCategory: selectedCategory,
    );
  }
}

/// Horizontal toolbox for mobile (bottom bar)
class _HorizontalToolbox extends ConsumerWidget {
  final List<ComponentType> components;
  final ComponentCategory? selectedCategory;

  const _HorizontalToolbox({
    required this.components,
    required this.selectedCategory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
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
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                const Text(
                  'Components',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    ref.read(toolboxVisibleProvider.notifier).state = false;
                  },
                  icon: const Icon(Icons.close, size: 16),
                  color: AppTheme.textMuted,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // Category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: ComponentCategory.values.map((category) {
                final isSelected = selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () {
                      ref.read(selectedCategoryProvider.notifier).state =
                          isSelected ? null : category;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        category.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // Components
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: components.length,
              itemBuilder: (context, index) {
                final type = components[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: LongPressDraggable<ComponentType>(
                    data: type,
                    delay: const Duration(milliseconds: 100),
                    feedback: _DragFeedback(type: type),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: _ComponentChip(type: type),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        ref.read(addComponentTriggerProvider.notifier).state = type;
                      },
                      child: _ComponentChip(type: type),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Sidebar toolbox for web/desktop
class _SidebarToolbox extends ConsumerWidget {
  final List<ComponentType> components;
  final ComponentCategory? selectedCategory;

  const _SidebarToolbox({
    required this.components,
    required this.selectedCategory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          right: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.widgets, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Components',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.border),

          // Category chips (wrap layout for sidebar)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ComponentCategory.values.map((category) {
                final isSelected = selectedCategory == category;
                return GestureDetector(
                  onTap: () {
                    ref.read(selectedCategoryProvider.notifier).state =
                        isSelected ? null : category;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      category.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1, color: AppTheme.border),

          // Components grid (scrollable)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: components.length,
              itemBuilder: (context, index) {
                final type = components[index];
                return Draggable<ComponentType>(
                  data: type,
                  feedback: _DragFeedback(type: type),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: _SidebarComponentTile(type: type),
                  ),
                  child: GestureDetector(
                    onTap: () {
                      ref.read(addComponentTriggerProvider.notifier).state = type;
                    },
                    child: _SidebarComponentTile(type: type),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Component tile for sidebar mode
class _SidebarComponentTile extends StatelessWidget {
  final ComponentType type;

  const _SidebarComponentTile({required this.type});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type.icon,
              color: type.color,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              type.displayName,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentChip extends StatelessWidget {
  final ComponentType type;

  const _ComponentChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type.icon,
            color: type.color,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            type.displayName,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final ComponentType type;

  const _DragFeedback({required this.type});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 80,
        height: 64,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: type.color, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: type.color.withValues(alpha: 0.3),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(type.icon, color: type.color, size: 24),
            const SizedBox(height: 4),
            Text(
              type.displayName,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FAB to show toolbox
class ToolboxToggle extends ConsumerWidget {
  const ToolboxToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(toolboxVisibleProvider);

    if (isVisible) return const SizedBox.shrink();

    return FloatingActionButton.small(
      onPressed: () {
        ref.read(toolboxVisibleProvider.notifier).state = true;
      },
      backgroundColor: AppTheme.primary,
      child: const Icon(Icons.add, color: Colors.white, size: 20),
    );
  }
}
