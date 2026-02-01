import 'dart:math' as math;
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
import '../../theme/app_theme.dart';
import 'component_node.dart';
import 'connections_layer.dart';
import 'issue_marker.dart';

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
    final isSimulating = simState.isRunning;
    final isConnecting = connectingFromId != null;

    final isSelectionMode = activeTool == CanvasTool.select;
    final isHandMode = activeTool == CanvasTool.hand;
    final isDrawingMode = activeTool == CanvasTool.rectangle || 
                         activeTool == CanvasTool.circle ||
                         activeTool == CanvasTool.diamond ||
                         activeTool == CanvasTool.arrow ||
                         activeTool == CanvasTool.line ||
                         activeTool == CanvasTool.text;
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
              if (activeTool != CanvasTool.select) {
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
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Listener for one-tap add from toolbox
            Consumer(
              builder: (context, ref, _) {
                ref.listen(addComponentTriggerProvider, (prev, next) {
                  if (next != null) {
                    _addComponentAtCenter(next);
                    // Reset trigger
                    ref.read(addComponentTriggerProvider.notifier).state = null;
                  }
                });
                return const SizedBox.shrink();
              },
            ),

            // Main interactive area
            DragTarget<ComponentType>(
              builder: (context, candidateData, rejectedData) {
                final isDragging = candidateData.isNotEmpty;
                
                return Listener(
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent && !isSimulating) {
                      final isControl = HardwareKeyboard.instance.isControlPressed || 
                                       HardwareKeyboard.instance.isMetaPressed;
                      
                      if (isControl) {
                        // 1. Mark as interacting to block external sync
                        _isUserInteracting = true;
                        _scrollEndTimer?.cancel();
                        _scrollEndTimer = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            _isUserInteracting = false;
                            _syncToProvider();
                          }
                        });

                        // 2. Perform Zoom
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
                    panEnabled: !isSimulating,
                    scaleEnabled: !isSimulating,
                    trackpadScrollCausesScale: false, // Unified manual zoom via Listener
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
                      behavior: HitTestBehavior.translucent, // Changed from opaque
                      onTap: () {
                        if (isHandMode) return;
                        ref.read(canvasProvider.notifier).selectComponent(null);
                        setState(() => _editingComponentId = null);
                        _focusNode.requestFocus();
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
                          // Grid (Isolated for performance)
                          RepaintBoundary(
                            child: CustomPaint(
                              size: const Size(10000, 10000),
                              painter: _GridPainter(
                                color: AppTheme.border.withValues(alpha: 0.3),
                              ),
                            ),
                          ),

                          // Connection Lines Layer (Production Ready: Single Painter)
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: ConnectionsLayer(
                                canvasState: canvasState,
                                isSimulating: isSimulating,
                                onTap: (connection) {
                                  if (!isSimulating) {
                                    _showConnectionOptions(connection);
                                  }
                                },
                              ),
                            ),
                          ),

                          // Connecting line preview (elastic cable)
                          if (_draggingFromId != null && _draggingCurrentPos != null)
                            _buildElasticCable(canvasState),

                          // Drawing preview
                          if (_drawStartPos != null && _drawEndPos != null && isDrawingMode)
                            _buildDrawingPreview(activeTool),

                          // Component nodes
                          ...canvasState.components.map((component) {
                            final isSelected = component.id == canvasState.selectedComponentId;
                            final isConnectSource = component.id == canvasState.connectingFromId;
                            final isHovered = _hoveredComponentId == component.id;
                            final isArrowActive = activeTool == CanvasTool.arrow;
                            
                            // Valid target if explicitly connecting OR using Arrow tool and hovering
                            final isValidTarget = (isConnecting && canvasState.connectingFromId != component.id) || 
                                                (isArrowActive && isHovered && !isSimulating);

                            // Show handles if SELECTED (Selection-based interaction)
                            // Handles don't show on text nodes usually, but let's allow it for consistency if needed?
                            // Actually, text connection is niche, but allowed.
                            // User request: "when selected component have four selectors dots"
                            final showHandles = isSelected && !isConnecting && !isSimulating;

                            return Positioned(
                              left: component.position.dx,
                              top: component.position.dy,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  MouseRegion(
                                    onEnter: (_) {
                                      if (!isSimulating && activeTool == CanvasTool.arrow) {
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
                                      // Consumer gestures to prevent canvas panning when interacting with component
                                      onTap: () {
                                        if (activeTool == CanvasTool.eraser) {
                                          ref.read(canvasProvider.notifier).removeComponent(component.id);
                                          // Reset to Select after eraser use
                                          ref.read(canvasToolProvider.notifier).state = CanvasTool.select;
                                          return;
                                        }
                                        if (isHandMode) return;
                                        _onComponentTap(component, isConnecting);
                                        _focusNode.requestFocus();
                                      },
                                      onDoubleTap: isSimulating ? null : () {
                                         // Prevent editing if Arrow tool is active (Connection Focus)
                                         if (activeTool == CanvasTool.arrow) return;

                                         final canEdit = component.type.isSketchy || 
                                                        component.type == ComponentType.text;
                                         
                                         if (canEdit) {
                                            // Enable inline editing
                                            setState(() => _editingComponentId = component.id);
                                            // Ensure selected
                                            if (canvasState.selectedComponentId != component.id) {
                                               ref.read(canvasProvider.notifier).selectComponent(component.id);
                                            }
                                            // Clear any connecting state just in case
                                            ref.read(canvasProvider.notifier).cancelConnecting(); 
                                         } else if (canvasState.selectedComponentId != component.id) {
                                            // Just select if not editable
                                            ref.read(canvasProvider.notifier).selectComponent(component.id);
                                         }
                                      },
                                      onLongPress: (isSimulating || !isSelectionMode) ? null : () => _showComponentOptions(component),
                                      onPanStart: (details) {
                                         if (activeTool == CanvasTool.arrow) {
                                            _onDragConnectStart(component, startPos: _getCanvasPosition(details.globalPosition));
                                         }
                                      }, 
                                      onPanUpdate: (details) {
                                         if (activeTool == CanvasTool.arrow) {
                                            _onDragConnectUpdate(details.globalPosition);
                                            return;
                                         }
                                         if (!isSimulating && isSelectionMode) {
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
                                          child: ComponentNode(
                                            component: component,
                                            isSelected: isSelected,
                                            isConnecting: isConnectSource,
                                            isValidTarget: isValidTarget,
                                            isEditing: _editingComponentId == component.id,
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
                                  

                                  
                                  // Connection handles removed per user request
                                ],
                              ),
                            ); // Positioned
                          }),

                          // Issue Markers
                          ...simState.failures.map((failure) {
                            final component = canvasState.getComponent(failure.componentId);
                            if (component == null) return const SizedBox.shrink();
                            return IssueMarker(
                              failure: failure,
                              position: component.position,
                            );
                          }),

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
                                    border: Border.all(
                                      color: AppTheme.primary.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Icon(
                                    candidateData.first?.icon ?? Icons.add,
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
                ref.read(canvasProvider.notifier).addComponent(
                  details.data,
                  Offset(canvasPos.dx.clamp(50, 9900), canvasPos.dy.clamp(50, 9900)),
                );
                setState(() => _dragPreviewPosition = null);
              },
            ),

            // Connecting mode overlay - hidden for stealth mode
            // if (isConnecting)
            //   Positioned(
            //     top: 8,
            //     left: 0,
            //     right: 0,
            //     child: Center(
            //       child: _ConnectingIndicator(
            //         onCancel: () => ref.read(canvasProvider.notifier).cancelConnecting(),
            //       ),
            //     ),
            //   ),

            // Empty state
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
                    Text(
                      'Drag components here',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pinch to zoom • Drag to pan',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.3),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
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
    setState(() {
      _draggingFromId = component.id;
      _dragStartPos = startPos ?? Offset(component.position.dx + 80, component.position.dy + 32);
      _draggingCurrentPos = _dragStartPos;
      _editingComponentId = null; // Clear any active editing
    });
  }

  void _onDragConnectUpdate(Offset globalPos) {
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
        minW = 20; minH = 20; paddingX = 24; paddingY = 8;
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
    ref.read(canvasProvider.notifier).selectComponent(component.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ComponentSheet(component: component),
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
}

// ======== Helper Widgets ========

class _GridPainter extends CustomPainter {
  final Color color;

  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

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
  late int _cacheTtl;
  late String? _dbSchema;
  late bool _showSchema;

  @override
  void initState() {
    super.initState();
    _instances = widget.component.config.instances;
    _capacity = widget.component.config.capacity;
    _nameController = TextEditingController(text: widget.component.customName ?? widget.component.type.displayName);
    _algorithm = widget.component.config.algorithm;
    _replication = widget.component.config.replication;
    _cacheTtl = widget.component.config.cacheTtlSeconds;
    _dbSchema = widget.component.config.dbSchema;
    _showSchema = widget.component.config.showSchema;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.component.type.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.component.type.icon, color: widget.component.type.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Component Name',
                  ),
                  onChanged: (val) {
                    ref.read(canvasProvider.notifier).renameComponent(widget.component.id, val);
                  },
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                color: AppTheme.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Technical Stats
          Text(
            'SYSTEM CONFIGURATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMuted.withValues(alpha: 0.6),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Instance Count
          _ConfigRow(
            label: 'Replicas / Instances',
            value: '$_instances',
            onMinus: () {
              setState(() {
                _instances = (_instances - 1).clamp(1, 100);
              });
              _updateConfig();
            },
            onPlus: () {
              setState(() {
                _instances = (_instances + 1).clamp(1, 100);
              });
              _updateConfig();
            },
          ),
          const SizedBox(height: 12),

          // Capacity
          _ConfigRow(
            label: 'Worker Capacity (RPS)',
            value: _formatCapacity(_capacity),
            onMinus: () {
              setState(() {
                _capacity = (_capacity - 500).clamp(100, 1000000);
              });
              _updateConfig();
            },
            onPlus: () {
              setState(() {
                _capacity = (_capacity + 500).clamp(100, 1000000);
              });
              _updateConfig();
            },
          ),
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
              },
              onChanged: (val) {
                setState(() {
                  _algorithm = val;
                });
                _updateConfig();
              },
            ),
            const SizedBox(height: 12),
          ],

          if (widget.component.type == ComponentType.database) ...[
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const Text('Read Replicas', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                 Switch(
                   value: _replication,
                   activeColor: AppTheme.primary,
                   onChanged: (val) {
                     setState(() {
                       _replication = val;
                     });
                     _updateConfig();
                   },
                 ),
               ],
             ),
             const SizedBox(height: 12),
             
             // Schema Editor
             const Text('Database Schema', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
             const SizedBox(height: 8),
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
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       const Text('Show on Canvas', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                       Switch(
                         value: _showSchema,
                         activeColor: AppTheme.primary,
                         onChanged: (val) {
                           setState(() {
                             _showSchema = val;
                           });
                           _updateConfig();
                         },
                         materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                       ),
                     ],
                   ),
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
                     onChanged: (val) {
                       _dbSchema = val;
                       _updateConfig(); // Note: Debouncing recommended for texts
                     },
                   ),
                 ],
               ),
             ),
             const SizedBox(height: 12),
          ],

          if (widget.component.type == ComponentType.cache || widget.component.type == ComponentType.apiGateway) ...[
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
                       onChanged: (val) {
                         setState(() {
                           _cacheTtl = val.toInt();
                         });
                         _updateConfig();
                       },
                     ),
                   ],
                 ),
               ],
             ),
             const SizedBox(height: 12),
          ],

          const Divider(height: 32),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(canvasProvider.notifier).removeComponent(widget.component.id);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete Component'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Close Settings'),
                ),
              ),
            ],
          ),
        ],
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
        cacheTtlSeconds: _cacheTtl,
        dbSchema: _dbSchema,
        showSchema: _showSchema,
      ),
    );
  }

  String _formatCapacity(int cap) {
    if (cap >= 1000000) return '${(cap / 1000000).toStringAsFixed(1)}M';
    if (cap >= 1000) return '${(cap / 1000).toStringAsFixed(1)}K';
    return cap.toString();
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
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        DropdownButton<String>(
          value: value,
          dropdownColor: AppTheme.surface,
          underline: const SizedBox.shrink(),
          onChanged: onChanged,
          items: options.entries.map((e) {
            return DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
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
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onMinus,
                icon: const Icon(Icons.remove, size: 14),
                color: AppTheme.textMuted,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              SizedBox(
                width: 45,
                child: Text(
                  value,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: onPlus,
                icon: const Icon(Icons.add, size: 14),
                color: AppTheme.primary,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
