import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/component.dart';
import '../models/connection.dart';
import '../models/problem.dart';
import '../models/metrics.dart';
import '../models/score.dart';
import '../models/chaos_event.dart';
import '../models/custom_component.dart';
import '../data/problems.dart';
import '../models/canvas_state.dart';
export '../models/canvas_state.dart';
import '../data/progress_repository.dart';
import '../simulation/design_validator.dart';
import 'package:flutter/foundation.dart';

const _uuid = Uuid();

/// Current problem/level being played
final currentProblemProvider = StateProvider<Problem>((ref) {
  return Problems.urlShortener;
});

final progressRepositoryProvider = Provider((ref) => ProgressRepository());

/// Canvas state notifier
class CanvasNotifier extends StateNotifier<CanvasState> {
  final ProgressRepository _repository;
  final Ref _ref;
  String? _currentProblemId;
  String? _currentDesignId;
  String? _currentDesignName;

  CanvasNotifier(this._repository, this._ref) : super(const CanvasState());

  String? get currentDesignName => _currentDesignName;

  Future<void> _save() async {
    if (_currentDesignId != null && _currentDesignName != null && _currentProblemId != null) {
      await _repository.saveDesign(_currentDesignId!, _currentDesignName!, _currentProblemId!, state);
    } else if (_currentProblemId != null) {
      await _repository.saveProgress(_currentProblemId!, state);
    }
  }

  /// Save current state as a named design
  Future<void> saveAs(String name, String problemId) async {
    _currentDesignId ??= _uuid.v4();
    _currentDesignName = name;
    _currentProblemId = problemId;
    await _repository.saveDesign(_currentDesignId!, name, problemId, state);
  }

  /// Load a specific design
  Future<void> loadSavedDesign(DesignMetadata meta) async {
    final loadedState = await _repository.loadDesign(meta.id);
    if (loadedState != null) {
      _currentDesignId = meta.id;
      _currentDesignName = meta.name;
      _currentProblemId = meta.problemId;
      state = loadedState;
    }
  }

  /// List all available designs
  Future<List<DesignMetadata>> listDesigns() {
    return _repository.listDesigns();
  }

  /// Delete a saved design
  Future<void> deleteDesign(String id) async {
    await _repository.deleteDesign(id);
    if (_currentDesignId == id) {
      _currentDesignId = null;
      _currentDesignName = null;
    }
  }

  /// Initialize with a problem (existing logic modified to set _currentProblemId)
  void initializeWithProblem(String problemId, {bool forceTestDesign = false}) async {
    _currentProblemId = problemId;
    _currentDesignId = null;
    _currentDesignName = null;
    if (forceTestDesign) {
      final loadedSample = await _loadDesignFromAsset('assets/solutions/minimal_design.json');
      if (!loadedSample) {
        state = const CanvasState();
      }
      _save();
      return;
    }

    final loadedState = await _repository.loadProgress(problemId);
    if (loadedState != null) {
      state = loadedState;
      return;
    }

    final loadedSample = await _loadDesignFromAsset('assets/solutions/minimal_design.json');
    if (!loadedSample) {
      state = const CanvasState();
    }
  }

  /// Add a new component to the canvas
  String addComponent(ComponentType type, Offset position, {Size? size, bool flipX = false, bool flipY = false}) {
    final component = SystemComponent(
      id: _uuid.v4(),
      type: type,
      position: position,
      size: size ?? const Size(80, 64),
      config: ComponentConfig.defaultFor(type),
      flipX: flipX,
      flipY: flipY,
    );

    state = state.copyWith(
      components: [...state.components, component],
      selectedComponentId: component.id,
    );
    _save();
    return component.id;
  }

/// Add a custom component to the canvas (expands to internal nodes + connections)
/// Returns a list of all created component IDs
List<String> addCustomComponent(CustomComponentDefinition definition, Offset dropPosition) {
  // Map old internal node IDs to new component IDs
  final Map<String, String> idMapping = {};
  final List<SystemComponent> newComponents = [];
  final List<Connection> newConnections = [];
  
  // Create components for each internal node, positioned relative to drop position
  for (final node in definition.internalNodes) {
    final newId = _uuid.v4();
    idMapping[node.id] = newId;
    
    final component = SystemComponent(
      id: newId,
      type: node.type,
      customName: '${definition.name}: ${node.label}',
      position: dropPosition + node.relativePosition,
      size: const Size(80, 64),
      config: node.config,
      // Store reference to parent custom component for aggregation
      customComponentId: definition.id,
    );
    newComponents.add(component);
  }
  
  // Create connections between internal nodes
  for (final conn in definition.internalConnections) {
    final sourceId = idMapping[conn.sourceNodeId];
    final targetId = idMapping[conn.targetNodeId];
    
    if (sourceId != null && targetId != null) {
      newConnections.add(Connection(
        id: _uuid.v4(),
        sourceId: sourceId,
        targetId: targetId,
        direction: ConnectionDirection.unidirectional,
        type: conn.type,
      ));
    }
  }
  
  // Update state with all new components and connections
  state = state.copyWith(
    components: [...state.components, ...newComponents],
    connections: [...state.connections, ...newConnections],
    selectedComponentId: newComponents.isNotEmpty ? newComponents.first.id : null,
  );
  _save();
  
    return newComponents.map((c) => c.id).toList();
}

/// Add a pre-configured template component to the canvas
String addComponentTemplate(SystemComponent template, Offset position) {
  final component = template.copyWith(
    id: _uuid.v4(), // Generate new ID
    position: position,
  );

  state = state.copyWith(
    components: [...state.components, component],
    selectedComponentId: component.id,
  );
  _save();
  return component.id;
}

