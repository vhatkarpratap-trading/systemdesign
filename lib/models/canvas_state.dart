
import 'package:flutter/material.dart';
import 'component.dart';
import 'connection.dart';

/// State of the system canvas (components and connections)
class CanvasState {
  final List<SystemComponent> components;
  final List<Connection> connections;
  final String? selectedComponentId;
  final String? connectingFromId;
  final Offset panOffset;
  final double scale;
  final String? activeProblemId;
  final bool isCyberpunkMode;
  final double trafficLevel; // 0.0 to 1.0 (representing 0% to 100% traffic)
  final bool showErrors; // Toggle to show/hide error indicators

  const CanvasState({
    this.components = const [],
    this.connections = const [],
    this.selectedComponentId,
    this.connectingFromId,
    this.panOffset = Offset.zero,
    this.scale = 1.0,
    this.activeProblemId,
    this.isCyberpunkMode = false,
    this.trafficLevel = 1.0, // Default 100% traffic
    this.showErrors = true, // Default: show errors
  });

  CanvasState copyWith({
    List<SystemComponent>? components,
    List<Connection>? connections,
    String? selectedComponentId,
    String? connectingFromId,
    Offset? panOffset,
    double? scale,
    String? activeProblemId,
    bool clearSelection = false,
    bool clearConnecting = false,
    bool? isCyberpunkMode,
    double? trafficLevel,
    bool? showErrors,
  }) {
    return CanvasState(
      components: components ?? this.components,
      connections: connections ?? this.connections,
      selectedComponentId:
          clearSelection ? null : (selectedComponentId ?? this.selectedComponentId),
      connectingFromId:
          clearConnecting ? null : (connectingFromId ?? this.connectingFromId),
      panOffset: panOffset ?? this.panOffset,
      scale: scale ?? this.scale,
      activeProblemId: activeProblemId ?? this.activeProblemId,
      isCyberpunkMode: isCyberpunkMode ?? this.isCyberpunkMode,
      trafficLevel: trafficLevel ?? this.trafficLevel,
      showErrors: showErrors ?? this.showErrors,
    );
  }

  /// Get component by ID
  SystemComponent? getComponent(String id) {
    try {
      return components.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
  
  // Computed property for Bill Shock
  double get totalCostPerHour {
    return components.fold(0.0, (sum, c) => sum + (c.config.costPerHour * c.config.instances));
  }

  /// Get connections for a component
  List<Connection> getConnectionsFor(String componentId) {
    return connections
        .where((c) => c.sourceId == componentId || c.targetId == componentId)
        .toList();
  }

  /// Check if two components are connected
  bool areConnected(String id1, String id2) {
    return connections.any((c) =>
        (c.sourceId == id1 && c.targetId == id2) ||
        (c.sourceId == id2 && c.targetId == id1));
  }

  Map<String, dynamic> toJson() => {
    'components': components.map((c) => c.toJson()).toList(),
    'connections': connections.map((c) => c.toJson()).toList(),
    'panOffset': {'dx': panOffset.dx, 'dy': panOffset.dy},
    'scale': scale,
    'activeProblemId': activeProblemId,
    'isCyberpunkMode': isCyberpunkMode,
    'trafficLevel': trafficLevel,
        'showErrors': showErrors,
  };

  factory CanvasState.fromJson(Map<String, dynamic> json) {
    final panOffsetJson = json['panOffset'] as Map<String, dynamic>?;
    return CanvasState(
      components: (json['components'] as List<dynamic>?)
          ?.map((e) => SystemComponent.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      connections: (json['connections'] as List<dynamic>?)
          ?.map((e) => Connection.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      panOffset: panOffsetJson != null
          ? Offset(
              (panOffsetJson['dx'] as num?)?.toDouble() ?? 0.0,
              (panOffsetJson['dy'] as num?)?.toDouble() ?? 0.0,
            )
          : Offset.zero,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      activeProblemId: json['activeProblemId'] as String?,
      isCyberpunkMode: json['isCyberpunkMode'] as bool? ?? false,
      trafficLevel: (json['trafficLevel'] as num?)?.toDouble() ?? 1.0,
      showErrors: json['showErrors'] as bool? ?? true,
    );
  }
}
