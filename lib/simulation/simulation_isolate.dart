import 'dart:math';
import '../models/component.dart';
import '../models/connection.dart';
import '../models/metrics.dart';
import '../models/problem.dart';

/// Data required to run a simulation tick
class SimulationData {
  final List<SystemComponent> components;
  final List<Connection> connections;
  final Problem problem;
  final GlobalMetrics currentGlobalMetrics;
  final int tickCount;

  SimulationData({
    required this.components,
    required this.connections,
    required this.problem,
    required this.currentGlobalMetrics,
    required this.tickCount,
  });
}

/// Result of a simulation tick
class SimulationResult {
  final Map<String, ComponentMetrics> componentMetrics;
  final Map<String, double> connectionTraffic;
  final List<FailureEvent> failures;
  final GlobalMetrics globalMetrics;
  final bool isCompleted;

  SimulationResult({
    required this.componentMetrics,
    required this.connectionTraffic,
    required this.failures,
    required this.globalMetrics,
    required this.isCompleted,
  });
}

/// Run a single simulation tick in an isolate
SimulationResult runSimulationTick(SimulationData data) {
  final random = Random();
  final components = data.components;
  final connections = data.connections;
  final problem = data.problem;

  // Calculate incoming traffic based on problem constraints
  final targetRps = problem.constraints.effectiveQps;
  // Add some variation to simulate real traffic
  final currentRps = (targetRps * (0.8 + random.nextDouble() * 0.4)).toInt();

  // Process traffic
  final (componentMetrics, connectionTraffic, failures) =
      _processTraffic(components, connections, currentRps, problem, random);

  // Calculate global metrics
  final globalMetrics = _calculateGlobalMetrics(
    components,
    componentMetrics,
    currentRps,
    problem,
  );

  return SimulationResult(
    componentMetrics: componentMetrics,
    connectionTraffic: connectionTraffic,
    failures: failures,
    globalMetrics: globalMetrics,
    isCompleted: data.tickCount >= 100,
  );
}

/// Process traffic through the system
(Map<String, ComponentMetrics>, Map<String, double>, List<FailureEvent>)
    _processTraffic(
  List<SystemComponent> components,
  List<Connection> connections,
  int incomingRps,
  Problem problem,
  Random random,
) {
  final componentMetrics = <String, ComponentMetrics>{};
  final connectionTraffic = <String, double>{};
  final failures = <FailureEvent>[];

  if (components.isEmpty) {
    return (componentMetrics, connectionTraffic, failures);
  }

  // Find entry points
  final hasIncoming = connections.map((c) => c.targetId).toSet();
  final entryPoints = components
      .where((c) => !hasIncoming.contains(c.id))
      .map((c) => c.id)
      .toList();

  // Distribute traffic
  final rpsPerEntry = entryPoints.isEmpty ? 0 : incomingRps ~/ entryPoints.length;

  // Process each component
  for (final component in components) {
    int componentRps;
    if (entryPoints.contains(component.id)) {
      componentRps = rpsPerEntry;
    } else {
      componentRps = connections
          .where((c) => c.targetId == component.id)
          .fold(0, (sum, c) {
        final sourceMetrics = componentMetrics[c.sourceId];
        if (sourceMetrics != null) {
          return sum + (sourceMetrics.currentRps * 0.9).toInt();
        }
        return sum;
      });
    }

    final metrics = _calculateComponentMetrics(component, componentRps, problem, random);
    componentMetrics[component.id] = metrics;

    final componentFailures = _checkFailures(component, metrics, problem);
    failures.addAll(componentFailures);
  }

  // Calculate connection traffic
  for (final connection in connections) {
    final sourceMetrics = componentMetrics[connection.sourceId];
    if (sourceMetrics != null) {
      final sourceComponent = components.firstWhere((c) => c.id == connection.sourceId);
      final flow = sourceMetrics.currentRps / (sourceComponent.totalCapacity + 1);
      connectionTraffic[connection.id] = flow.clamp(0.0, 1.0);
    }
  }

  return (componentMetrics, connectionTraffic, failures);
}

ComponentMetrics _calculateComponentMetrics(
  SystemComponent component,
  int incomingRps,
  Problem problem,
  Random random,
) {
  final capacity = component.totalCapacity;
  final load = capacity > 0 ? incomingRps / capacity : 1.0;

  final cpuUsage = (load * 0.8 + random.nextDouble() * 0.1).clamp(0.0, 1.0);
  final memoryUsage = (0.3 + load * 0.4 + random.nextDouble() * 0.1).clamp(0.0, 1.0);

  double baseLatency = _getBaseLatency(component.type);
  double latencyMultiplier = 1.0;
  if (load > 0.7) {
    latencyMultiplier = 1 + pow(load - 0.7, 2) * 10;
  }
  if (load > 1.0) {
    latencyMultiplier = 5 + pow(load - 1.0, 2) * 20;
  }
  final avgLatency = baseLatency * latencyMultiplier;
  final p95Latency = avgLatency * 2.5;

  double errorRate = 0.001;
  if (load > 0.9) {
    errorRate = 0.01 + (load - 0.9) * 0.5;
  }
  if (load > 1.0) {
    errorRate = 0.1 + (load - 1.0) * 0.3;
  }
  errorRate = errorRate.clamp(0.0, 0.5);

  double cacheHitRate = 0.0;
  if (component.type == ComponentType.cache) {
    cacheHitRate = 0.85 + random.nextDouble() * 0.1;
    if (load > 0.9) {
      cacheHitRate -= (load - 0.9) * 0.3;
    }
    cacheHitRate = cacheHitRate.clamp(0.0, 1.0);
  }

  return ComponentMetrics(
    cpuUsage: cpuUsage,
    memoryUsage: memoryUsage,
    currentRps: incomingRps,
    avgLatencyMs: avgLatency,
    p95LatencyMs: p95Latency,
    errorRate: errorRate,
    cacheHitRate: cacheHitRate,
  );
}