  /// Remove a component from the canvas
  void removeComponent(String id) {
    state = state.copyWith(
      components: state.components.where((c) => c.id != id).toList(),
      connections: state.connections
          .where((c) => c.sourceId != id && c.targetId != id)
          .toList(),
      clearSelection: state.selectedComponentId == id,
    );
    _save();
  }

  /// Move a component to a new position
  void moveComponent(String id, Offset position) {
    state = state.copyWith(
      components: state.components.map((c) {
        if (c.id == id) {
          return c.copyWith(position: position);
        }
        return c;
      }).toList(),
    );
    _save();
  }

  /// Select a component
  void selectComponent(String? id) {
    state = state.copyWith(
      selectedComponentId: id,
      clearSelection: id == null,
    );
  }

  /// Update component configuration
  void updateComponentConfig(String id, ComponentConfig config) {
    // Calculate intelligent size based on architecture complexity
    Size newSize = const Size(80, 64);
    
    if (config.displayMode == ComponentDisplayMode.detailed) {
       newSize = const Size(220, 260);
    } else if (config.sharding) {
      // Wider for shards: Base 80 + 25 per partition
      final partitions = config.partitionCount < 1 ? 1 : (config.partitionCount > 4 ? 4 : config.partitionCount);
      newSize = Size(80.0 + (partitions * 25.0), 96);
    } else if (config.replication && config.replicationFactor > 1) {
      // Wide for Leader-Follower diagram
      newSize = const Size(150, 90);
    } else if (config.instances > 1) {
      // Slightly larger box for cluster grid
      newSize = const Size(110, 84);
    }

    state = state.copyWith(
      components: state.components.map((c) {
        if (c.id == id) {
          // Keep custom size if it's vastly different? 
          // For now, snap to architectural size to ensure the visualization looks good.
          return c.copyWith(config: config, size: newSize);
        }
        return c;
      }).toList(),
    );
    _save();
  }

  /// Rename a component
  void renameComponent(String id, String newName) {
    state = state.copyWith(
      components: state.components.map((c) {
        if (c.id == id) {
          return c.copyWith(customName: newName);
        }
        return c;
      }).toList(),
    );
    _save();
  }

  /// Resize a component (e.g. for text fitting)
  void resizeComponent(String id, Size newSize) {
    state = state.copyWith(
      components: state.components.map((c) {
        if (c.id == id) {
          return c.copyWith(size: newSize);
        }
        return c;
      }).toList(),
    );
    _save();
  }

  /// Start connecting from a component
  void startConnecting(String fromId) {
    state = state.copyWith(connectingFromId: fromId);
  }

  /// Complete connection to another component
  /// Returns null if successful, or an error message if invalid
  String? connectTo(String toId, {ConnectionDirection direction = ConnectionDirection.unidirectional, String? fromIdOverride}) {
    final fromId = fromIdOverride ?? state.connectingFromId;
    if (fromId == null) return null;
    if (fromId == toId) {
      state = state.copyWith(clearConnecting: true);
      return null;
    }

    // Check if already connected
    if (state.areConnected(fromId, toId)) {
      state = state.copyWith(clearConnecting: true);
      return null;
    }

    // Validation
    final source = state.getComponent(fromId);
    final target = state.getComponent(toId);

    if (source != null && target != null) {
      final error = source.type.validateConnection(target.type);
      if (error != null) {
        // Return error without clearing connecting state (so they can try again)
        // Or should we clear? Let's clear to reset interaction
        state = state.copyWith(clearConnecting: true);
        return error;
      }
    }

    final connection = Connection(
      id: _uuid.v4(),
      sourceId: fromId,
      targetId: toId,
      direction: direction,
    );

    state = state.copyWith(
      connections: [...state.connections, connection],
      clearConnecting: true,
    );
    _save();
    return null;
  }

