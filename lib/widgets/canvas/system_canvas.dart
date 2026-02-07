import 'dart:math' as math;
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart'; // Added
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/component.dart';
import '../../models/connection.dart';
import '../../providers/game_provider.dart';
import '../../models/problem.dart';
import '../../theme/app_theme.dart';
import 'component_node.dart';
import 'component_hover_popover.dart';
import 'connections_layer.dart';
import 'traffic_layer.dart'; // Added
import '../../models/traffic_particle.dart'; // Added
import '../../providers/traffic_provider.dart'; // Added
import 'package:uuid/uuid.dart';
import '../../models/chaos_event.dart';
import '../../models/custom_component.dart';
import 'issue_marker.dart';
import '../panels/db_modeling_panel.dart';
import '../../providers/auth_provider.dart';

/// Interactive canvas for building system architecture
class SystemCanvas extends ConsumerStatefulWidget {
  const SystemCanvas({super.key});

  @override
  ConsumerState<SystemCanvas> createState() => _SystemCanvasState();
}

class _SystemCanvasState extends ConsumerState<SystemCanvas> {
  final TransformationController _transformController = TransformationController();
  bool _isExternalUpdate = false;
  bool _isUserInteracting = false;
  Offset? _dragPreviewPosition;
  Timer? _debounceTimer;
  Timer? _scrollEndTimer;
  
  // Drag-to-connect state
  String? _draggingFromId;
  Offset? _draggingCurrentPos;
  Offset? _dragStartPos;
  Offset? _drawStartPos;
  Offset? _drawEndPos;
  String? _hoveredComponentId; // Only for non-selected hint if needed, mostly unused now
  String? _editingComponentId; // ID of component being edited inline
  final FocusNode _focusNode = FocusNode();
  Offset? _lastDoubleTapGlobalPos;
  DateTime? _lastTapTime;
  String? _lastTappedId;
  bool _showSettingsSidebar = false;
  SystemComponent? _selectedComponentForSidebar;

