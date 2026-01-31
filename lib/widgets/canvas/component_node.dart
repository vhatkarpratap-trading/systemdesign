import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/component.dart';
import '../../theme/app_theme.dart';
import '../../data/excalidraw_definitions.dart';
import 'excalidraw_painter.dart';
import '../../providers/game_provider.dart';

/// Minimal component node for the canvas
class ComponentNode extends ConsumerWidget {
  final SystemComponent component;
  final bool isSelected;
  final bool isConnecting;
  final bool isValidTarget;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onDragEnd;
  final bool isEditing;
  final Function(String)? onTextChange;
  final VoidCallback? onEditDone;
  final VoidCallback? onLongPress;
  final Function(Offset)? onDragUpdate;

  const ComponentNode({
    super.key,
    required this.component,
    this.isSelected = false,
    this.isConnecting = false,
    this.isValidTarget = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onDragUpdate,
    this.onDragEnd,
    this.isEditing = false,
    this.onTextChange,
    this.onEditDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = component.status;
    final color = component.type.color;
    final isActive = component.metrics.currentRps > 0;
    final isSketchy = component.type.isSketchy;

    // Text components are transparent and just text
    // Text components are transparent and just text
    if (component.type == ComponentType.text) {
      if (isEditing) {
        return _InlineTextEditor(
          initialText: component.customName ?? 'New Text',
          onChange: onTextChange!,
          onDone: onEditDone!,
          maxWidth: math.max(100.0, component.size.width),
        );
      }
      
      return Container(
          decoration: BoxDecoration(
            border: isSelected ? Border.all(color: AppTheme.primary, width: 1.5) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            component.customName?.isNotEmpty == true ? component.customName! : '',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: component.size.width,
      height: component.size.height,
      decoration: BoxDecoration(
        color: (isSketchy && (component.type == ComponentType.rectangle || 
                             component.type == ComponentType.circle || 
                             component.type == ComponentType.diamond ||
                             component.type == ComponentType.arrow || 
                             component.type == ComponentType.line))
            ? Colors.transparent
            : null,
        gradient: (isSketchy && (component.type == ComponentType.rectangle || 
                                component.type == ComponentType.circle || 
                                component.type == ComponentType.diamond ||
                                component.type == ComponentType.arrow || 
                                component.type == ComponentType.line))
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isSelected ? AppTheme.surfaceLight : AppTheme.surfaceLight.withValues(alpha: 0.9),
                  isSelected ? AppTheme.surface : AppTheme.surface.withValues(alpha: 0.7),
                ],
              ),
        boxShadow: (isSelected || isActive || (!isSketchy && component.type != ComponentType.text)) 
            ? [
                BoxShadow(
                  color: (isSelected || isActive) 
                      ? color.withValues(alpha: isSelected ? 0.3 : 0.15)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: isSelected ? 12 : 4,
                  spreadRadius: isSelected ? 1 : 0,
                  offset: isSelected ? Offset.zero : const Offset(0, 2),
                ),
              ] 
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : (isSketchy && (component.type == ComponentType.rectangle || 
                             component.type == ComponentType.circle || 
                             component.type == ComponentType.diamond ||
                             component.type == ComponentType.arrow || 
                             component.type == ComponentType.line))
                  ? Colors.transparent
                  : (isConnecting
                      ? AppTheme.secondary.withValues(alpha: 0.5)
                      : Colors.transparent), // No border for standard components by default
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: GestureDetector(
        onDoubleTap: onDoubleTap, // Use passed callback if any
        child: isSketchy 
          ? _buildSketchyContent()
          : _buildStandardContent(status, color, isActive),
      ),
    );
  }

  Widget _buildTextContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.notes, size: 16, color: AppTheme.textMuted.withValues(alpha: 0.5)),
        const SizedBox(height: 4),
        Text(
          component.customName ?? '',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStandardContent(ComponentStatus status, Color color, bool isActive) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with status indicator
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                component.type.icon,
                color: color,
                size: 20, // Slightly smaller to prevent overflow
              ),
              // Minimal status dot removed per user request (was status.color)
              // Instance count
              if (component.config.instances > 1)
                Positioned(
                  left: -5,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.textMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '×${component.config.instances}',
                      style: const TextStyle(
                        fontSize: 6,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          // Name (Flexible to avoid overflow)
          Flexible(
            child: Text(
              component.customName ?? component.type.displayName,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          /* Removed RPS metric per user request for clean UI
          if (isActive) ...[
            const SizedBox(height: 1),
            Text(
              _formatRps(component.metrics.currentRps),
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w500,
                color: status.color.withValues(alpha: 0.8),
              ),
            ),
          ],
          */

          
          // Schema View (Optional)
          if (component.type == ComponentType.database && component.config.showSchema && component.config.dbSchema != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.9),
                border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                component.config.dbSchema!,
                style: GoogleFonts.robotoMono(
                  fontSize: 6,
                  color: AppTheme.textSecondary,
                  height: 1.2,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
  }

  Widget _buildSketchyContent() {
    // Import definition locally or via helper
    int index = 0;
    switch (component.type) {
      case ComponentType.sketchyService: index = 0; break;
      case ComponentType.sketchyDatabase: index = 1; break;
      case ComponentType.sketchyLogic: index = 2; break;
      case ComponentType.sketchyQueue: index = 3; break;
      case ComponentType.sketchyClient: index = 4; break;
      case ComponentType.rectangle: index = 5; break;
      case ComponentType.circle: index = 6; break;
      case ComponentType.arrow: index = 7; break;
      case ComponentType.line: index = 8; break;
      case ComponentType.diamond: index = 2; break;
      default: index = 0;
    }

    // Unified handling for all sketchy/geometric components
    const isGeometric = true;

    return Stack(
      children: [
        // Shape Layer
        Positioned.fill(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scale(component.flipX ? -1.0 : 1.0, component.flipY ? -1.0 : 1.0),
            child: CustomPaint(
              painter: ExcalidrawPainter(
                elements: excalidrawLibrary[index],
                overrideColor: isSelected ? AppTheme.primary : null,
                scaleToFit: true, // Use auto-scaling
                forceSolidFill: true, // No hachure/patterns
              ),
            ),
          ),
        ),
        
        // Text Layer - Centered for all sketchy shapes
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: isEditing 
              ? _InlineTextEditor(
                  initialText: component.customName ?? '',
                  onChange: onTextChange!,
                  onDone: onEditDone!,
                  isCentered: true,
                  maxWidth: math.max(80.0, component.size.width - 20),
                )
              : Text(
                  component.customName ?? '',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.architectsDaughter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
          ),
        ),
      ],
    );
  }

  String _formatRps(int rps) {
    if (rps >= 1000000) return '${(rps / 1000000).toStringAsFixed(1)}M/s';
    if (rps >= 1000) return '${(rps / 1000).toStringAsFixed(1)}K/s';
    return '$rps/s';
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: component.customName ?? component.type.displayName);
    final presets = component.type.presets;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Configure ${component.type.displayName}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Input
                TextField(
                  controller: controller,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Component Name',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                    hintStyle: TextStyle(color: AppTheme.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
                  ),
                  autofocus: true,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      ref.read(canvasProvider.notifier).renameComponent(component.id, value);
                    }
                    Navigator.pop(context);
                  },
                ),
                
                if (presets.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Quick Select:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((preset) {
                      return ActionChip(
                        label: Text(preset),
                        labelStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                        backgroundColor: AppTheme.surfaceLight,
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onPressed: () {
                          controller.text = preset;
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                 ref.read(canvasProvider.notifier).renameComponent(component.id, controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}



class _InlineTextEditor extends StatefulWidget {
  final String initialText;
  final Function(String) onChange;
  final VoidCallback onDone;
  final bool isCentered;
  final double maxWidth;

  const _InlineTextEditor({
    required this.initialText,
    required this.onChange,
    required this.onDone,
    this.isCentered = false,
    required this.maxWidth,
  });

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    // Request focus next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.maxWidth,
      child: Material(
        color: Colors.transparent,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textAlign: widget.isCentered ? TextAlign.center : TextAlign.start,
          style: widget.isCentered 
            ? GoogleFonts.architectsDaughter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              )
            : const TextStyle(
                fontSize: 16,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            isDense: true,
          ),
          onChanged: (val) => widget.onChange(val),
          onSubmitted: (_) => widget.onDone(),
          onEditingComplete: () => widget.onDone(),
        ),
      ),
    );
  }
}