  /// Duplicate a component (Visual Scaling)
  String? duplicateComponent(String originalId) {
    final original = state.getComponent(originalId);
    if (original == null) return null;

    // Create new ID
    final newId = _uuid.v4();
    
    // Find smart position to avoid overlap
    Offset newPosition = original.position + const Offset(20, 20); // Default fallback
    
    // Attempt to find a free spot nearby
    // We check 8 directions at varying distances
    bool foundSpot = false;
    final size = original.size;
    final buffer = 20.0;
    
    // Search spiral: Right, Bottom, Left, Top...
    final candidates = [
       original.position + Offset(size.width + buffer, 0), // Right
       original.position + Offset(0, size.height + buffer), // Bottom
       original.position + Offset(size.width + buffer, size.height + buffer), // Bottom-Right
       original.position + Offset(-(size.width + buffer), 0), // Left
       original.position + Offset(0, -(size.height + buffer)), // Top
       original.position + Offset(size.width + buffer, -(size.height + buffer)), // Top-Right
       original.position + Offset(-(size.width + buffer), size.height + buffer), // Bottom-Left
    ];

    for (final candidate in candidates) {
        // Check collision with ALL components
        final candidateRect = Rect.fromLTWH(candidate.dx, candidate.dy, size.width, size.height);
        bool hasCollision = false;
        
        for (final existing in state.components) {
            final existingRect = Rect.fromLTWH(existing.position.dx, existing.position.dy, existing.size.width, existing.size.height);
            // Inflate existing rect slightly to ensure gaps
            if (candidateRect.overlaps(existingRect.inflate(10))) {
                hasCollision = true;
                break;
            }
        }
        
        if (!hasCollision) {
            newPosition = candidate;
            foundSpot = true;
            break;
        }
    }
    
    // If first ring failed, try a second wider ring (simple fallback to further down-right)
    if (!foundSpot) {
       newPosition = original.position + const Offset(50, 50);
    }

    final newComponent = original.copyWith(
      id: newId,
      position: newPosition,
      // Reset status on new component
      customName: original.customName != null ? '${original.customName} (Replica)' : null,
    );

    // Duplicate connections
    final newConnections = <Connection>[];
    
    // 1. Incoming: Anyone connected to Original should also connect to New (Load balancing)
    final incoming = state.connections.where((c) => c.targetId == originalId);
    for (final conn in incoming) {
      newConnections.add(conn.copyWith(
        id: _uuid.v4(),
        targetId: newId,
      ));
    }

    // 2. Outgoing: New should connect to same targets as Original
    final outgoing = state.connections.where((c) => c.sourceId == originalId);
    for (final conn in outgoing) {
      newConnections.add(conn.copyWith(
        id: _uuid.v4(),
        sourceId: newId,
      ));
    }

    state = state.copyWith(
      components: [...state.components, newComponent],
      connections: [...state.connections, ...newConnections],
    );
    _save();
    
    return newId;
  }

  /// Apply an automated fix
  void applyFix(FixType type, String? componentId) {
    if (componentId == null) return;
    
    final component = state.getComponent(componentId);
    if (component == null) return;
    
    var config = component.config;
    
    switch (type) {
      case FixType.enableAutoscaling:
        config = config.copyWith(autoScale: true);
        break;
      case FixType.addCircuitBreaker:
        config = config.copyWith(circuitBreaker: true);
        break;
      case FixType.increaseReplicas:
        // VISUAL SCALING: Instead of just config increment, adding a real node
        // We add 1 replica visually (user can click again for more)
        duplicateComponent(componentId);
        // Also update the original config just in case logic relies on it? 
        // No, if we have multiple nodes, each has 1 instance.
        // But if the original had 1, and we add 1, we now have 2 nodes of 1 instance.
        break;
      case FixType.enableReplication:
        config = config.copyWith(
          replication: true, 
          replicationFactor: config.replicationFactor < 2 ? 2 : config.replicationFactor
        );
        break;
      case FixType.enableRateLimiting:
        config = config.copyWith(rateLimiting: true, rateLimitRps: 1000);
        break;
      case FixType.increaseConnectionPool:
        // Increasing capacity as a proxy for connection pool limits
        config = config.copyWith(capacity: (config.capacity * 1.5).toInt());
        break;
      case FixType.addDlq:
        config = config.copyWith(dlq: true);
        break;
    }
    
    updateComponentConfig(componentId, config);
    
    // OPTIMISTIC FIX: Immediately clear failures from simulation state 
    // so the red banner disappears without waiting for the next tick
    _ref.read(simulationProvider.notifier).clearFailuresForComponent(componentId);
  }

  /// Cancel connecting
  void cancelConnecting() {
    state = state.copyWith(clearConnecting: true);
  }

  /// Remove a connection
  void removeConnection(String id) {
    state = state.copyWith(
      connections: state.connections.where((c) => c.id != id).toList(),
    );
    _save();
  }