double _getBaseLatency(ComponentType type) {
  return switch (type) {
    ComponentType.dns => 1.0,
    ComponentType.cdn => 5.0,
    ComponentType.loadBalancer => 1.0,
    ComponentType.apiGateway => 5.0,
    ComponentType.appServer => 20.0,
    ComponentType.worker => 100.0,
    ComponentType.serverless => 50.0,
    ComponentType.cache => 2.0,
    ComponentType.database => 10.0,
    ComponentType.objectStore => 50.0,
    ComponentType.queue => 5.0,
    ComponentType.pubsub => 5.0,
    ComponentType.stream => 10.0,
    ComponentType.customService => 20.0,
    ComponentType.sketchyService => 20.0,
    ComponentType.sketchyDatabase => 10.0,
    ComponentType.sketchyLogic => 20.0,
    ComponentType.sketchyQueue => 5.0,
    ComponentType.sketchyClient => 1.0,  
    ComponentType.client => 1.0,
    ComponentType.text || 
    ComponentType.sharding ||
    ComponentType.hashing ||
    ComponentType.rectangle || 
    ComponentType.circle || 
    ComponentType.diamond ||
    ComponentType.arrow || 
    ComponentType.line => 0.0,
  };
}

List<FailureEvent> _checkFailures(
  SystemComponent component,
  ComponentMetrics metrics,
  Problem problem,
) {
  final failures = <FailureEvent>[];
  final now = DateTime.now();

  if (metrics.cpuUsage > 0.95) {
    failures.add(FailureEvent(
      timestamp: now,
      componentId: component.id,
      type: FailureType.overload,
      message: '${component.type.displayName} is overloaded (${(metrics.cpuUsage * 100).toInt()}% CPU)',
      recommendation: 'Add more instances or increase capacity',
    ));
  }

  if (component.config.instances == 1 && !component.config.autoScale) {
    if (component.type != ComponentType.dns && component.type != ComponentType.cdn) {
      failures.add(FailureEvent(
        timestamp: now,
        componentId: component.id,
        type: FailureType.spof,
        message: '${component.type.displayName} is a single point of failure',
        recommendation: 'Add redundancy with multiple instances',
      ));
    }
  }

  if (metrics.p95LatencyMs > problem.constraints.latencySlaMsP95) {
    failures.add(FailureEvent(
      timestamp: now,
      componentId: component.id,
      type: FailureType.latencyBreach,
      message: 'P95 latency ${metrics.p95LatencyMs.toInt()}ms exceeds SLA of ${problem.constraints.latencySlaMsP95}ms',
      recommendation: 'Optimize performance or add caching',
    ));
  }

  if (component.type == ComponentType.database && !component.config.replication) {
    failures.add(FailureEvent(
      timestamp: now,
      componentId: component.id,
      type: FailureType.dataLoss,
      message: 'Database has no replication configured',
      recommendation: 'Enable replication for data durability',
    ));
  }

  return failures;
}

GlobalMetrics _calculateGlobalMetrics(
  List<SystemComponent> components,
  Map<String, ComponentMetrics> componentMetrics,
  int totalRps,
  Problem problem,
) {
  if (components.isEmpty || componentMetrics.isEmpty) {
    return const GlobalMetrics();
  }

  double totalLatency = 0;
  double maxLatency = 0;
  double totalErrorRate = 0;
  double totalCost = 0;

  for (final component in components) {
    final metrics = componentMetrics[component.id];
    if (metrics != null) {
      totalLatency += metrics.avgLatencyMs;
      if (metrics.p95LatencyMs > maxLatency) {
        maxLatency = metrics.p95LatencyMs;
      }
      totalErrorRate = totalErrorRate + metrics.errorRate - (totalErrorRate * metrics.errorRate);
    }
    totalCost += component.hourlyCost;
  }

  final availability = (1 - totalErrorRate).clamp(0.0, 1.0);

  return GlobalMetrics(
    totalRps: totalRps,
    avgLatencyMs: totalLatency,
    p50LatencyMs: totalLatency * 0.8,
    p95LatencyMs: maxLatency,
    p99LatencyMs: maxLatency * 1.5,
    errorRate: totalErrorRate,
    availability: availability,
    totalCostPerHour: totalCost,
    totalRequests: totalRps,
    successfulRequests: ((1 - totalErrorRate) * totalRps).toInt(),
    failedRequests: (totalErrorRate * totalRps).toInt(),
  );
}
