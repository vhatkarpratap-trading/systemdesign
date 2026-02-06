import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';

/// Floating toolbar for drawing tools (mimics Excalidraw etc.)
class DrawingToolbar extends ConsumerWidget {
  final CanvasTool? activeTool;
  final Function(CanvasTool)? onToolChanged;

  const DrawingToolbar({
    super.key,
    this.activeTool,
    this.onToolChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTool = activeTool ?? ref.watch(canvasToolProvider);
    final isManaged = activeTool == null;

    void selectTool(CanvasTool tool) {
      if (onToolChanged != null) {
        onToolChanged!(tool);
      } else {
        ref.read(canvasToolProvider.notifier).state = tool;
        // Ensure connection state is reset so the first arrow drag always works
        if (tool == CanvasTool.arrow) {
          ref.read(canvasProvider.notifier).cancelConnecting();
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.drag_indicator,
                size: 16,
                color: AppTheme.textMuted.withValues(alpha: 0.5),
              ),
            ),
            const _Divider(),
            _ToolButton(
              icon: Icons.near_me_outlined,
              tool: CanvasTool.select,
              isActive: currentTool == CanvasTool.select,
              shortcut: '1',
              onTap: () => selectTool(CanvasTool.select),
            ),
            _ToolButton(
              icon: Icons.pan_tool_outlined,
              tool: CanvasTool.hand,
              isActive: currentTool == CanvasTool.hand,
              shortcut: 'H',
              onTap: () => selectTool(CanvasTool.hand),
            ),
            const _Divider(),
            _ToolButton(
              icon: Icons.crop_square,
              tool: CanvasTool.rectangle,
              isActive: currentTool == CanvasTool.rectangle,
              shortcut: '2',
              onTap: () => selectTool(CanvasTool.rectangle),
            ),
            _ToolButton(
              icon: Icons.circle_outlined,
              tool: CanvasTool.circle,
              isActive: currentTool == CanvasTool.circle,
              shortcut: '3',
              onTap: () => selectTool(CanvasTool.circle),
            ),
            _ToolButton(
              icon: Icons.change_history_rounded,
              tool: CanvasTool.diamond,
              isActive: currentTool == CanvasTool.diamond,
              shortcut: '4',
              onTap: () => selectTool(CanvasTool.diamond),
            ),
            const _Divider(),
            _ToolButton(
              icon: Icons.arrow_forward_outlined,
              tool: CanvasTool.arrow,
              isActive: currentTool == CanvasTool.arrow,
              shortcut: '5',
              onTap: () => selectTool(CanvasTool.arrow),
            ),
            _ToolButton(
              icon: Icons.maximize_outlined,
              tool: CanvasTool.line,
              isActive: currentTool == CanvasTool.line,
              shortcut: '6',
              onTap: () => selectTool(CanvasTool.line),
            ),
            _ToolButton(
              icon: Icons.edit_outlined,
              tool: CanvasTool.pen,
              isActive: currentTool == CanvasTool.pen,
              shortcut: '7',
              onTap: () => selectTool(CanvasTool.pen),
            ),
            _ToolButton(
              icon: Icons.text_fields_outlined,
              tool: CanvasTool.text,
              isActive: currentTool == CanvasTool.text,
              shortcut: 'T',
              onTap: () => selectTool(CanvasTool.text),
            ),
            const _Divider(),
            _ToolButton(
              icon: Icons.auto_fix_high_outlined,
              tool: CanvasTool.eraser,
              isActive: currentTool == CanvasTool.eraser,
              shortcut: '0',
              onTap: () => selectTool(CanvasTool.eraser),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final CanvasTool tool;
  final bool isActive;
  final String shortcut;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.tool,
    required this.isActive,
    required this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: '${tool.name.toUpperCase()} ($shortcut)',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isActive ? AppTheme.primary : AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(height: 2),
                Text(
                  shortcut,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: isActive ? AppTheme.primary.withValues(alpha: 0.7) : AppTheme.textMuted,
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppTheme.border,
    );
  }
}