  /// Update connection direction
  void updateConnectionDirection(String id, ConnectionDirection direction) {
    state = state.copyWith(
      connections: state.connections.map((c) {
        if (c.id == id) {
          return c.copyWith(direction: direction);
        }
        return c;
      }).toList(),
    );
    _save();
  }

  /// Update component metrics (from simulation)
  void updateMetrics(Map<String, ComponentMetrics> metrics) {
    state = state.copyWith(
      components: state.components.map((c) {
        final newMetrics = metrics[c.id];
        if (newMetrics != null) {
          return c.copyWith(metrics: newMetrics);
        }
        return c;
      }).toList(),
    );
  }

  /// Update connection traffic flow
  void updateConnectionTraffic(Map<String, double> traffic) {
    state = state.copyWith(
      connections: state.connections.map((c) {
        final flow = traffic[c.id];
        if (flow != null) {
          return c.copyWith(trafficFlow: flow);
        }
        return c;
      }).toList(),
    );
  }

  /// Update pan/zoom
  void toggleCyberpunkMode() {
    state = state.copyWith(isCyberpunkMode: !state.isCyberpunkMode);
  }

  /// Update traffic level (0.0 to 1.0)
  void setTrafficLevel(double level) {
    state = state.copyWith(trafficLevel: level.clamp(0.0, 1.0));
    _save();
  }

  /// Toggle error visibility
  void setShowErrors(bool show) {
    state = state.copyWith(showErrors: show);
    _save();
  }

  void updateTransform({Offset? panOffset, double? scale}) {
    state = state.copyWith(
      panOffset: panOffset,
      scale: scale,
    );
    _save();
  }

  /// Zoom in
  void zoomIn() {
    final newScale = (state.scale * 1.2).clamp(0.1, 3.0);
    state = state.copyWith(scale: newScale);
    _save();
  }

  /// Zoom out
  void zoomOut() {
    final newScale = (state.scale / 1.2).clamp(0.1, 3.0);
    state = state.copyWith(scale: newScale);
    _save();
  }

  /// Clear the canvas
  void clear() {
    state = const CanvasState();
    _save();
  }

  /// Replace entire canvas state (for imports)
  void loadState(CanvasState newState) {
    state = newState;
    _save();
  }

  /// Load state for a specific problem
  Future<void> loadForProblem(Problem problem) async {
    _currentProblemId = problem.id;
    
    // Try loading saved progress
    try {
      final savedState = await _repository.loadProgress(problem.id);
      if (savedState != null) {
        state = savedState;
        return;
      }
    } catch (e) {
      // Ignore error for now
    }

    // Default: Reset to initial state for a problem
    // Start with a 'Users' component
    final client = SystemComponent(
      id: _uuid.v4(),
      type: ComponentType.client,
      position: const Offset(50, 300),
      config: ComponentConfig.defaultFor(ComponentType.client),
    );
    
    state = CanvasState(
      components: [client],
    );
  }

  /// Reset to initial state for a problem (Manual Reset)
  void resetForProblem() {
    // Start with a 'Users' component
    final client = SystemComponent(
      id: _uuid.v4(),
      type: ComponentType.client,
      position: const Offset(50, 300),
      config: ComponentConfig.defaultFor(ComponentType.client),
    );
    
    state = CanvasState(
      components: [client],
    );
    _save();
  }

  /// Clear the canvas entirely (Manual Reset)
  void clearCanvas() {
    _currentDesignId = null;
    _currentDesignName = null;
    state = const CanvasState();
    _save();
  }

  /// Load the optimal solution for the problem
  void loadSolution(Problem problem) {
    _currentProblemId = problem.id; // Ensure we save solution if they modify it?
    // Maybe better not to overwrite user progress with solution unless explicitly requested
    // Logic: Loading solution REPLACES current canvas
    
    if (problem.id == 'url_shortener') {
      _loadDesignFromAsset('assets/solutions/url_shortener_solution.json').then((_) => _save());
    } else {
      _save();
    }
    // Add other solutions here
    _save();
  }

