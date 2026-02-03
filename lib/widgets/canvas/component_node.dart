import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/component.dart';
import '../../theme/app_theme.dart';
import '../../data/excalidraw_definitions.dart';
import 'excalidraw_painter.dart';
import '../../providers/game_provider.dart';
import 'failure_animations.dart';

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
    // OPTIMIZATION: Watch specific metrics for this component only
    // This prevents the entire canvas from rebuilding when one component updates
    final ephemeralMetrics = ref.watch(simulationMetricsProvider.select((map) => map[component.id]));
    final metrics = ephemeralMetrics ?? component.metrics;

    final status = component.status;
    final color = component.type.color;
    final isActive = metrics.currentRps > 0;
    final isSketchy = component.type.isSketchy;
    
    // Determine visual failure states
    final hasError = metrics.errorRate > 0.1;
    final isOverloaded = metrics.cpuUsage > 0.9;
    final isScaling = metrics.isScaling;
    final isSlow = metrics.isSlow;
    final connectionExhaustion = metrics.connectionPoolUtilization > 0.9;

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

    Widget child = AnimatedContainer(
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
            : (hasError || isSlow || isOverloaded)
                ? RadialGradient(
                    colors: [
                      (hasError ? AppTheme.error : isOverloaded ? Colors.orange : Colors.amber)
                          .withValues(alpha: 0.25),
                      GetStatusColor(hasError, isOverloaded, isSlow).withValues(alpha: 0.05),
                    ],
                    radius: 0.8,
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isSelected ? AppTheme.surfaceLight : AppTheme.surfaceLight.withValues(alpha: 0.9),
                      isSelected ? AppTheme.surface : AppTheme.surface.withValues(alpha: 0.7),
                    ],
                  ),
        boxShadow: (isSelected || isActive || hasError || isSlow || (!isSketchy && component.type != ComponentType.text)) 
            ? [
                BoxShadow(
                  color: hasError 
                      ? Colors.red.withValues(alpha: 0.4)
                      : isSlow
                          ? Colors.amber.withValues(alpha: 0.3)
                          : isOverloaded
                              ? Colors.orange.withValues(alpha: 0.3)
                              : (isSelected || isActive) 
                                  ? color.withValues(alpha: isSelected ? 0.3 : 0.15)
                                  : Colors.black.withValues(alpha: 0.3),
                  blurRadius: hasError || isSlow || isOverloaded ? 16 : (isSelected ? 12 : 4),
                  spreadRadius: hasError || isSlow || isOverloaded ? 4 : (isSelected ? 1 : 0),
                  offset: (hasError || isSlow || isSelected) ? Offset.zero : const Offset(0, 2),
                ),
              ] 
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? Colors.red.withValues(alpha: 0.7)
              : isSlow
                  ? Colors.amber.withValues(alpha: 0.6)
                  : isOverloaded 
                      ? Colors.orange.withValues(alpha: 0.6)
                      : isSelected
                          ? AppTheme.primary
                          : (isSketchy && (component.type == ComponentType.rectangle || 
                                         component.type == ComponentType.circle || 
                                         component.type == ComponentType.diamond ||
                                         component.type == ComponentType.arrow || 
                                         component.type == ComponentType.line))
                              ? AppTheme.border.withValues(alpha: 0.4)
                              : (isConnecting
                                  ? AppTheme.secondary.withValues(alpha: 0.5)
                                  : Colors.transparent),
          width: hasError || isSlow || isOverloaded ? 3 : (isSelected ? 2.5 : 1),
        ),
      ),
      child: isSketchy 
          ? _buildSketchyContent()
          : _buildStandardContent(status, color, isActive, metrics, hasError, isSlow, isOverloaded),
    );
    
    // Unified Failure Animation Wrapper
    // If any issue is present, we wrap in ShakingWrapper (which handles jiggle)
    // Pulsing is handled by the AnimatedContainer shadow/gradient updates or we can keep it separate
    
    if (hasError || isOverloaded || isSlow) {
      child = ShakingWrapper(child: child);
    }
    
    // Add scaling pulse for autoscaling
    if (isScaling) {
      child = ScalingPulseWrapper(child: child);
    }
    
    return child;
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

  Widget _buildStandardContent(
    ComponentStatus status, 
    Color color, 
    bool isActive,
    ComponentMetrics metrics,
    bool hasError,
    bool isSlow,
    bool isOverloaded
  ) {
      final config = component.config;
      
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Replication Shadow (Faded replicas behind)
          if (config.replication && config.replicationFactor > 1)
            Positioned(
              top: 2,
              left: 2,
              child: Opacity(
                opacity: 0.3,
                child: Icon(component.type.icon, color: color, size: 20),
              ),
            ),
            
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with status indicator
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Visual Instances (Stacked Icons behind)
                  // Show up to 3 icons total for instances
                  if (config.instances > 1)
                    ...List.generate(math.min(config.instances - 1, 2), (i) => Positioned(
                      left: (i + 1) * 3.0,
                      top: (i + 1) * 2.0,
                      child: Icon(
                        component.type.icon,
                        color: color.withValues(alpha: 0.5 - (i * 0.15)),
                        size: 20,
                      ),
                    )),

                  // Read Replicas Visual (Small satellite icons)
                  if (config.replication && config.replicationFactor > 1)
                     ...List.generate(math.min(config.replicationFactor - 1, 3), (i) => Positioned(
                        right: -8.0 - (i * 4.0),
                        bottom: 0,
                        child: Icon(
                          component.type.icon,
                          color: color.withValues(alpha: 0.6),
                          size: 10,
                        ),
                      )),

                  // Sharding Visual (Multiple Icons if sharded - keeping this but adjusting)
                  if (config.sharding)
                    ...List.generate(math.min(config.partitionCount, 3), (i) => Positioned(
                      left: -i * 4.0,
                      bottom: i * 2.0,
                      child: Icon(
                        component.type.icon,
                        color: color.withValues(alpha: 0.8 - (i * 0.2)),
                        size: 14,
                      ),
                    )),
                    
                  Icon(
                    component.type.icon,
                    color: color,
                    size: 20,
                  ),
                  
                  // Replica/Instance count badge
                  if (config.instances > 1 || (config.replication && config.replicationFactor > 1))
                    Positioned(
                      left: -8,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          config.instances > 1 ? '×${config.instances}' : 'R:${config.replicationFactor}',
                          style: const TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
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
              
              // Strategy Indicators (Sharding/Consistent Hashing/Quorum labels)
              if (config.sharding || config.consistentHashing || config.replication)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    [
                      if (config.sharding) 'SHARDED',
                      if (config.consistentHashing) 'HASH',
                      if (config.replication) 'REP',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 5, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                  ),
                ),

              // Capacity / Traffic Indicator
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Builder(
                    builder: (context) {
                      final totalCapacity = config.capacity * config.instances;
                      final isOverflow = metrics.currentRps > totalCapacity;
                      return Text(
                        '${metrics.currentRps} / ${totalCapacity} RPS',
                        style: TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.bold,
                          color: isOverflow ? Colors.red : AppTheme.textSecondary.withValues(alpha: 0.7),
                        ),
                      );
                    }
                  ),
                ),

              // Schema View (Optional)
              if (component.type == ComponentType.database && config.showSchema && config.dbSchema != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.9),
                    border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    config.dbSchema!,
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
          ),
          
          // Strategy Overlays (Badges)
          _buildStrategyBadges(config),

          // Load Bar (New "Human" Feature)
          if (isActive)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: _buildLoadBar(metrics.cpuUsage),
            ),

          // Status Emoji (New "Human" Feature)
          if (hasError || isSlow || isOverloaded)
            Positioned(
              top: -8,
              left: -8,
              child: _buildStatusEmoji(hasError, isSlow, isOverloaded),
            ),
            
          // Pressure Label (Explicit "Capacity Used" indicator)
          if (isActive && (metrics.cpuUsage > 0.5 || metrics.queueDepth > 10 || metrics.connectionPoolUtilization > 0.5))
             Positioned(
               bottom: 12,
               right: 4,
               child: _buildPressureLabel(metrics),
             ),
        ],
      );
  }

  Widget _buildPressureLabel(ComponentMetrics metrics) {
    // Determine the dominant pressure factor
    double pressure = metrics.cpuUsage;
    String label = 'LOAD';
    
    if (metrics.queueDepth > 50) {
      // Normalize queue depth for display (e.g. 100 items = 100% vis)
      pressure = (metrics.queueDepth / 200).clamp(0.0, 1.0);
      label = 'QUEUE';
    } else if (metrics.connectionPoolUtilization > pressure) {
      pressure = metrics.connectionPoolUtilization;
      label = 'CONN';
    }
    
    final percentage = (pressure * 100).toInt();
    final color = pressure > 0.9 ? AppTheme.error : (pressure > 0.7 ? AppTheme.warning : AppTheme.textSecondary);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2,
          )
        ]
      ),
      child: Text(
        '$label: $percentage%',
        style: TextStyle(
          fontSize: 6, 
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLoadBar(double load) {
    // Green -> Yellow -> Red gradient based on load
    final color = load > 0.9 
        ? AppTheme.error 
        : load > 0.7 
            ? AppTheme.warning 
            : AppTheme.success;
            
    // Enhanced Load Bar: Taller and with Glow
    return Container(
      height: 6, // Taller
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.3), width: 0.5),
      ),
      // Smoothly animate the width of the load bar
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: load.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 200), // Smooth 200ms transition
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                boxShadow: load > 0.7 ? [
                   BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1),
                ] : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusEmoji(bool hasError, bool isSlow, bool isOverloaded) {
    IconData? icon;
    Color color = Colors.transparent;
    
    if (hasError) {
      icon = Icons.error_outline;
      color = AppTheme.error;
    } else if (isOverloaded) {
      icon = Icons.local_fire_department;
      color = Colors.orange;
    } else if (isSlow) {
      icon = Icons.hourglass_bottom;
      color = Colors.amber;
    }
    
    if (icon == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }

  Widget _buildStrategyBadges(ComponentConfig config) {
    return Positioned(
      right: -4,
      top: -4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (config.rateLimiting) _badgeItem(Icons.speed, Colors.orange),
          if (config.circuitBreaker) _badgeItem(Icons.power_off, Colors.red),
          if (config.retries) _badgeItem(Icons.replay, Colors.blue),
          if (config.dlq) _badgeItem(Icons.warning_amber, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _badgeItem(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 0.5),
      ),
      child: Icon(icon, size: 6, color: Colors.white),
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

  Color GetStatusColor(bool hasError, bool isOverloaded, bool isSlow) {
    if (hasError) return AppTheme.error;
    if (isOverloaded) return Colors.orange;
    if (isSlow) return Colors.amber;
    return AppTheme.surface;
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
