import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/component.dart';
import '../models/custom_component.dart';
import '../models/canvas_state.dart';
import '../models/connection.dart';
import '../providers/game_provider.dart';
import '../data/progress_repository.dart';

/// Provider for the editor's canvas state
final componentEditorCanvasProvider = StateNotifierProvider.autoDispose<ComponentEditorNotifier, CanvasState>((ref) {
  // We pass a dummy repository because we override the save logic
  return ComponentEditorNotifier(ref, ProgressRepository()); 
});

/// Adapter that makes CanvasNotifier work for Custom Component Editing
class ComponentEditorNotifier extends CanvasNotifier {
  CustomComponentDefinition? _activeDefinition;
  Function(CustomComponentDefinition)? _onUpdate;

  ComponentEditorNotifier(Ref ref, ProgressRepository repo) : super(repo, ref);

  /// Initialize with a definition to edit
  void  loadDefinition(CustomComponentDefinition definition, {Function(CustomComponentDefinition)? onUpdate}) {
    _activeDefinition = definition;
    _onUpdate = onUpdate;

    // Map InternalNodes to SystemComponents
    final components = definition.internalNodes.map((node) {
      return SystemComponent(
        id: node.id,
        type: node.type,
        position: node.relativePosition,
        size: node.size,
        config: node.config,
        customName: node.label,
      );
    }).toList();

    // Map InternalConnections to Connections
    final connections = definition.internalConnections.map((conn) {
      return Connection(
        id: conn.id,
        sourceId: conn.sourceNodeId,
        targetId: conn.targetNodeId,
        type: conn.type,
        direction: ConnectionDirection.unidirectional,
      );
    }).toList();

    state = CanvasState(
      components: components,
      connections: connections,
      panOffset: const Offset(0, 0), // Start centered or at 0,0
      scale: 1.0,
    );
  }

  /// Override save to update the definition instead of disk
  @override
  Future<void> saveAs(String name, String problemId) async {
    // No-op or update name
  }

  // We capture every state change explicitly in overrides if needed,
  // but CanvasNotifier updates `state` directly. We can just listen to state changes
  // or override methods that modify state to sync back.
  // Actually, easiest is to expose a 'getDefinition' or sync on every valid change.
  
  @override 
  String addComponent(ComponentType type, Offset position, {Size? size, bool flipX = false, bool flipY = false}) {
     final id = super.addComponent(type, position, size: size, flipX: flipX, flipY: flipY);
     _syncToDefinition();
     return id;
  }

  @override
  void moveComponent(String id, Offset position) {
    super.moveComponent(id, position);
    _syncToDefinition();
  }
  
  @override
  void resizeComponent(String id, Size size) {
    super.resizeComponent(id, size);
    _syncToDefinition();
  }

  @override
  void removeComponent(String id) {
    super.removeComponent(id);
    _syncToDefinition();
  }

  @override
  String? connect(String sourceId, String targetId) {
    final id = super.connect(sourceId, targetId);
    _syncToDefinition();
    return id;
  }

  @override
  void removeConnection(String connectionId) {
    super.removeConnection(connectionId);
    _syncToDefinition();
  }

  void _syncToDefinition() {
    if (_activeDefinition == null || _onUpdate == null) return;

    final updatedNodes = state.components.map((c) {
      return InternalNode(
        id: c.id,
        label: c.customName ?? c.type.displayName,
        type: c.type,
        relativePosition: c.position,
        size: c.size,
        config: c.config,
      );
    }).toList();

    final updatedConnections = state.connections.map((c) {
      return InternalConnection(
        id: c.id,
        sourceNodeId: c.sourceId, 
        targetNodeId: c.targetId,
        type: c.type,
      );
    }).toList();

    final updatedDef = _activeDefinition!.copyWith(
      internalNodes: updatedNodes,
      internalConnections: updatedConnections,
    );

    _activeDefinition = updatedDef;
    _onUpdate!(updatedDef);
  }
}