  /// Automatically layout components in a hierarchical Left-to-Right Graph (DAG)
  /// Uses Barycenter heuristic for crossing minimization.
  void autoLayout(Size viewportSize) {
    if (state.components.isEmpty) return;

    final layers = <int, List<String>>{};
    final visited = <String>{};
    final nodeDepths = <String, int>{};

    // 0. Pre-processing: Pin unconnected text nodes to nearest neighbors
    final textAttachments = <String, String>{}; // TextId -> HostId
    final textOffsets = <String, Offset>{}; // TextId -> Relative Offset
    final excludedIds = <String>{};

    const double attachThreshold = 200.0; // Distance to consider "attached"

    for (final comp in state.components) {
      if (comp.type == ComponentType.text) {
        // Check if actually connected
        final isConnected = state.connections.any((c) => c.sourceId == comp.id || c.targetId == comp.id);
        if (isConnected) continue;

        // Find nearest non-text neighbor
        SystemComponent? nearest;
        double minDistance = double.infinity;

        // Center of text
        final textCenter = comp.position + Offset(comp.size.width / 2, comp.size.height / 2);

        for (final candidate in state.components) {
          if (candidate.id == comp.id) continue;
          if (candidate.type == ComponentType.text) continue; // Don't attach to other text

          final candidateCenter = candidate.position + Offset(candidate.size.width / 2, candidate.size.height / 2);
          final dist = (textCenter - candidateCenter).distance;

          if (dist < minDistance) {
            minDistance = dist;
            nearest = candidate;
          }
        }

        if (nearest != null && minDistance < attachThreshold) {
          textAttachments[comp.id] = nearest.id;
          textOffsets[comp.id] = comp.position - nearest.position;
          excludedIds.add(comp.id);
        }
      }
    }

    // 1. Identify roots (nodes with no incoming connections from *within* the set of nodes being laid out)
    final layoutCandidates = state.components.where((c) => !excludedIds.contains(c.id)).toList();
    final layoutIds = layoutCandidates.map((c) => c.id).toSet();
    
    final targets = state.connections
        .where((c) => layoutIds.contains(c.sourceId) && layoutIds.contains(c.targetId))
        .map((c) => c.targetId).toSet();
        
    final roots = layoutCandidates
        .where((c) => !targets.contains(c.id))
        .map((c) => c.id)
        .toList();
    
    // Cycle handling / Disconnected graphs: If no roots found but components exist, pick the first one.
    if (roots.isEmpty && layoutCandidates.isNotEmpty) {
      roots.add(layoutCandidates.first.id); 
    }

    // 2. BFS for Layer Assignment (Rank)
    final queue = [...roots];
    for (final root in roots) nodeDepths[root] = 0;

    // Keep track of all nodes to ensure orphans are handled
    // Use layoutCandidates instead of all components
    final allNodeIds = layoutIds;

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final depth = nodeDepths[currentId] ?? 0;
      
      layers.putIfAbsent(depth, () => []).add(currentId);
      visited.add(currentId);
      
      // Find downstream neighbors
      final outgoing = state.connections
          .where((c) => c.sourceId == currentId)
          .map((c) => c.targetId)
          .where((id) => layoutIds.contains(id)); // Only consider nodes in layout
          
      for (final targetId in outgoing) {
        if (!nodeDepths.containsKey(targetId)) {
          nodeDepths[targetId] = depth + 1;
          queue.add(targetId);
        }
      }
    }

    // Handle orphans (nodes not reachable from identified roots)
    for (final id in allNodeIds) {
      if (!nodeDepths.containsKey(id)) {
        nodeDepths[id] = 0;
        layers.putIfAbsent(0, () => []).add(id);
      }
    }

    // 3. Crossing Minimization (Barycenter Heuristic)
    // Sort Rank K based on average position of parents in Rank K-1
    final sortedLayers = layers.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    
    // Virtual positions map for sorting
    final nodeY = <String, double>{};

    for (var i = 0; i < sortedLayers.length; i++) {
      final layerDepth = sortedLayers[i].key;
      final layerNodes = sortedLayers[i].value;

      if (i == 0) {
        // First layer: Keep mostly as is, maybe sort by type?
        layerNodes.sort(); 
      } else {
        // Subsequent layers: Sort by average Y of parents
        layerNodes.sort((a, b) {
           double getAvgParentY(String nodeId) {
             final parents = state.connections
                .where((c) => c.targetId == nodeId)
                .map((c) => c.sourceId)
                .where((id) => nodeY.containsKey(id));
             
             if (parents.isEmpty) return 0.0;
             final sum = parents.map((id) => nodeY[id]!).reduce((a, b) => a + b);
             return sum / parents.length;
           }

           return getAvgParentY(a).compareTo(getAvgParentY(b));
        });
      }

      // Assign virtual Y positions for this layer for next layer's calculation
      for (var j = 0; j < layerNodes.length; j++) {
        nodeY[layerNodes[j]] = j.toDouble();
      }
    }

    // 4. Assign Final Coordinates (Left-to-Right)
    final newComponents = <SystemComponent>[];
    const startX = 5000.0;
    const startY = 5000.0; // Centered
    
