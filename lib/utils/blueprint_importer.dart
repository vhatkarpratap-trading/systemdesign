import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../models/canvas_state.dart';
import '../models/component.dart';
import '../models/connection.dart';

/// Utility to import system designs from the standardized JSON blueprint format
class BlueprintImporter {
  static CanvasState importFromJson(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);
    return _importLogic(data);
  }

  static Future<CanvasState> importFromJsonAsync(String jsonString) async {
    return compute((String json) {
      final Map<String, dynamic> data = jsonDecode(json);
      return _importLogic(data);
    }, jsonString);
  }

  static CanvasState importFromMap(Map<String, dynamic> data) {
    return _importLogic(data);
  }

  static CanvasState _importLogic(Map<String, dynamic> data) {
    // data is already a Map here
    
    final Map<String, dynamic> componentsJson = data['components'] ?? {};
    final List<dynamic> connectionsJson = data['connections'] ?? [];
    
    final List<SystemComponent> components = [];
    final Map<String, String> idMapping = {}; // Old ID -> New UUID
    
    // 1. Process Components
    componentsJson.forEach((key, value) {
      final String oldId = value['id'] ?? key;
      final String newId = oldId; // We can reuse the ID if it's unique, or generate UUID
      
      final type = _mapType(value['type']);
      final config = _mapConfig(value, type);
      
      final component = SystemComponent(
        id: newId,
        type: type,
        // Spread components out if no position (manual import usually doesn't have pos)
        position: _getPosition(value, components.length),
        config: config,
        customName: value['name'] ?? key,
      );
      
      components.add(component);
      idMapping[oldId] = newId;
    });
    
    // 2. Process Connections
    final List<Connection> connections = [];
    for (final connJson in connectionsJson) {
      final String? from = connJson['from'];
      final String? to = connJson['to'];
      
      if (from != null && to != null) {
        connections.add(Connection(
          id: connJson['id']?.toString() ?? 'conn_${connections.length}',
          sourceId: idMapping[from] ?? from,
          targetId: idMapping[to] ?? to,
          direction: ConnectionDirection.unidirectional,
          type: _mapConnectionType(connJson['protocol']),
        ));
      }
    }
    
    // 3. Process View State (Pan & Scale)
    final Map<String, dynamic>? viewState = data['viewState'];
    Offset panOffset = Offset.zero;
    double scale = 1.0;
    
    if (viewState != null) {
      final panJson = viewState['panOffset'];
      if (panJson != null) {
        panOffset = Offset(
          (panJson['x'] as num).toDouble(),
          (panJson['y'] as num).toDouble(),
        );
      }
      scale = (viewState['scale'] as num?)?.toDouble() ?? 1.0;
    } else {
      // Default: Center in a way that (5000, 5000) is roughly visible
      // viewport is usually ~800-1200 wide. 
      // viewportX = panOffset.dx + pos.x * scale
      // To center 5000 at 500 (mid of 1000): 500 = panX + 5000*1 -> panX = -4500
       panOffset = const Offset(-4500, -4700);
    }
    
    return CanvasState(
      components: components,
      connections: connections,
      panOffset: panOffset,
      scale: scale,
    );
  }

  static ComponentType _mapType(String? typeStr) {
    if (typeStr == null) return ComponentType.appServer;
    
    // Handle specific mappings from the requested schema
    final normalized = typeStr.toLowerCase();
    
    if (normalized == 'application_server') return ComponentType.appServer;
    if (normalized == 'load_balancer') return ComponentType.loadBalancer;
    if (normalized == 'client' || normalized == 'users') return ComponentType.client;
    if (normalized == 'cache') return ComponentType.cache;
    if (normalized == 'database') return ComponentType.database;
    if (normalized == 'api_gateway') return ComponentType.apiGateway;
    if (normalized == 'cdn') return ComponentType.cdn;
    if (normalized == 'dns') return ComponentType.dns;
    if (normalized == 'worker') return ComponentType.worker;
    if (normalized == 'serverless') return ComponentType.serverless;
    if (normalized == 'message_queue' || normalized == 'queue') return ComponentType.queue;
    if (normalized == 'pub_sub' || normalized == 'pubsub') return ComponentType.pubsub;
    if (normalized == 'stream') return ComponentType.stream;
    if (normalized == 'object_store') return ComponentType.objectStore;
    
    // Fallback to closest match in enum
    return ComponentType.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => ComponentType.appServer,
    );
  }

  static ComponentConfig _mapConfig(Map<String, dynamic> json, ComponentType type) {
    final capacity = json['capacity'] ?? {};
    final scaling = json['scaling'] ?? {};
    final properties = json['properties'] ?? {};
    
    return ComponentConfig(
      capacity: capacity['maxRPSPerInstance'] ?? 1000,
      instances: capacity['instances'] ?? 1,
      autoScale: scaling['autoScale'] ?? false,
      minInstances: scaling['minInstances'] ?? 1,
      maxInstances: scaling['maxInstances'] ?? 10,
      algorithm: properties['algorithm'],
      cacheTtlSeconds: properties['ttlSeconds'] ?? 300,
      replication: properties['replication'] != null && properties['replication'] != 'single-node',
      // We'd add more mapping as needed
    );
  }

  static Offset _getPosition(Map<String, dynamic> json, int index) {
    // If original pos exists, use it
    if (json['position'] != null) {
      return Offset(
        (json['position']['x'] as num).toDouble(),
        (json['position']['y'] as num).toDouble(),
      );
    }
    
    // Otherwise, place in a rough grid
    const startX = 5000.0;
    const startY = 4800.0;
    const nodesPerRow = 3;
    
    return Offset(
      startX + (index % nodesPerRow) * 250,
      startY + (index ~/ nodesPerRow) * 250,
    );
  }

  static ConnectionType _mapConnectionType(String? protocol) {
    if (protocol == null) return ConnectionType.request;
    final p = protocol.toUpperCase();
    if (p == 'TCP' || p == 'UDP') return ConnectionType.request; // Basic request
    if (p == 'ASYNC') return ConnectionType.async;
    return ConnectionType.request;
  }
}