  @override
  void initState() {
    super.initState();
    // Sync UI changes (gestures) back to provider source of truth
    _transformController.addListener(_onTransformChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Center the view in the stable canvas
      final viewport = MediaQuery.of(context).size;
      final x = -5000.0 + viewport.width / 2;
      final y = -5000.0 + viewport.height / 2;
      
      _updateController(
        Matrix4.identity()..setTranslationRaw(x, y, 0.0),
      );
      
      // Initialize provider with this default state
      ref.read(canvasProvider.notifier).updateTransform(
        panOffset: Offset(x, y),
        scale: 1.0,
      );
    });
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    _scrollEndTimer?.cancel();
    super.dispose();
  }

  void _onTransformChanged() {
    // Only handle external updates (e.g. from Auto Layout or Zoom buttons)
    // or inertia updates when the user is NOT actively touching/scrolling.
    if (_isExternalUpdate || _isUserInteracting) return;

    _debounceSave();
  }

  void _debounceSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && !_isUserInteracting) {
        _syncToProvider();
      }
    });
  }

  void _syncToProvider() {
    final matrix = _transformController.value;
    final translation = matrix.getTranslation();
    final scale = matrix.getMaxScaleOnAxis();
    
    ref.read(canvasProvider.notifier).updateTransform(
      panOffset: Offset(translation.x, translation.y),
      scale: scale,
    );
  }

  void _updateController(Matrix4 matrix) {
    _isExternalUpdate = true;
    _transformController.value = matrix;
    _isExternalUpdate = false;
  }

  Offset _getCanvasPosition(Offset globalPosition) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return globalPosition;
    
    final localPosition = renderBox.globalToLocal(globalPosition);
    final Matrix4 matrix = _transformController.value.clone()..invert();
    return MatrixUtils.transformPoint(matrix, localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = ref.watch(canvasReadOnlyProvider);
    // CRITICAL: We only watch the fields that affect the visual build of the components.
    // We specifically do NOT watch 'panOffset' or 'scale' here, because those are 
    // handled by the TransformationController. If we rebuilt on every pan/zoom,
    // the InteractiveViewer would lose its active gesture state!
    final components = ref.watch(canvasProvider.select((s) => s.components));
    final connections = ref.watch(canvasProvider.select((s) => s.connections));
    final selectedComponentId = ref.watch(canvasProvider.select((s) => s.selectedComponentId));
    final connectingFromId = ref.watch(canvasProvider.select((s) => s.connectingFromId));

    // Reconstruction for backwards compatibility with builders
    final canvasState = CanvasState(
      components: components,
      connections: connections,
      selectedComponentId: selectedComponentId,
      connectingFromId: connectingFromId,
    );
    
    final activeTool = ref.watch(canvasToolProvider);
    final simState = ref.watch(simulationProvider);
    final problem = ref.watch(currentProblemProvider);
    final isSimulating = simState.isRunning;
    final isConnecting = connectingFromId != null;

    final isSelectionMode = activeTool == CanvasTool.select;
    final isHandMode = activeTool == CanvasTool.hand;
    final isDrawingMode = activeTool == CanvasTool.rectangle || 
                         activeTool == CanvasTool.circle ||
                         activeTool == CanvasTool.diamond ||
                         activeTool == CanvasTool.arrow ||
                         activeTool == CanvasTool.line;
    final isArrowActive = activeTool == CanvasTool.arrow;

    // Listen for external transform changes (e.g. Zoom Buttons, Auto Layout)
    ref.listen(canvasProvider, (previous, next) {
      // If the user is currently interacting with the canvas directly, 
      // do NOT let the provider fight the transformation controller.
      if (_isUserInteracting || _isExternalUpdate) return;

      if (next.scale != null && next.panOffset != null) {
        final currentMatrix = _transformController.value;
        final currentTranslation = currentMatrix.getTranslation();
        final currentScale = (currentMatrix.getMaxScaleOnAxis() * 1000).round() / 1000;
        final nextScale = (next.scale! * 1000).round() / 1000;

        final hasChanged = (currentScale - nextScale).abs() > 0.001 ||
                           (currentTranslation.x - next.panOffset!.dx).abs() > 0.5 ||
                           (currentTranslation.y - next.panOffset!.dy).abs() > 0.5;

        if (hasChanged) {
           final matrix = Matrix4.identity()
            ..translate(next.panOffset!.dx, next.panOffset!.dy)
            ..scale(next.scale!);
           
           _updateController(matrix);
        }
      }
    });

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final isDelete = event.logicalKey == LogicalKeyboardKey.delete || 
                          event.logicalKey == LogicalKeyboardKey.backspace;
          
          if (isDelete && canvasState.selectedComponentId != null && _editingComponentId == null) {
            ref.read(canvasProvider.notifier).removeComponent(canvasState.selectedComponentId!);
            return KeyEventResult.handled;
          }

          // Tool shortcuts
          if (_editingComponentId == null) {
            final key = event.logicalKey;
            
            // Escape key handling
            if (key == LogicalKeyboardKey.escape) {
              // Close settings sidebar first if open
              if (_showSettingsSidebar) {
                _closeSidebar();
                return KeyEventResult.handled;
              } else if (activeTool != CanvasTool.select) {
                // Revert tool to Select
                ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
              } else if (canvasState.selectedComponentId != null) {
                // Clear selection
                ref.read(canvasProvider.notifier).selectComponent(null);
              } else if (canvasState.connectingFromId != null) {
                // Cancel connection
                ref.read(canvasProvider.notifier).cancelConnecting();
              }
              return KeyEventResult.handled;
            }

            if (key == LogicalKeyboardKey.digit1) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit2) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.rectangle;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit3) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.circle;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit4) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.diamond;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit5) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.arrow;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit6) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.line;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit7) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.pen;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.keyT) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.text;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.keyH) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.hand;
              return KeyEventResult.handled;
            } else if (key == LogicalKeyboardKey.digit0) {
              ref.read(canvasToolProvider.notifier).state = CanvasTool.eraser;
              return KeyEventResult.handled;
            }

            // Clear Canvas shortcut (Ctrl + Shift + Backspace)
            final isControl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            if (isControl && HardwareKeyboard.instance.isShiftPressed && event.logicalKey == LogicalKeyboardKey.backspace) {
              ref.read(canvasProvider.notifier).clear();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand, // Force stack to fill parent
        children: [
          Positioned.fill( // Constrain canvas to stack size
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DragTarget<Object>(
                onWillAcceptWithDetails: (details) => true,
                onMove: (details) {
                  final canvasPos = _getCanvasPosition(details.offset);
                  setState(() => _dragPreviewPosition = canvasPos);
                },
                onLeave: (_) {
                  setState(() {
                    _dragPreviewPosition = null;
                  });
                },
                onAcceptWithDetails: (details) {
                  final canvasPos = _getCanvasPosition(details.offset);
                  final data = details.data;
                  
                  if (data is ComponentType) {
                    ref.read(canvasProvider.notifier).addComponent(
                      data,
                      Offset(canvasPos.dx.clamp(50, 9900), canvasPos.dy.clamp(50, 9900)),
                    );
                  } else if (data is ChaosType) {
                    // Find target component
                    final canvasState = ref.read(canvasProvider);
                    String? targetId;
                    for (final comp in canvasState.components) {
                      final rect = Rect.fromLTWH(comp.position.dx, comp.position.dy, comp.size.width, comp.size.height);
                      if (rect.contains(canvasPos)) {
                        targetId = comp.id;
                        break;
                      }
                    }
                    
                    // Create Chaos Event
                    final event = ChaosEvent(
                      id: const Uuid().v4(),
                      type: data,
                      startTime: DateTime.now(),
                      duration: const Duration(seconds: 30), // Default 30s disaster
                      parameters: {
                         'targetId': targetId, // Null means global or random?
                         'severity': 1.0, 
                      },
                    );

                    // Add to simulation
                    ref.read(simulationProvider.notifier).addChaosEvent(event);
                    
                    // Visual feedback
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${data.emoji} ${data.label} unleashed!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppTheme.secondary,
                      ),
                    );
                  } else if (data is CustomComponentDefinition) {
                    // Expand custom component to internal nodes + connections
                    final dropPos = Offset(canvasPos.dx.clamp(50, 9900), canvasPos.dy.clamp(50, 9900));
                    final createdIds = ref.read(canvasProvider.notifier).addCustomComponent(data, dropPos);
                    
                    // Visual feedback
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${data.name} deployed with ${createdIds.length} components!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: data.color,
                      ),
                    );
                  } else if (data is SystemComponent) {
                    // Add template component
                    final dropPos = Offset(canvasPos.dx.clamp(50, 9900), canvasPos.dy.clamp(50, 9900));
                    ref.read(canvasProvider.notifier).addComponentTemplate(data, dropPos);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${data.customName ?? data.type.displayName} deployed!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                  
                  setState(() => _dragPreviewPosition = null);
                },
                builder: (context, candidateData, rejectedData) {
                  final isDragging = candidateData.isNotEmpty;
                  
                  return Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        final isControl = HardwareKeyboard.instance.isControlPressed || 
                                         HardwareKeyboard.instance.isMetaPressed;
                        
                        if (isControl) {
                          _isUserInteracting = true;
                          _scrollEndTimer?.cancel();
                          _scrollEndTimer = Timer(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              _isUserInteracting = false;
                              _syncToProvider();
                            }
                          });

                          final double zoomDelta = -pointerSignal.scrollDelta.dy / 250;
                          final double currentScale = _transformController.value.getMaxScaleOnAxis();
                          final double newScale = (currentScale + zoomDelta).clamp(0.1, 5.0);
                          
                          final Offset localPos = pointerSignal.localPosition;
                          final Matrix4 matrix = _transformController.value.clone();
                          final Offset untransformedPos = MatrixUtils.transformPoint(Matrix4.inverted(matrix), localPos);
                          
                          final Matrix4 newMatrix = Matrix4.identity()
                            ..translate(localPos.dx, localPos.dy)
                            ..scale(newScale)
                            ..translate(-untransformedPos.dx, -untransformedPos.dy);
                          
                          _updateController(newMatrix);
                        }
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.1,
                      maxScale: 5.0,
                      constrained: false,
                      panEnabled: true, // Allow panning during simulation
                      scaleEnabled: true, // Allow zoom during simulation
                      trackpadScrollCausesScale: false,
                      boundaryMargin: const EdgeInsets.all(5000),
                      onInteractionStart: (_) {
                        _isUserInteracting = true;
                        _debounceTimer?.cancel();
                        _scrollEndTimer?.cancel();
                      },
                      onInteractionEnd: (_) {
                        _isUserInteracting = false;
                        _syncToProvider();
                      },
                      child: SizedBox(
                        width: 10000,
                        height: 10000,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (isHandMode) return;
                            // Reset selection on background tap
                            ref.read(canvasProvider.notifier).selectComponent(null);
                            setState(() {
                              _editingComponentId = null;
                              _showSettingsSidebar = false;
                              _selectedComponentForSidebar = null;
                            });
                            _focusNode.requestFocus();
                          },
                          onTapUp: (details) {
                             if (activeTool == CanvasTool.text) {
                                _addTextAt(details.globalPosition);
                                return;
                             }
                          },
                          onDoubleTapDown: (details) {
                            if (isSelectionMode) {
                              _lastDoubleTapGlobalPos = details.globalPosition;
                            }
                          },
                          onDoubleTap: () {
                            if (isSelectionMode && _lastDoubleTapGlobalPos != null) {
                              _addTextAt(_lastDoubleTapGlobalPos!);
                              _lastDoubleTapGlobalPos = null;
                            }
                          },
                          onPanStart: isDrawingMode ? (details) {
                            setState(() {
                              _drawStartPos = details.localPosition;
                              _drawEndPos = _drawStartPos;
                            });
                          } : null,
                          onPanUpdate: isDrawingMode ? (details) {
                            setState(() {
                              _drawEndPos = details.localPosition;
                            });
                          } : null,
                          onPanEnd: isDrawingMode ? (details) {
                            _finishDrawing(activeTool);
                          } : null,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                                    // Background & Grid
                                    Positioned.fill(
                                      child: Container(
                                        color: canvasState.isCyberpunkMode ? AppTheme.cyberpunkBackground : AppTheme.background,
                                        child: RepaintBoundary(
                                          child: CustomPaint(
                                            size: const Size(10000, 10000),
                                            painter: _GridPainter(
                                              color: canvasState.isCyberpunkMode 
                                                ? AppTheme.neonCyan.withValues(alpha: 0.15) 
                                                : AppTheme.border.withValues(alpha: 0.3),
                                              isCyberpunk: canvasState.isCyberpunkMode,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Connections
                                    Positioned.fill(
                                      child: RepaintBoundary(
                                        child: ConnectionsLayer(
                                          canvasState: canvasState,
                                          isSimulating: isSimulating,
                                          onTap: (connection) {
                                            _showConnectionOptions(connection);
                                          },
                                        ),
                                      ),
                                    ),

                                    // Traffic Particles (NEW)
                                    Consumer(
                                      builder: (context, ref, child) {
                                        final particles = ref.watch(trafficProvider);
                                        if (particles.isEmpty) return const SizedBox.shrink();
                                        
                                        return Positioned.fill(
                                          child: IgnorePointer(
                                            child: RepaintBoundary(
                                              child: CustomPaint(
                                                painter: TrafficLayer(
                                                  particles: particles,
                                                  connections: canvasState.connections,
                                                  components: canvasState.components,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),

                                    // Elastic cable
                                    if (_draggingFromId != null && _draggingCurrentPos != null)
                                      _buildElasticCable(canvasState),

                                    // Drawing preview
                                    if (_drawStartPos != null && _drawEndPos != null && isDrawingMode)
                                      _buildDrawingPreview(activeTool),

                                    // Components
                                    ...canvasState.components.map((component) {
                                      final isSelected = component.id == canvasState.selectedComponentId;
                                      final isConnectSource = component.id == canvasState.connectingFromId;
                                      final isHovered = _hoveredComponentId == component.id;
                                      final isArrowActive = activeTool == CanvasTool.arrow;
                                      final isValidTarget = (isConnecting && canvasState.connectingFromId != component.id) || 
                                                          (isArrowActive && isHovered);
                                      
                                      return Positioned(
                                        left: component.position.dx,
                                        top: component.position.dy,
                                        child: MouseRegion(
                                          onEnter: (_) {
                                            if (activeTool == CanvasTool.arrow) {
                                              setState(() => _hoveredComponentId = component.id);
                                            }
                                          },
                                          onExit: (_) {
                                            if (_hoveredComponentId == component.id && _draggingFromId == null) {
                                              setState(() => _hoveredComponentId = null);
                                            }
                                          },
                                          cursor: _getCursorForTool(activeTool),
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              debugPrint('Component Tap: ${component.id}');
                                              final now = DateTime.now();
                                              if (_lastTappedId == component.id && 
                                                  _lastTapTime != null) {
                                                final diff = now.difference(_lastTapTime!).inMilliseconds;
                                                debugPrint('Tap separation: ${diff}ms');
                                                if (diff < 600) {
                                                  debugPrint('Manual DoubleTap Detected: ${component.id}');
                                                  _showComponentOptions(component);
                                                  _lastTapTime = null; 
                                                  _lastTappedId = null;
                                                } else {
                                                  _lastTapTime = now;
                                                  _lastTappedId = component.id;
                                                }
                                              } else {
                                                _lastTapTime = now;
                                                _lastTappedId = component.id;
                                              }

                                              if (activeTool == CanvasTool.eraser) {
                                                ref.read(canvasProvider.notifier).removeComponent(component.id);
                                                ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
                                                return;
                                              }
                                              if (isHandMode) return;
                                              _onComponentTap(component, isConnecting);
                                              _focusNode.requestFocus();
                                            },
                                            onDoubleTap: () {
                                              if (readOnly) return;
                                              debugPrint('Flutter DoubleTap: ${component.id}');
                                              if (activeTool == CanvasTool.arrow) return;
                                              final canEditInline = component.type.isSketchy || component.type == ComponentType.text;
                                              if (canEditInline) {
                                                setState(() => _editingComponentId = component.id);
                                              } else {
                                                _showComponentOptions(component);
                                              }
                                            },
                                            onPanStart: (details) {
                                              if (readOnly) return;
                                              if (activeTool == CanvasTool.arrow) {
                                                _onDragConnectStart(component, startPos: _getCanvasPosition(details.globalPosition));
                                              }
                                            },
                                            onPanUpdate: (details) {
                                              if (readOnly) return;
                                              if (activeTool == CanvasTool.arrow) {
                                                _onDragConnectUpdate(details.globalPosition);
                                                return;
                                              }
                                              if (isSelectionMode) {
                                                _moveComponent(component, details.delta);
                                              }
                                            },
                                            onPanEnd: (details) {
                                              if (activeTool == CanvasTool.arrow) {
                                                _onDragConnectEnd();
                                              }
                                            },
                                            child: RepaintBoundary(
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 150),
                                                decoration: isValidTarget
                                                    ? BoxDecoration(
                                                        borderRadius: BorderRadius.circular(14),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: AppTheme.primary.withValues(alpha: 0.4),
                                                            blurRadius: 12,
                                                            spreadRadius: 2,
                                                          ),
                                                        ],
                                                      )
                                                    : null,
                                                child: ComponentHoverPopover(
                                                  component: component,
                                                  child: ComponentNode(
                                                    component: component,
                                                    isSelected: isSelected,
                                                    isConnecting: isConnectSource,
                                                    isValidTarget: isValidTarget,
                                                    isEditing: _editingComponentId == component.id,
                                                    onLabelTap: () {
                                                      ref.read(canvasProvider.notifier).selectComponent(component.id);
                                                      setState(() => _editingComponentId = component.id);
                                                    },
                                                    onTextChange: (newName) {
                                                      ref.read(canvasProvider.notifier).renameComponent(component.id, newName);
                                                      _resizeComponentToFitText(component, newName);
                                                    },
                                                    onEditDone: () {
                                                      setState(() => _editingComponentId = null);
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),

                                    // Issue Markers - only if enabled and user visible
                                    ...(canvasState.showErrors 
                                        ? simState.visibleFailures.where((f) => f.userVisible).map((failure) {
                                            final component = canvasState.getComponent(failure.componentId);
                                            if (component == null) return const SizedBox.shrink();
                                            return IssueMarker(
                                              failure: failure,
                                              position: component.position,
                                            );
                                          })
                                        : []),

                                    // Drop preview
                                    if (isDragging && _dragPreviewPosition != null)
                                      Positioned(
                                        left: _dragPreviewPosition!.dx - 40,
                                        top: _dragPreviewPosition!.dy - 32,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 80,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                                            ),
                                            child: Icon(
                                              (candidateData.first is ComponentType) 
                                                  ? (candidateData.first as ComponentType).icon 
                                                  : (candidateData.first is ChaosType)
                                                      ? (candidateData.first as ChaosType).icon
                                                      : Icons.add,
                                              color: AppTheme.primary.withValues(alpha: 0.7),
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          ),
          
          
          // 2. Settings Sidebar Layer (Overlay)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            top: 0,
            bottom: 0,
            right: (_showSettingsSidebar && _selectedComponentForSidebar != null) ? 0 : -350,
            width: 350,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
                border: const Border(
                  left: BorderSide(color: AppTheme.border, width: 1),
                ),
              ),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 0,
                    child: _selectedComponentForSidebar != null 
                        ? _buildSettingsSidebar(_selectedComponentForSidebar!)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),

          // 3. Cyberpunk & Cost Controls (Top Right Overlay)
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Cost Ticker
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: canvasState.isCyberpunkMode 
                        ? AppTheme.cyberpunkSurface.withValues(alpha: 0.9)
                        : AppTheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: canvasState.isCyberpunkMode ? AppTheme.neonMagenta : AppTheme.border,
                      width: canvasState.isCyberpunkMode ? 1.5 : 1,
                    ),
                    boxShadow: canvasState.isCyberpunkMode 
                        ? [BoxShadow(color: AppTheme.neonMagenta.withValues(alpha: 0.4), blurRadius: 8)]
                        : [],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showBudgetDialog(problem),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_money, size: 16, color: canvasState.isCyberpunkMode ? AppTheme.neonMagenta : AppTheme.success),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\$${(simState.globalMetrics.totalCostPerHour > 0
                                      ? simState.globalMetrics.totalCostPerHour
                                      : canvasState.totalCostPerHour)
                                  .toStringAsFixed(2)}/hr',
                              style: GoogleFonts.firaCode(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Spent ${simState.globalMetrics.costSpentString} · Budget \$${_formatBudget(problem.constraints.budgetPerMonth)}/mo',
                              style: GoogleFonts.firaCode(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.edit, size: 14, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Cyberpunk Toggle
                GestureDetector(
                  onTap: () {
                      ref.read(canvasProvider.notifier).toggleCyberpunkMode();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: canvasState.isCyberpunkMode 
                          ? AppTheme.cyberpunkSurface.withValues(alpha: 0.9)
                          : AppTheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: canvasState.isCyberpunkMode ? AppTheme.neonCyan : AppTheme.border,
                      ),
                      boxShadow: canvasState.isCyberpunkMode 
                          ? [BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.4), blurRadius: 8)]
                          : [],
                    ),
                    child: Icon(
                      Icons.nightlight_round,
                      size: 20,
                      color: canvasState.isCyberpunkMode ? AppTheme.neonCyan : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 4. Empty state
          if (canvasState.components.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    size: 40,
                    color: AppTheme.textMuted.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Drag components here',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pinch to zoom • Drag to pan',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildElasticCable(CanvasState canvasState) {
    final source = canvasState.getComponent(_draggingFromId!);
    if (source == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _PreviewCablePainter(
            start: _dragStartPos ?? Offset(source.position.dx + 80, source.position.dy + 32),
            end: _draggingCurrentPos!,
          ),
        ),
      ),
    );
  }

  void _onDragConnectStart(SystemComponent component, {Offset? startPos}) {
    if (ref.read(canvasReadOnlyProvider)) return;
    setState(() {
      _draggingFromId = component.id;
      _dragStartPos = startPos ?? Offset(component.position.dx + 80, component.position.dy + 32);
      _draggingCurrentPos = _dragStartPos;
      _editingComponentId = null; // Clear any active editing
    });
  }

  void _onDragConnectUpdate(Offset globalPos) {
    if (ref.read(canvasReadOnlyProvider)) return;
    final canvasPos = _getCanvasPosition(globalPos);

    // Find if we are hovering over another component (Magnetic Snap)
    final canvasState = ref.read(canvasProvider);
    String? hoverId;
    Offset targetPos = canvasPos;
    double closestDistance = 50.0; // Snap radius

    for (final comp in canvasState.components) {
      if (comp.id == _draggingFromId) continue;

      // Check distance to center for magnetic snap
      final center = Offset(comp.position.dx + 40, comp.position.dy + 32);
      final dist = (canvasPos - center).distance;

      if (dist < closestDistance) {
        closestDistance = dist;
        hoverId = comp.id;
        targetPos = center; // Snap to center
      } else {
        // Fallback to strict bounds check for larger components if outside snap radius
        final rect = Rect.fromLTWH(comp.position.dx, comp.position.dy, 80, 64);
        if (rect.contains(canvasPos)) {
           hoverId = comp.id;
           // Don't modify targetPos here, let it follow mouse unless snapped
        }
      }
    }

    setState(() {
      _draggingCurrentPos = targetPos; // Use snapped position if snapped
      _hoveredComponentId = hoverId;
    });
  }

  void _onDragConnectEnd() {
    if (ref.read(canvasReadOnlyProvider)) {
      setState(() {
        _draggingFromId = null;
        _draggingCurrentPos = null;
        _hoveredComponentId = null;
      });
      return;
    }
    if (_draggingFromId != null && _hoveredComponentId != null) {
      // Direct connection without dialog for seamless flow
      final error = ref.read(canvasProvider.notifier).connectTo(
        _hoveredComponentId!, 
        direction: ConnectionDirection.unidirectional,
        fromIdOverride: _draggingFromId,
      );
      
      if (error != null) {
        // Connection error - removed snackbar
      }
    }
    
    setState(() {
      _draggingFromId = null;
      _draggingCurrentPos = null;
      _hoveredComponentId = null;
    });

    // Revert tool to select after dragging a connection
    if (ref.read(canvasToolProvider) == CanvasTool.arrow) {
      ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
    }
  }

  void _onComponentTap(SystemComponent component, bool isConnecting) {
    final canvasNotifier = ref.read(canvasProvider.notifier);
    final canvasState = ref.read(canvasProvider);
    final activeTool = ref.read(canvasToolProvider); // Check active tool
    final readOnly = ref.read(canvasReadOnlyProvider);

    if (readOnly) {
      // Allow selection highlight only
      canvasNotifier.selectComponent(component.id);
      return;
    }

    // Arrow tool acts as a connection tool (Hybrid: Connect + Edit)
    if (activeTool == CanvasTool.arrow) {
      if (canvasState.connectingFromId == null) {
        // Start connection
        canvasNotifier.startConnecting(component.id);
        // Hybrid: Also open text editor for the source component
        setState(() => _editingComponentId = component.id);
      } else {
        // Complete connection
        if (canvasState.connectingFromId != component.id) {
          final error = canvasNotifier.connectTo(
            component.id, 
            direction: ConnectionDirection.unidirectional,
          );
          
          if (error != null) {
            // Connection error - removed snackbar
          } else {
             // Success! Reset tool and close editor
             canvasNotifier.cancelConnecting();
             setState(() => _editingComponentId = null);
             ref.read(canvasToolProvider.notifier).state = CanvasTool.select; 
          }
        } else {
            // Tapped self, cancel everything
             canvasNotifier.cancelConnecting();
             setState(() => _editingComponentId = null);
        }
      }
      return;
    }

    if (isConnecting) {
      // Complete connection
      if (canvasState.connectingFromId != component.id) {
        // Automatically create a One-Way connection
        final error = canvasNotifier.connectTo(component.id, direction: ConnectionDirection.unidirectional);
        
        if (error != null) {
          // Connection error - removed snackbar
        } else {
          canvasNotifier.cancelConnecting();
        }
      }
      return;
    }

    // Close settings sidebar if clicking anywhere on canvas
    if (_showSettingsSidebar && _selectedComponentForSidebar?.id != component.id) {
      _closeSidebar();
    }

    // Toggle selection
    if (canvasState.selectedComponentId == component.id) {
      canvasNotifier.selectComponent(null);
    } else {
      canvasNotifier.selectComponent(component.id);
    }
  }

  void _startConnecting(SystemComponent component) {
    ref.read(canvasProvider.notifier).startConnecting(component.id);
  }

  void _moveComponent(SystemComponent component, Offset delta) {
    // Zoom-aware movement
    final scale = _transformController.value.getMaxScaleOnAxis(); 
    final adjustedDelta = delta / scale;

    final newPos = Offset(
      (component.position.dx + adjustedDelta.dx).clamp(0, 9900),
      (component.position.dy + adjustedDelta.dy).clamp(0, 9900),
    );
    ref.read(canvasProvider.notifier).moveComponent(component.id, newPos);
  }

  void _addComponentAtCenter(ComponentType type) {
    // Get viewport center in canvas coordinates
    final viewport = MediaQuery.of(context).size;
    final centerOffset = Offset(viewport.width / 2, viewport.height / 2);
    
    // Invert transform to get canvas coordinates
    final matrix = _transformController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, centerOffset);
    
    // Add component slightly offset randomly to prevent perfect stacking
    final randomOffset = Offset(
      (math.Random().nextDouble() - 0.5) * 40,
      (math.Random().nextDouble() - 0.5) * 40,
    );

    final newId = ref.read(canvasProvider.notifier).addComponent(
      type, 
      canvasPos + randomOffset,
    );

    // Auto-edit for text nodes
    if (type == ComponentType.text) {
      setState(() => _editingComponentId = newId);
    }
  }

  void _addTextAt(Offset globalPos) {
    // Convert local interactive viewer position to canvas position
    final canvasPos = _getCanvasPosition(globalPos);
    
    // Check if tapping on an existing component to avoid conflict
    final canvasState = ref.read(canvasProvider);
    for (final component in canvasState.components) {
       final rect = Rect.fromLTWH(component.position.dx, component.position.dy, 80, 64);
       if (rect.contains(canvasPos)) return;
    }

    // Overlap prevention logic
    Offset finalPos = canvasPos;
    bool hasOverlap;
    int attempts = 0;
    const textSize = Size(100, 40);
    
    do {
      hasOverlap = false;
      final textRect = Rect.fromLTWH(finalPos.dx - 40, finalPos.dy - 20, textSize.width, textSize.height);
      for (final comp in canvasState.components) {
        final compRect = Rect.fromLTWH(comp.position.dx, comp.position.dy, 80, 64);
        if (compRect.overlaps(textRect)) {
          finalPos += const Offset(0, 40);
          hasOverlap = true;
          break;
        }
      }
      attempts++;
    } while (hasOverlap && attempts < 5);

    final adjustedPos = finalPos - const Offset(8, 4);
    final id = ref.read(canvasProvider.notifier).addComponent(
      ComponentType.text,
      adjustedPos,
    );
    setState(() {
      _editingComponentId = id;
    });
    
    // Revert tool to select after placing text
    ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
  }

  void _addComponentAt(CanvasTool tool, Offset canvasPos, {Size? size, bool flipX = false, bool flipY = false}) {
    ComponentType? type;
    
    switch (tool) {
      case CanvasTool.rectangle: type = ComponentType.rectangle; break;
      case CanvasTool.circle: type = ComponentType.circle; break;
      case CanvasTool.diamond: type = ComponentType.diamond; break;
      // Arrow is now a connector tool, not a component creator
      case CanvasTool.arrow: return; 
      case CanvasTool.line: type = ComponentType.line; break;
      case CanvasTool.text: type = ComponentType.text; break;
      default: return;
    }
    
    if (type == null) return;
    
    final id = ref.read(canvasProvider.notifier).addComponent(
      type,
      canvasPos,
      size: size ?? const Size(80, 64),
      flipX: flipX,
      flipY: flipY,
    );
    
    if (tool == CanvasTool.text) {
      setState(() {
        _editingComponentId = id;
      });
    }
  }

  void _resizeComponentToFitText(SystemComponent component, String text) {
    // Only resize sketchy components or text (standard ones are fixed size usually)
    if (!component.type.isSketchy && component.type != ComponentType.text) return;

    final style = component.type == ComponentType.text 
        ? const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)
        : GoogleFonts.architectsDaughter(fontSize: 14, fontWeight: FontWeight.w500);

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // Min sizes & Padding
    double minW = 80.0;
    double minH = 64.0;
    double paddingX = 50.0; // Increased padding to prevent text clipping
    double paddingY = 32.0; // Extra for shape

    if (component.type == ComponentType.text) {
        minW = 20; minH = 20; paddingX = 24; paddingY = 12;
    }

    final newW = math.max(minW, textPainter.width + paddingX);
    final newH = math.max(minH, textPainter.height + paddingY);
    
    // Only update if dimensions changed significantly
    if ((newW - component.size.width).abs() > 2 || (newH - component.size.height).abs() > 2) {
       ref.read(canvasProvider.notifier).resizeComponent(component.id, Size(newW, newH));
    }
  }

  void _finishDrawing(CanvasTool tool) {
    if (_drawStartPos == null || _drawEndPos == null) return;
    
    // Arrow tool no longer draws shapes via drag
    if (tool == CanvasTool.arrow) {
       setState(() {
        _drawStartPos = null;
        _drawEndPos = null;
      });
      return;
    }

    // Calculate rect and ensure positive size
    final rect = Rect.fromPoints(_drawStartPos!, _drawEndPos!);

    // Check for flip (negative direction)
    final flipX = _drawEndPos!.dx < _drawStartPos!.dx;
    final flipY = _drawEndPos!.dy < _drawStartPos!.dy;
    
    if (rect.width < 10 && rect.height < 10) {
      // Treat as a simple click
      _addComponentAt(tool, _drawStartPos! - const Offset(40, 32), size: const Size(80, 64));
    } else {
      // Use the dragged area, preserving direction via flip flags
      _addComponentAt(tool, rect.topLeft, size: rect.size, flipX: flipX, flipY: flipY);
    }
    
    setState(() {
      _drawStartPos = null;
      _drawEndPos = null;
    });

    // Revert tool to select after drawing any shape
    ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
  }



  Widget _buildDrawingPreview(CanvasTool tool) {
    if (_drawStartPos == null || _drawEndPos == null) return const SizedBox.shrink();
    
    final rect = Rect.fromPoints(_drawStartPos!, _drawEndPos!);
    
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primary, width: 2),
          borderRadius: tool == CanvasTool.circle 
              ? BorderRadius.circular(math.max(rect.width, rect.height)) 
              : BorderRadius.circular(4),
          color: AppTheme.primary.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  void _showConnectionTypeDialog(String sourceId, String targetId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ConnectionTypeSheet(
        onSelect: (direction) {
          final error = ref.read(canvasProvider.notifier).connectTo(targetId, direction: direction);
          Navigator.pop(context);
          
          if (error != null) {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error),
                backgroundColor: AppTheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onCancel: () {
          ref.read(canvasProvider.notifier).cancelConnecting();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showComponentOptions(SystemComponent component) {
    debugPrint('Show Component Options: ${component.id} (${component.type.displayName})');
    ref.read(canvasProvider.notifier).selectComponent(component.id);
    setState(() {
      _selectedComponentForSidebar = component;
      _showSettingsSidebar = true;
    });
  }

  void _closeSidebar() {
    setState(() {
      _showSettingsSidebar = false;
      _selectedComponentForSidebar = null;
    });
  }

  Widget _buildSettingsSidebar(SystemComponent component) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.border.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(-5, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.settings_outlined, color: AppTheme.primary, size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Component Settings',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _closeSidebar,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _ComponentSheet(component: component),
          ),
        ],
      ),
    );
  }

  void _showConnectionOptions(Connection connection) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ConnectionOptionsSheet(
        connection: connection,
        onDelete: () {
          ref.read(canvasProvider.notifier).removeConnection(connection.id);
          Navigator.pop(context);
        },
        onToggleDirection: () {
          // Toggle between uni and bidirectional
          final newDirection = connection.direction == ConnectionDirection.unidirectional
              ? ConnectionDirection.bidirectional
              : ConnectionDirection.unidirectional;
          ref.read(canvasProvider.notifier).updateConnectionDirection(connection.id, newDirection);
          Navigator.pop(context);
        },
      ),
    );
  }

  MouseCursor _getCursorForTool(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.hand:
        return SystemMouseCursors.grab;
      case CanvasTool.arrow:
        return SystemMouseCursors.click;
      case CanvasTool.eraser:
        return SystemMouseCursors.forbidden; 
      case CanvasTool.select:
        return SystemMouseCursors.basic;
      case CanvasTool.text:
         return SystemMouseCursors.text;
      default:
        return SystemMouseCursors.precise; 
    }
  }

  String _formatBudget(int budgetPerMonth) {
    if (budgetPerMonth >= 1000000) {
      return '${(budgetPerMonth / 1000000).toStringAsFixed(1)}M';
    }
    if (budgetPerMonth >= 1000) {
      return '${(budgetPerMonth / 1000).toStringAsFixed(1)}K';
    }
    return budgetPerMonth.toString();
  }

  Future<void> _showBudgetDialog(Problem problem) async {
    final controller = TextEditingController(
      text: problem.constraints.budgetPerMonth.toString(),
    );

    final result = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Set Monthly Budget',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'e.g. 50000',
            prefixText: '\$',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
              final parsed = int.tryParse(raw);
              if (parsed == null || parsed <= 0) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context, parsed);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;
    ref.read(currentProblemProvider.notifier).state = problem.copyWith(
      constraints: problem.constraints.copyWith(budgetPerMonth: result),
    );
  }
}

// ======== Helper Widgets ========

class _GridPainter extends CustomPainter {
  final Color color;
  final bool isCyberpunk;

  _GridPainter({
    required this.color,
    this.isCyberpunk = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isCyberpunk ? color.withValues(alpha: 0.3) : color
      ..strokeWidth = isCyberpunk ? 0.8 : 1.0;
      
    if (isCyberpunk) {
      // Add a glow effect to the grid
      paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);
    }

    const gridSize = 100.0;
    
    // Draw dot grid
    for (double x = 0; x <= size.width; x += gridSize) {
      for (double y = 0; y <= size.height; y += gridSize) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PreviewCablePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _PreviewCablePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.lineTo(end.dx, end.dy);
    
    canvas.drawPath(path, paint);
    
    // Draw endpoint dot
    final dotPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(end, 4, dotPaint);

    // Draw arrow at end to indicate direction
    _drawArrow(canvas, start, end, AppTheme.primary.withValues(alpha: 0.6));
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const arrowSize = 12.0;
    const arrowAngle = math.pi / 5;

    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - arrowSize * math.cos(angle - arrowAngle),
        to.dy - arrowSize * math.sin(angle - arrowAngle),
      )
      ..lineTo(
        to.dx - arrowSize * math.cos(angle + arrowAngle),
        to.dy - arrowSize * math.sin(angle + arrowAngle),
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PreviewCablePainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}



class _ConnectionPoint extends StatelessWidget {
  final bool isActive;
  final bool isReceiver;
  final bool isHovered;
  final bool showGhost; // New: Shows when this is a valid target
  final VoidCallback? onDragStart;
  final Function(Offset)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback? onTap;

  const _ConnectionPoint({
    this.isActive = false,
    this.isReceiver = false,
    this.isHovered = false,
    this.showGhost = false,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Colors
    final baseColor = isHovered 
        ? AppTheme.success 
        : (isActive ? AppTheme.primary : AppTheme.surface);
    
    final borderColor = isHovered 
        ? AppTheme.success 
        : (isActive 
            ? AppTheme.primary 
            : isReceiver 
                ? AppTheme.success.withValues(alpha: 0.5) 
                : showGhost 
                    ? AppTheme.textMuted.withValues(alpha: 0.5) // Ghost border
                    : AppTheme.textMuted);

    // Hit target size (invisible container)
    return GestureDetector(
      onTap: onTap,
      onPanStart: onDragStart != null ? (_) => onDragStart!() : null,
      onPanUpdate: onDragUpdate != null ? (d) => onDragUpdate!(d.globalPosition) : null,
      onPanEnd: onDragEnd != null ? (_) => onDragEnd!() : null,
      behavior: HitTestBehavior.translucent, // Ensure touches are caught even if empty
      child: Container(
        width: 44, // Large hit target recommended for touch
        height: 44,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isHovered ? 18 : (showGhost ? 14 : 12),
          height: isHovered ? 18 : (showGhost ? 14 : 12),
          decoration: BoxDecoration(
            color: showGhost && !isHovered ? AppTheme.surface : baseColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: isHovered ? 2.0 : (showGhost ? 1.5 : 1.0),
            ),
            boxShadow: isHovered || showGhost ? [
              BoxShadow(
                color: (isHovered ? AppTheme.success : AppTheme.textPrimary)
                    .withValues(alpha: 0.15),
                blurRadius: isHovered ? 8 : 4,
                spreadRadius: 2,
              )
            ] : null,
          ),
          child: isReceiver || showGhost
              ? Icon(
                  Icons.arrow_left, 
                  size: isHovered ? 12 : (showGhost ? 10 : 8), 
                  color: isHovered 
                      ? Colors.white 
                      : (showGhost ? AppTheme.textMuted : AppTheme.success),
                )
              : null,
        ),
      ),
    );
  }
}

class _ConnectingIndicator extends StatelessWidget {
  final VoidCallback onCancel;

  const _ConnectingIndicator({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Animate(
      effects: const [FadeEffect(), SlideEffect(begin: Offset(0, -0.5))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'Select component to connect',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionTypeSheet extends StatelessWidget {
  final Function(ConnectionDirection) onSelect;
  final VoidCallback onCancel;

  const _ConnectionTypeSheet({
    required this.onSelect,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Connection Type',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TypeOption(
                  icon: Icons.arrow_forward,
                  label: 'One-way',
                  sublabel: 'Request → Response',
                  onTap: () => onSelect(ConnectionDirection.unidirectional),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TypeOption(
                  icon: Icons.swap_horiz,
                  label: 'Two-way',
                  sublabel: 'Bidirectional',
                  onTap: () => onSelect(ConnectionDirection.bidirectional),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _TypeOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionOptionsSheet extends StatelessWidget {
  final Connection connection;
  final VoidCallback onDelete;
  final VoidCallback onToggleDirection;

  const _ConnectionOptionsSheet({
    required this.connection,
    required this.onDelete,
    required this.onToggleDirection,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Connection Options',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(
              connection.direction == ConnectionDirection.unidirectional
                  ? Icons.swap_horiz
                  : Icons.arrow_forward,
              color: AppTheme.primary,
            ),
            title: Text(
              connection.direction == ConnectionDirection.unidirectional
                  ? 'Make Bidirectional'
                  : 'Make One-way',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            onTap: onToggleDirection,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppTheme.error),
            title: const Text(
              'Delete Connection',
              style: TextStyle(color: AppTheme.error),
            ),
            onTap: onDelete,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ComponentSheet extends ConsumerStatefulWidget {
  final SystemComponent component;

  const _ComponentSheet({required this.component});

  @override
  ConsumerState<_ComponentSheet> createState() => _ComponentSheetState();
}

class _ComponentSheetState extends ConsumerState<_ComponentSheet> {
  late int _instances;
  late int _capacity;
  late TextEditingController _nameController;
  late String? _algorithm;
  late bool _replication;
  late int _replicationFactor;
  late String? _replicationStrategy;
  late bool _sharding;
  late String? _shardingStrategy;
  late int _partitionCount;
  late bool _consistentHashing;
  late int _cacheTtl;
  late String? _dbSchema;
  late bool _showSchema;
  
  // New resilience properties
  late bool _rateLimiting;
  late int? _rateLimitRps;
  late bool _circuitBreaker;
  late bool _retries;
  late bool _dlq;
  late int? _quorumRead;

  late int? _quorumWrite;
  late String _region;
  
  // Detailed Visualization
  late ComponentDisplayMode _displayMode;
  late List<ShardConfig> _shardConfigs;
  late List<PartitionConfig> _partitionConfigs;
  late ReplicationType _replicationType;

  @override
  void initState() {
    super.initState();
    final config = widget.component.config;
    _instances = config.instances;
    _capacity = config.capacity;
    _nameController = TextEditingController(text: widget.component.customName ?? widget.component.type.displayName);
    _algorithm = config.algorithm;
    _replication = config.replication;
    _replicationFactor = config.replicationFactor;
    _replicationStrategy = config.replicationStrategy;
    _sharding = config.sharding;
    _shardingStrategy = config.shardingStrategy;
    _partitionCount = config.partitionCount;
    _consistentHashing = config.consistentHashing;
    _cacheTtl = config.cacheTtlSeconds;
    _dbSchema = config.dbSchema;
    _showSchema = config.showSchema;
    _rateLimiting = config.rateLimiting;
    _rateLimitRps = config.rateLimitRps;
    _circuitBreaker = config.circuitBreaker;
    _retries = config.retries;
    _dlq = config.dlq;
    _quorumRead = config.quorumRead;

    _quorumWrite = config.quorumWrite;
    _region = config.regions.isNotEmpty ? config.regions.first : 'us-east-1';
    
    _displayMode = config.displayMode;
    _shardConfigs = List.from(config.shardConfigs);
    _partitionConfigs = List.from(config.partitionConfigs);
    _replicationType = config.replicationType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.component.type.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.component.type.icon, color: widget.component.type.color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.component.customName ?? widget.component.type.displayName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Scaling & Distribution Section
            _buildSectionHeader('DEPLOYMENT'),
            _DropdownRow(
              label: 'Deployment Region',
              value: _region,
              options: const {
                'us-east-1': 'US East (N. Virginia)',
                'us-west-2': 'US West (Oregon)',
                'eu-central-1': 'Europe (Frankfurt)',
                'ap-southeast-1': 'Asia Pacific (Singapore)',
              },
              onChanged: (val) { if(val != null) { setState(() => _region = val); _updateConfig(); } },
            ),
            const SizedBox(height: 12),

            _buildSectionHeader('ARCHITECTURE VISUALIZATION'),
            _DropdownRow(
              label: 'Display Mode',
              value: _displayMode.name,
              options: const {
                'collapsed': 'Collapsed (Icon)',
                'expanded': 'Expanded (Basic)',
                'detailed': 'Detailed (Shards/Partitions)',
              },
              onChanged: (val) {
                 if(val != null) {
                   setState(() {
                     _displayMode = ComponentDisplayMode.values.firstWhere((e) => e.name == val);
                   });
                   _updateConfig();
                 }
              },
            ),
            if (_displayMode == ComponentDisplayMode.detailed) ...[
               const SizedBox(height: 12),
               const Text('Shards', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
               ..._shardConfigs.map((shard) => Row(
                 children: [
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(shard.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                         Text(shard.keyRange, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                       ],
                     ),
                   ),
                   IconButton(
                     icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                     onPressed: () {
                        setState(() {
                          _shardConfigs.remove(shard);
                        });
                        _updateConfig();
                     },
                   ),
                 ],
               )),
               Align(
                 alignment: Alignment.centerLeft,
                 child: TextButton.icon(
                   icon: const Icon(Icons.add, size: 16),
                   label: const Text('Add Shard'),
                   onPressed: () {
                     setState(() {
                       _shardConfigs.add(ShardConfig(
                         id: const Uuid().v4(),
                         name: 'Shard ${_shardConfigs.length + 1}',
                         keyRange: 'Range ${_shardConfigs.length + 1}',
                       ));
                     });
                     _updateConfig();
                   },
                 ),
               ),
               
               const Divider(height: 16),
               
               const Text('Partitions (Primary)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
               ..._partitionConfigs.map((p) => Row(
                 children: [
                    Expanded(child: Text('${p.tableName} (${p.partitions.length})', style: const TextStyle(color: Colors.white, fontSize: 12))),
                    IconButton(
                     icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                     onPressed: () {
                        setState(() {
                          _partitionConfigs.remove(p);
                        });
                        _updateConfig();
                     },
                   ),
                 ],
               )),
               Align(
                 alignment: Alignment.centerLeft,
                 child: TextButton.icon(
                   icon: const Icon(Icons.add, size: 16),
                   label: const Text('Add Partitioned Table'),
                   onPressed: () {
                     setState(() {
                       _partitionConfigs.add(PartitionConfig(
                         tableName: 'table_${_partitionConfigs.length + 1}',
                         partitionKey: 'id',
                         partitions: ['p1', 'p2', 'p3'],
                       ));
                     });
                     _updateConfig();
                   },
                 ),
               ),

               const SizedBox(height: 8),
               _DropdownRow(
                  label: 'Replication Type',
                  value: _replicationType.name,
                  options: const {
                    'none': 'None',
                    'synchronous': 'Synchronous',
                    'asynchronous': 'Asynchronous',
                    'streaming': 'Streaming',
                  },
                  onChanged: (val) {
                    if(val != null) {
                      setState(() {
                        _replicationType = ReplicationType.values.firstWhere((e) => e.name == val);
                      });
                      _updateConfig();
                    }
                  },
                ),
            ],

            const SizedBox(height: 12),

            _buildSectionHeader('SCALING & DISTRIBUTION'),
            _ConfigRow(
              label: 'Replicas / Instances',
              value: '$_instances',
              onMinus: () { setState(() => _instances = (_instances - 1).clamp(1, 100)); _updateConfig(); },
              onPlus: () { setState(() => _instances = (_instances + 1).clamp(1, 100)); _updateConfig(); },
            ),
            const SizedBox(height: 12),
            _ConfigRow(
              label: 'Node Capacity (RPS)',
              value: _formatCapacity(_capacity),
              onMinus: () { setState(() => _capacity = (_capacity - 500).clamp(100, 1000000)); _updateConfig(); },
              onPlus: () { setState(() => _capacity = (_capacity + 500).clamp(100, 1000000)); _updateConfig(); },
            ),
            const SizedBox(height: 12),
  
            // Sharding & Partitioning
            if (widget.component.type.category == ComponentCategory.storage || 
                widget.component.type.category == ComponentCategory.messaging) ...[
              _SwitchRow(
                label: 'Enable Sharding / Partitioning',
                value: _sharding,
                onChanged: (val) { setState(() => _sharding = val); _updateConfig(); },
              ),
              if (_sharding) ...[
                const SizedBox(height: 8),
                _ConfigRow(
                  label: 'Partition / Shard Count',
                  value: '$_partitionCount',
                  onMinus: () { setState(() => _partitionCount = (_partitionCount - 1).clamp(1, 64)); _updateConfig(); },
                  onPlus: () { setState(() => _partitionCount = (_partitionCount + 1).clamp(1, 64)); _updateConfig(); },
                ),
                const SizedBox(height: 8),
                _SwitchRow(
                  label: 'Consistent Hashing',
                  value: _consistentHashing,
                  onChanged: (val) { setState(() => _consistentHashing = val); _updateConfig(); },
                ),
              ],
              const SizedBox(height: 12),
            ],
  
            // Replication & Consistency
            _buildSectionHeader('CONSISTENCY & HIGH AVAILABILITY'),
            _SwitchRow(
              label: 'Enable Replication',
              value: _replication,
              onChanged: (val) { setState(() => _replication = val); _updateConfig(); },
            ),
            if (_replication) ...[
              const SizedBox(height: 8),
              _DropdownRow(
                label: 'Replication Strategy',
                value: _replicationStrategy ?? 'Leader-Follower',
                options: const {
                  'Leader-Follower': 'Leader-Follower (Master-Slave)',
                  'Multi-Leader': 'Multi-Leader / Multi-Master',
                  'Leaderless': 'Leaderless (Dynamo-style)',
                },
                onChanged: (val) { setState(() => _replicationStrategy = val); _updateConfig(); },
              ),
              const SizedBox(height: 8),
              _ConfigRow(
                label: 'Replication Factor',
                value: '$_replicationFactor',
                onMinus: () { setState(() => _replicationFactor = (_replicationFactor - 1).clamp(1, 7)); _updateConfig(); },
                onPlus: () { setState(() => _replicationFactor = (_replicationFactor + 1).clamp(1, 7)); _updateConfig(); },
              ),
            ],
            const SizedBox(height: 12),
  
            // Conditional Configs
            if (widget.component.type == ComponentType.loadBalancer) ...[
              _DropdownRow(
                label: 'Balancing Strategy',
                value: _algorithm ?? 'round_robin',
                options: const {
                  'round_robin': 'Round Robin',
                  'least_conn': 'Least Connections',
                  'ip_hash': 'IP Hash',
                  'consistent_hashing': 'Consistent Hashing',
                },
                onChanged: (val) { setState(() => _algorithm = val); _updateConfig(); },
              ),
              const SizedBox(height: 12),
            ],
  
            // Resilience & Reliability Section
            _buildSectionHeader('RESILIENCE & RELIABILITY'),
            _SwitchRow(label: 'Circuit Breaker', value: _circuitBreaker, onChanged: (val) { setState(() => _circuitBreaker = val); _updateConfig(); }),
            _SwitchRow(label: 'Automatic Retries (with Jitter)', value: _retries, onChanged: (val) { setState(() => _retries = val); _updateConfig(); }),
            if (widget.component.type.category == ComponentCategory.messaging || widget.component.type == ComponentType.worker)
              _SwitchRow(label: 'Dead Letter Queue (DLQ)', value: _dlq, onChanged: (val) { setState(() => _dlq = val); _updateConfig(); }),
            const SizedBox(height: 12),
  
            // Traffic Control Section
            _buildSectionHeader('TRAFFIC CONTROL'),
            _SwitchRow(label: 'Rate Limiting', value: _rateLimiting, onChanged: (val) { setState(() => _rateLimiting = val); _updateConfig(); }),
            if (_rateLimiting) ...[
              const SizedBox(height: 8),
              _ConfigRow(
                label: 'Max RPS (Throttle)',
                value: '${_rateLimitRps ?? 1000}',
                onMinus: () { setState(() => _rateLimitRps = ((_rateLimitRps ?? 1000) - 100).clamp(10, 100000)); _updateConfig(); },
                onPlus: () { setState(() => _rateLimitRps = ((_rateLimitRps ?? 1000) + 100).clamp(10, 100000)); _updateConfig(); },
              ),
            ],
            const SizedBox(height: 12),
  
            if (widget.component.type == ComponentType.database) ...[
               const SizedBox(height: 12),
               // Schema Editor
               _buildSectionHeader('DATABASE SCHEMA'),
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                 decoration: BoxDecoration(
                   color: AppTheme.surfaceLight,
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: AppTheme.border),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     _SwitchRow(label: 'Show on Canvas', value: _showSchema, onChanged: (val) { setState(() => _showSchema = val); _updateConfig(); }),
                     const Divider(height: 1),
                     TextField(
                       controller: TextEditingController(text: _dbSchema),
                       maxLines: 4,
                       style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                       decoration: const InputDecoration(
                         border: InputBorder.none,
                         hintText: 'CREATE TABLE users (\n  id UUID PRIMARY KEY,\n  email VARCHAR(255)\n);',
                         hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                       ),
                       onChanged: (val) { _dbSchema = val; _updateConfig(); },
                     ),
                   ],
                 ),
               ),
               const SizedBox(height: 12),
               DbModelingPanel(
                 embedded: true,
               ),
               const SizedBox(height: 12),
            ],
  
            if (widget.component.type == ComponentType.cache || widget.component.type == ComponentType.apiGateway) ...[
              _buildSectionHeader('CACHING'),
              Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   const Text('Cache TTL (s)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                   Row(
                     children: [
                       Text('$_cacheTtl', style: const TextStyle(fontWeight: FontWeight.bold)),
                       Slider(
                         value: _cacheTtl.toDouble(),
                         min: 0,
                         max: 3600,
                         onChanged: (val) { setState(() => _cacheTtl = val.toInt()); _updateConfig(); },
                       ),
                     ],
                   ),
                 ],
               ),
               const SizedBox(height: 12),
            ],
  
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 24),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppTheme.textMuted.withValues(alpha: 0.5),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _updateConfig() {
    ref.read(canvasProvider.notifier).updateComponentConfig(
      widget.component.id,
      widget.component.config.copyWith(
        instances: _instances,
        capacity: _capacity,
        algorithm: _algorithm,
        replication: _replication,
        replicationFactor: _replicationFactor,
        replicationStrategy: _replicationStrategy,
        sharding: _sharding,
        shardingStrategy: _shardingStrategy,
        partitionCount: _partitionCount,
        consistentHashing: _consistentHashing,
        cacheTtlSeconds: _cacheTtl,
        dbSchema: _dbSchema,
        showSchema: _showSchema,
        rateLimiting: _rateLimiting,
        rateLimitRps: _rateLimitRps,
        circuitBreaker: _circuitBreaker,
        retries: _retries,
        dlq: _dlq,
        quorumRead: _quorumRead,
        quorumWrite: _quorumWrite,
        regions: [_region],
        displayMode: _displayMode,
        shardConfigs: _shardConfigs,
        partitionConfigs: _partitionConfigs,
        replicationType: _replicationType,
      ),
    );
  }

  String _formatCapacity(int cap) {
    if (cap >= 1000000) return '${(cap / 1000000).toStringAsFixed(1)}M';
    if (cap >= 1000) return '${(cap / 1000).toStringAsFixed(1)}K';
    return cap.toString();
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label, 
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.8), 
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              activeColor: AppTheme.primary,
              activeTrackColor: AppTheme.primary.withValues(alpha: 0.3),
              inactiveThumbColor: AppTheme.textMuted,
              inactiveTrackColor: AppTheme.surfaceLight,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: value,
          dropdownColor: AppTheme.surface,
          underline: const SizedBox.shrink(),
          onChanged: onChanged,
          isExpanded: false,
          items: options.entries.map((e) {
            return DropdownMenuItem(
              value: e.key,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  e.value, 
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _ConfigRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label, 
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.8), 
                fontSize: 15,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepperButton(icon: Icons.remove, onTap: onMinus),
                SizedBox(
                  width: 60,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StepperButton(icon: Icons.add, onTap: onPlus),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 16),
      ),
    );
  }
}