    // Spacing tuned to reduce overlap on dense graphs
    const layerSpacingX = 320.0;      // more horizontal separation
    const fixedNodeSpacing = 140.0;   // more vertical gap between nodes
    
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final entry in sortedLayers) {
      final depth = entry.key;
      final ids = entry.value;
      
      // Calculate total height needed for this layer to center it
      double totalLayerHeight = 0;
      final componentHeights = <String, double>{};
      
      for (final id in ids) {
        final comp = state.getComponent(id);
        final height = comp?.size.height ?? 64.0;
        componentHeights[id] = height;
        totalLayerHeight += height + fixedNodeSpacing;
      }
      if (ids.isNotEmpty) totalLayerHeight -= fixedNodeSpacing; // Remove last gap

      var currentY = startY - (totalLayerHeight / 2);
      final xPos = startX + (depth * layerSpacingX);

      for (final id in ids) {
        final comp = state.getComponent(id);
        if (comp != null) {
          final h = componentHeights[id]!;
          
          final pos = Offset(xPos, currentY);
          newComponents.add(comp.copyWith(position: pos));
          
          // Update bounds
          if (pos.dx < minX) minX = pos.dx;
          final rightEdge = pos.dx + comp.size.width;
          if (rightEdge > maxX) maxX = rightEdge;
          
          if (pos.dy < minY) minY = pos.dy;
          final bottomEdge = pos.dy + h;
          if (bottomEdge > maxY) maxY = bottomEdge;
          
          currentY += h + fixedNodeSpacing;
        }
      }
    }
    
    // 4.5 Re-attach pinned text nodes
    for (final textId in textAttachments.keys) {
      final hostId = textAttachments[textId];
      final offset = textOffsets[textId];
      final originalTextComp = state.getComponent(textId);
      
      // Find the host in the NEW layout
      final hostComp = newComponents.cast<SystemComponent?>().firstWhere(
        (c) => c?.id == hostId, 
        orElse: () => null,
      );

      if (hostComp != null && originalTextComp != null && offset != null) {
        final newTextPos = hostComp.position + offset;
        final newTextComp = originalTextComp.copyWith(position: newTextPos);
        newComponents.add(newTextComp);

        // Update bounds for these too
        if (newTextPos.dx < minX) minX = newTextPos.dx;
        final rightEdge = newTextPos.dx + newTextComp.size.width;
        if (rightEdge > maxX) maxX = rightEdge;
        
        if (newTextPos.dy < minY) minY = newTextPos.dy;
        final bottomEdge = newTextPos.dy + newTextComp.size.height;
        if (bottomEdge > maxY) maxY = bottomEdge;
      } else if (originalTextComp != null) {
        // Fallback if host lost (shouldn't happen)
        newComponents.add(originalTextComp);
      }
    }

    // 5. Zoom to Fit
    final contentWidth = maxX - minX + 300; 
    final contentHeight = maxY - minY + 300;
    
    final scaleX = viewportSize.width / contentWidth;
    final scaleY = viewportSize.height / contentHeight;
    final fitScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.2, 1.5);
    
    final contentCenter = Offset(minX + (maxX - minX) / 2, minY + (maxY - minY) / 2);
    final viewportCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
    
    final newOffset = viewportCenter - (contentCenter * fitScale);

    state = state.copyWith(
      components: newComponents,
      scale: fitScale,
      panOffset: newOffset,
    );
    _save();
  }

  Future<bool> _loadDesignFromAsset(String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final components = (data['components'] as List)
          .map((c) => SystemComponent.fromJson(c))
          .toList();

      final connections = (data['connections'] as List)
          .map((c) => Connection.fromJson(c))
          .toList();

      Offset? panOffset;
      double? scale;
      final viewState = data['viewState'] as Map<String, dynamic>?;
      if (viewState != null) {
        final panJson = viewState['panOffset'] as Map<String, dynamic>?;
        if (panJson != null) {
          panOffset = Offset(
            (panJson['x'] as num?)?.toDouble() ?? 0.0,
            (panJson['y'] as num?)?.toDouble() ?? 0.0,
          );
        }
        scale = (viewState['scale'] as num?)?.toDouble();
      }

      state = state.copyWith(
        components: components,
        connections: connections,
        panOffset: panOffset ?? state.panOffset,
        scale: scale ?? state.scale,
      );
      return true;
    } catch (e, stack) {
      debugPrint('Error loading design from asset ($assetPath): $e\n$stack');
      return false;
    }
  }

}

final canvasProvider = StateNotifierProvider<CanvasNotifier, CanvasState>((ref) {
  final repo = ref.watch(progressRepositoryProvider);
  return CanvasNotifier(repo, ref);
});

/// Simulation state
enum SimulationStatus {
  idle,
  running,
  paused,
  completed,
  failed, // New strict failure status
}

class SimulationState {
  final SimulationStatus status;
  final GlobalMetrics globalMetrics;
  final List<FailureEvent> failures;
  final List<FailureEvent> visibleFailures; // Failures shown on components after persistence delay
  final int tickCount;
  final double simulationSpeed;
  final List<ChaosEvent> activeChaosEvents;
  final ChaosMultipliers chaosMultipliers;
  final Map<String, double> lastConnectionTraffic;

