import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/canvas_state.dart';
import '../models/component.dart';
import '../models/connection.dart';
import '../models/problem.dart';

/// Utility to export system designs to a standardized JSON blueprint format
class BlueprintExporter {
  static String exportToJson(CanvasState canvasState, Problem problem) {
    return _exportLogic(_ExportData(canvasState, problem));
  }

  static Future<String> exportToJsonAsync(CanvasState canvasState, Problem problem) async {
    return compute(_exportLogic, _ExportData(canvasState, problem));
  }

  static String _exportLogic(_ExportData data) {
    final canvasState = data.canvasState;
    final problem = data.problem;
    final Map<String, dynamic> blueprint = {
      "metadata": {
        "systemName": problem.title,
        "domain": "distributed-systems",
        "version": "1.0.0",
        "author": "Antigravity Designer",
        "description": problem.description,
      },
      "globals": {
        "region": "ap-south-1",
        "environment": "production",
        "defaultProtocol": "HTTPS",
        "timeUnit": "ms"
      },
      "components": _mapComponents(canvasState.components),
      "connections": _mapConnections(canvasState.components, canvasState.connections),
      "dataFlows": _generateDefaultFlows(canvasState),
      "constraints": {
        "latency": {
          "p95Ms": problem.constraints.latencySlaMsP95,
          "p99Ms": (problem.constraints.latencySlaMsP95 * 1.5).toInt()
        },
        "availability": {
          "target": problem.constraints.availabilityString
        },
        "cost": {
          "monthlyUSD": problem.constraints.budgetPerMonth
        }
      },
      "scalingRules": _generateScalingRules(canvasState.components),
      "failureModes": _generateFailureModes(canvasState.components),
      "viewState": {
        "panOffset": {"x": canvasState.panOffset.dx, "y": canvasState.panOffset.dy},
        "scale": canvasState.scale
      },
      "security": {
        "authentication": "JWT",
        "authorization": "RBAC",
        "encryption": {
          "inTransit": true,
          "atRest": true
        },
        "rateLimiting": {
          "enabled": true,
          "requestsPerMinute": problem.constraints.effectiveQps * 60
        }
      },
      "observability": {
        "logging": {
          "level": "INFO",
          "centralized": true
        },
        "metrics": ["latency", "error_rate", "throughput"],
        "tracing": {
          "enabled": true,
          "samplingRate": 0.1
        }
      }
    };

    return const JsonEncoder.withIndent('  ').convert(blueprint);
  }

  static Map<String, dynamic> _mapComponents(List<SystemComponent> components) {
    final Map<String, dynamic> result = {};
    for (final comp in components) {
      final String id = _getSanitizedId(comp);
      result[id] = {
        "id": id,
        "name": comp.customName ?? comp.type.displayName,
        "type": comp.type.name,
        "category": comp.type.category.name,
        "properties": _getComponentProperties(comp),
        "capacity": {
          "instances": comp.config.instances,
          "maxRPSPerInstance": comp.config.capacity,
        },
        "scaling": {
          "autoScale": comp.config.autoScale,
          "minInstances": comp.config.minInstances,
          "maxInstances": comp.config.maxInstances
        },
        "position": {"x": comp.position.dx, "y": comp.position.dy}
      };
      
      if (comp.type == ComponentType.database) {
        result[id]["properties"]["replication"] = comp.config.replication ? "primary-replica" : "single-node";
      }
      
      if (comp.type == ComponentType.cache) {
        result[id]["properties"]["ttlSeconds"] = comp.config.cacheTtlSeconds;
      }
    }
    return result;
  }

  static String _getSanitizedId(SystemComponent comp) {
    if (comp.customName != null && comp.customName!.isNotEmpty) {
      return comp.customName!.toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    }
    return comp.id.substring(0, 8); // Use first 8 chars of UUID if no name
  }

  static Map<String, dynamic> _getComponentProperties(SystemComponent comp) {
    // Return typical industry defaults based on component type
    return switch (comp.type) {
      ComponentType.loadBalancer => {
          "algorithm": comp.config.algorithm ?? "round_robin",
          "layer": "L7",
          "protocols": ["HTTP", "HTTPS"]
        },
      ComponentType.database => {
          "engine": _guessEngine(comp),
          "consistency": "strong",
        },
      ComponentType.cache => {
          "engine": "Redis",
          "evictionPolicy": "LRU",
        },
      ComponentType.appServer => {
          "language": "Go",
          "framework": "Gin",
          "stateless": true
        },
      _ => {
          "provider": "CloudProvider",
        }
    };
  }

  static String _guessEngine(SystemComponent comp) {
    final name = comp.customName?.toLowerCase() ?? "";
    if (name.contains('postgre')) return 'PostgreSQL';
    if (name.contains('mongo')) return 'MongoDB';
    if (name.contains('redis')) return 'Redis';
    return 'StandardDB';
  }

  static List<Map<String, dynamic>> _mapConnections(List<SystemComponent> components, List<Connection> connections) {
    // Generate the same sanitized IDs used in _mapComponents
    final Map<String, String> idLookup = {
      for (final c in components) c.id: _getSanitizedId(c)
    };

    return connections.map((conn) => {
      "id": conn.id.substring(0, 8),
      "from": idLookup[conn.sourceId] ?? conn.sourceId.substring(0, 8),
      "to": idLookup[conn.targetId] ?? conn.targetId.substring(0, 8),
      "protocol": conn.type == ConnectionType.replication ? "TCP" : "HTTPS",
      "sync": conn.type != ConnectionType.async
    }).toList();
  }

  static List<Map<String, dynamic>> _generateDefaultFlows(CanvasState state) {
    // Generate a simple read flow if we have servers and databases
    final hasApp = state.components.any((c) => c.type == ComponentType.appServer);
    final hasDb = state.components.any((c) => c.type == ComponentType.database);
    
    if (hasApp && hasDb) {
      return [
        {
          "id": "flow-1",
          "name": "Standard Request Flow",
          "trigger": "HTTP_GET",
          "steps": [
            {"component": "load_balancer", "action": "route"},
            {"component": "app_server", "action": "process"},
            {"component": "database", "action": "query"}
          ]
        }
      ];
    }
    return [];
  }

  static Map<String, dynamic> _generateScalingRules(List<SystemComponent> components) {
    final Map<String, dynamic> rules = {};
    for (final comp in components) {
      if (comp.config.autoScale) {
        final id = comp.customName?.toLowerCase().replaceAll(' ', '_') ?? comp.id;
        rules[id] = {
           "scaleOn": "cpu_utilization",
           "scaleOutThreshold": 70,
           "scaleInThreshold": 30,
           "coolDownSeconds": 120
        };
      }
    }
    return rules;
  }

  static Map<String, dynamic> _generateFailureModes(List<SystemComponent> components) {
    final Map<String, dynamic> modes = {};
    for (final comp in components) {
      if (comp.type == ComponentType.database || comp.type == ComponentType.cache) {
        final id = comp.customName?.toLowerCase().replaceAll(' ', '_') ?? comp.id;
        modes["${id}_failure"] = {
          "affectedComponents": [id],
          "impact": "service_degradation",
          "fallback": "circuit_breaker_open"
        };
      }
    }
    return modes;
  }
}

class _ExportData {
  final CanvasState canvasState;
  final Problem problem;

  _ExportData(this.canvasState, this.problem);
}