  const SimulationState({
    this.status = SimulationStatus.idle,
    this.globalMetrics = const GlobalMetrics(),
    this.failures = const [],
    this.visibleFailures = const [],
    this.tickCount = 0,
    this.simulationSpeed = 1.0,
    this.activeChaosEvents = const [],
    this.chaosMultipliers = ChaosMultipliers.normal,
    this.lastConnectionTraffic = const {},
  });

  SimulationState copyWith({
    SimulationStatus? status,
    GlobalMetrics? globalMetrics,
    List<FailureEvent>? failures,
    List<FailureEvent>? visibleFailures,
    int? tickCount,
    double? simulationSpeed,
    List<ChaosEvent>? activeChaosEvents,
    ChaosMultipliers? chaosMultipliers,
    Map<String, double>? lastConnectionTraffic,
  }) {
    return SimulationState(
      status: status ?? this.status,
      globalMetrics: globalMetrics ?? this.globalMetrics,
      failures: failures ?? this.failures,
      visibleFailures: visibleFailures ?? this.visibleFailures,
      tickCount: tickCount ?? this.tickCount,
      simulationSpeed: simulationSpeed ?? this.simulationSpeed,
      activeChaosEvents: activeChaosEvents ?? this.activeChaosEvents,
      chaosMultipliers: chaosMultipliers ?? this.chaosMultipliers,
      lastConnectionTraffic: lastConnectionTraffic ?? this.lastConnectionTraffic,
    );
  }

  bool get isRunning => status == SimulationStatus.running;
  bool get isPaused => status == SimulationStatus.paused;
  bool get isCompleted => status == SimulationStatus.completed;
  bool get isFailed => status == SimulationStatus.failed;
}

class SimulationNotifier extends StateNotifier<SimulationState> {
  SimulationNotifier() : super(const SimulationState());
  static const Duration _failureVisibleAfter = Duration(seconds: 5);
  final Map<String, DateTime> _failureFirstSeen = {};

  void start() {
    _failureFirstSeen.clear();
    state = state.copyWith(
      status: SimulationStatus.running,
      failures: [],
      visibleFailures: [],
      tickCount: 0,
      lastConnectionTraffic: {},
      globalMetrics: const GlobalMetrics(),
    );
  }

  void pause() {
    state = state.copyWith(status: SimulationStatus.paused);
  }

  void resume() {
    state = state.copyWith(status: SimulationStatus.running);
  }

  void stop() {
    state = state.copyWith(status: SimulationStatus.idle);
  }

  void complete() {
    state = state.copyWith(status: SimulationStatus.completed);
  }

  void tick() {
    if (state.status != SimulationStatus.running) return;
    state = state.copyWith(tickCount: state.tickCount + 1);
  }
  
  void updateConnectionTraffic(Map<String, double> traffic) {
    state = state.copyWith(lastConnectionTraffic: traffic);
  }

  void updateMetrics(GlobalMetrics metrics) {
    state = state.copyWith(globalMetrics: metrics);
  }



  void removeChaosEvent(String id) {
    state = state.copyWith(
      activeChaosEvents: state.activeChaosEvents.where((e) => e.id != id).toList(),
    );
  }

  void setFailures(List<FailureEvent> failures) {
    final now = DateTime.now();
    final currentKeys = <String>{};

    for (final failure in failures) {
      final key = '${failure.componentId}|${failure.type.name}';
      currentKeys.add(key);
      _failureFirstSeen.putIfAbsent(key, () => now);
    }

    _failureFirstSeen.removeWhere((key, _) => !currentKeys.contains(key));

    final visible = failures.where((failure) {
      final key = '${failure.componentId}|${failure.type.name}';
      final firstSeen = _failureFirstSeen[key] ?? now;
      return now.difference(firstSeen) >= _failureVisibleAfter;
    }).toList();

    state = state.copyWith(
      failures: failures,
      visibleFailures: visible,
    );
    // Note: We no longer stop the simulation on failure
  }

  /// Optimistically clear failures for a component (used when a fix is applied)
  void clearFailuresForComponent(String componentId) {
    _failureFirstSeen.removeWhere((key, _) => key.startsWith('$componentId|'));
    state = state.copyWith(
      failures: state.failures.where((f) => f.componentId != componentId).toList(),
      visibleFailures: state.visibleFailures.where((f) => f.componentId != componentId).toList(),
    );
  }

  void addFailure(FailureEvent failure) {
    // Check if we already have this failure to avoid duplicates
    final exists = state.failures.any((f) => 
      f.componentId == failure.componentId && f.type == failure.type
    );
    
    if (!exists) {
      state = state.copyWith(
        failures: [...state.failures, failure],
        // status: SimulationStatus.running, // Keep running!
      );
    }
  }

  void setSpeed(double speed) {
    state = state.copyWith(simulationSpeed: speed.clamp(0.0, 5.0));
  }

  void reset() {
    _failureFirstSeen.clear();
    state = const SimulationState();
  }

  /// Add a chaos event to the simulation
  void addChaosEvent(ChaosEvent event) {
    state = state.copyWith(
      activeChaosEvents: [...state.activeChaosEvents, event],
    );
    _updateChaosMultipliers();
  }

  /// Remove expired chaos events and update multipliers
  void updateChaosEvents() {
    final activeEvents = state.activeChaosEvents.where((e) => e.isActive).toList();
    if (activeEvents.length != state.activeChaosEvents.length) {
      state = state.copyWith(activeChaosEvents: activeEvents);
      _updateChaosMultipliers();
    }
  }

  /// Calculate and apply chaos multipliers based on active events
  void _updateChaosMultipliers() {
    var multipliers = ChaosMultipliers.normal;

    for (final event in state.activeChaosEvents.where((e) => e.isActive)) {
      switch (event.type) {
        case ChaosType.trafficSpike:
          final mult = event.parameters['multiplier'] as double? ?? 4.0;
          multipliers = multipliers.copyWith(
            trafficMultiplier: multipliers.trafficMultiplier * mult,
          );
          break;

        case ChaosType.networkLatency:
          final latency = event.parameters['latencyMs'] as int? ?? 300;
          multipliers = multipliers.copyWith(
            latencyMultiplier: multipliers.latencyMultiplier * (1 + latency / 100),
          );
          break;

        case ChaosType.networkPartition:
          // Would require component IDs - simplified for now
          break;

        case ChaosType.databaseSlowdown:
          final mult = event.parameters['multiplier'] as double? ?? 8.0;
          multipliers = multipliers.copyWith(
            databaseLatencyMultiplier: multipliers.databaseLatencyMultiplier * mult,
          );
          break;

        case ChaosType.cacheMissStorm:
          final drop = event.parameters['hitRateDrop'] as double? ?? 0.9;
          multipliers = multipliers.copyWith(
            cacheHitRate: multipliers.cacheHitRate * (1 - drop),
          );
          break;

        case ChaosType.componentCrash:
          multipliers = multipliers.copyWith(
            failureRateMultiplier: multipliers.failureRateMultiplier * 10,
          );
          break;
      }
    }
// Provider for real-time simulation metrics (decoupled from structure for performance)
    state = state.copyWith(chaosMultipliers: multipliers);
  }
}

// Provider for real-time simulation metrics (decoupled from structure for performance)
final simulationMetricsProvider = StateProvider<Map<String, ComponentMetrics>>((ref) => {});

final simulationProvider =
    StateNotifierProvider<SimulationNotifier, SimulationState>((ref) {
  return SimulationNotifier();
});

/// Current score
final scoreProvider = StateProvider<Score?>((ref) => null);

/// Validation provider (Asynchronous and Debounced)
final validationProvider = FutureProvider<ValidationResult>((ref) async {
  final components = ref.watch(canvasProvider.select((s) => s.components));
  final connections = ref.watch(canvasProvider.select((s) => s.connections));
  final problem = ref.watch(currentProblemProvider);

  // Debounce to avoid excessive isolate spawning during drags
  await Future.delayed(const Duration(milliseconds: 300));

  return compute(_validateDesignIsolate, _ValidationData(
    components: components,
    connections: connections,
    problem: problem,
  ));
});

/// Internal helper for isolate-based validation
class _ValidationData {
  final List<SystemComponent> components;
  final List<Connection> connections;
  final Problem problem;

  _ValidationData({
    required this.components,
    required this.connections,
    required this.problem,
  });
}

ValidationResult _validateDesignIsolate(_ValidationData data) {
  return DesignValidator.validate(
    components: data.components,
    connections: data.connections,
    problem: data.problem,
  );
}

/// Level completion results
final levelResultsProvider = StateProvider<Map<String, LevelResult>>((ref) => {});

/// Toolbox visibility
final toolboxVisibleProvider = StateProvider<bool>((ref) => true);

/// Selected component category in toolbox
final selectedCategoryProvider = StateProvider<ComponentCategory?>((ref) => null);

/// Trigger to add a component (from toolbox click)
final addComponentTriggerProvider = StateProvider<ComponentType?>((ref) => null);

/// Canvas Drawing Tools
enum CanvasTool {
  select,
  hand,
  rectangle,
  circle,
  diamond,
  arrow,
  line,
  pen,
  text,
  eraser,
}

final canvasToolProvider = StateProvider<CanvasTool>((ref) => CanvasTool.select);
