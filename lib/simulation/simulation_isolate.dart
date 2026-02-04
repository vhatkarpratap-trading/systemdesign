import 'dart:math';
import 'dart:ui'; // Needed for Offset
import '../models/component.dart';
import '../models/connection.dart';
import '../models/metrics.dart';
import '../models/problem.dart';

import '../models/chaos_event.dart';

/// Data required to run a simulation tick
class SimulationData {
  final List<SystemComponent> components;
  final List<Connection> connections;
  final Problem problem;
  final GlobalMetrics currentGlobalMetrics;
  final int tickCount;
  final List<ChaosEvent> activeChaosEvents;
  final Map<String, ComponentMetrics> previousMetrics;
  final double trafficLevel; // User-controlled 0.0-1.0 (0-100%)
  final double tickDurationSeconds; // Simulated time per tick

  SimulationData({
    required this.components,
    required this.connections,
    required this.problem,
    required this.currentGlobalMetrics,
    required this.tickCount,
    this.activeChaosEvents = const [],
    this.previousMetrics = const {},
    this.trafficLevel = 1.0, // Default 100% traffic
    this.tickDurationSeconds = _defaultSimWindowSeconds,
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

// --- Event-driven simulation helpers ---
const double _defaultSimWindowSeconds = 1.0;
const int _minSampleEvents = 120;
const int _maxSampleEvents = 2000;

enum _EventType { arrival, completion }

class _Token {
  final double weight; // How many real requests this token represents
  final double arrivedAt; // Arrival time at current component (seconds)
  final String? callerId; // Upstream component that sent this token
  final int retryCount;

  const _Token({
    required this.weight,
    required this.arrivedAt,
    this.callerId,
    this.retryCount = 0,
  });

  _Token copyWith({
    double? arrivedAt,
    String? callerId,
    int? retryCount,
  }) {
    return _Token(
      weight: weight,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      callerId: callerId ?? this.callerId,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

class _Event {
  final double time; // seconds
  final _EventType type;
  final String componentId;
  final _Token token;
  final String? connectionId;

  const _Event({
    required this.time,
    required this.type,
    required this.componentId,
    required this.token,
    this.connectionId,
  });
}

class _AutoscaleState {
  final int effectiveInstances;
  final bool isScaling;
  final int targetInstances;
  final int readyInstances;
  final int coldStartingInstances;

  const _AutoscaleState({
    required this.effectiveInstances,
    required this.isScaling,
    required this.targetInstances,
    required this.readyInstances,
    required this.coldStartingInstances,
  });
}

class _SimComponentState {
  final SystemComponent component;
  final ComponentMetrics? prevMetrics;
  final int servers;
  final int capacityPerInstance;
  final double baseLatencyMs;
  final bool isCrashed;
  final bool isSlow;
  final double slownessFactor;
  final bool circuitOpen;
  final int? rateLimitTokens;
  final int maxQueueTokens;
  final _AutoscaleState autoscale;

  int arrivals = 0;
  int processed = 0;
  int errors = 0;
  int inService = 0;
  bool isThrottled = false;

  double totalLatencyMs = 0.0;
  final List<double> latencySamples = [];
  final List<_Token> queue = [];

  _SimComponentState({
    required this.component,
    required this.prevMetrics,
    required this.servers,
    required this.capacityPerInstance,
    required this.baseLatencyMs,
    required this.isCrashed,
    required this.isSlow,
    required this.slownessFactor,
    required this.circuitOpen,
    required this.rateLimitTokens,
    required this.maxQueueTokens,
    required this.autoscale,
  });

  double get utilization {
    if (servers <= 0) return 1.0;
    final inFlight = queue.length + inService;
    return inFlight / servers;
  }
}

class _MinHeap {
  final List<_Event> _items = [];

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  void add(_Event value) {
    _items.add(value);
    _bubbleUp(_items.length - 1);
  }

  _Event pop() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      _bubbleDown(0);
    }
    return first;
  }

  void _bubbleUp(int index) {
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_items[index].time >= _items[parent].time) break;
      final tmp = _items[parent];
      _items[parent] = _items[index];
      _items[index] = tmp;
      index = parent;
    }
  }

  void _bubbleDown(int index) {
    final length = _items.length;
    while (true) {
      final left = (index << 1) + 1;
      final right = left + 1;
      int smallest = index;

      if (left < length && _items[left].time < _items[smallest].time) {
        smallest = left;
      }
      if (right < length && _items[right].time < _items[smallest].time) {
        smallest = right;
      }
      if (smallest == index) break;
      final tmp = _items[index];
      _items[index] = _items[smallest];
      _items[smallest] = tmp;
      index = smallest;
    }
  }
}

/// Run a single simulation tick in an isolate
SimulationResult runSimulationTick(SimulationData data) {
  final random = Random();
  final components = data.components;
  final connections = data.connections;
  final problem = data.problem;

  // Calculate incoming traffic based on problem constraints with dynamic multiplier
  final targetRps = problem.constraints.effectiveQps;
  final multiplier = _getTrafficMultiplier(data.tickCount);
  
  // Apply Chaos Traffic Spikes
  double chaosMultiplier = 1.0;
  for (final event in data.activeChaosEvents) {
    if (event.type == ChaosType.trafficSpike) {
      chaosMultiplier *= (event.parameters['multiplier'] ?? 4.0);
    }
  }

  // CRITICAL: Apply user's traffic level control (0-100% slider)
  final currentRps = (targetRps * multiplier * chaosMultiplier * data.trafficLevel * (0.95 + random.nextDouble() * 0.1)).toInt();

  final simWindowSeconds = data.tickDurationSeconds > 0
      ? data.tickDurationSeconds
      : _defaultSimWindowSeconds;

  // Process traffic
  final (componentMetrics, connectionTraffic, failures) =
      _processTraffic(
        components,
        connections,
        currentRps,
        problem,
        random,
        data.activeChaosEvents,
        data.previousMetrics,
        simWindowSeconds,
      );

  // Check for consistency issues (replication lag, stale reads, etc.)
  final consistencyIssues = _checkConsistencyIssues(
    components,
    connections,
    componentMetrics,
    data.tickCount,
  );
  
  // Check for cascading failures
  final cascadingFailures = _checkCascadingFailures(
    components,
    connections,
    componentMetrics,
    [...failures, ...consistencyIssues],
  );
  
  // Check for retry storms
  final retryStorms = _detectRetryStorms(
    components,
    componentMetrics,
    connections,
  );
  
  // Check for network partitions (rare but impactful)
  final networkFailure = _simulateNetworkPartition(components, data.tickCount, random);

  // Combine all failures
  final allFailures = [
    ...failures,
    ...consistencyIssues,
    ...cascadingFailures,
    ...retryStorms,
    if (networkFailure != null) networkFailure,
  ];

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
    failures: allFailures,
    globalMetrics: globalMetrics,
    isCompleted: false, // Run indefinitely - user controls when to stop
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
  List<ChaosEvent> activeChaosEvents,
  Map<String, ComponentMetrics> previousMetrics,
  double simWindowSeconds,
) {
  int chooseSampleCount(double totalRequests) {
    if (totalRequests <= 0) return 0;
    if (totalRequests < 40) return totalRequests.round().clamp(5, 40);
    final desired = (totalRequests * 0.002).round(); // ~0.2% sampling
    return desired.clamp(_minSampleEvents, _maxSampleEvents);
  }

  double randomNormal() {
    // Box-Muller transform
    final u1 = random.nextDouble().clamp(1e-8, 1.0);
    final u2 = random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
  }

  double sampleLogNormal(double mean, double sigma) {
    if (mean <= 0) return 0.0;
    final variance = sigma * sigma;
    final mu = log(mean) - 0.5 * variance;
    final z = randomNormal();
    return exp(mu + sigma * z);
  }

  double percentile(List<double> values, double p) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final index = (sorted.length * p).clamp(0.0, (sorted.length - 1).toDouble());
    return sorted[index.floor()];
  }

  double smooth(double next, double prev, double alpha) {
    return (next * alpha) + (prev * (1 - alpha));
  }

  _AutoscaleState computeAutoscaleState(SystemComponent component, double estimatedRps) {
    var effectiveInstances = component.config.instances;
    var targetInstances = effectiveInstances;
    var readyInstances = effectiveInstances;
    var coldStartingInstances = 0;
    var isScaling = false;

    final baseCapacity = component.config.capacity * component.config.instances;
    final load = baseCapacity > 0 ? (estimatedRps / baseCapacity) : 1.0;

    if (component.config.autoScale && load > 0.7) {
      targetInstances = (effectiveInstances * 1.5).ceil().clamp(
        component.config.minInstances,
        component.config.maxInstances,
      );
      if (targetInstances > effectiveInstances) {
        isScaling = true;
        coldStartingInstances = targetInstances - effectiveInstances;
        // Cold instances are half capacity initially
        effectiveInstances = readyInstances + (coldStartingInstances * 0.5).ceil();
      }
    }

    return _AutoscaleState(
      effectiveInstances: effectiveInstances,
      isScaling: isScaling,
      targetInstances: targetInstances,
      readyInstances: readyInstances,
      coldStartingInstances: coldStartingInstances,
    );
  }

  double sampleServiceTimeMs(_SimComponentState state) {
    var mean = max(state.baseLatencyMs, 1.0);
    final prevCpu = state.prevMetrics?.cpuUsage ?? 0.0;
    final contention = 1.0 + (prevCpu * 0.6);
    final pressure = state.utilization;
    final pressureFactor = pressure > 0.7 ? 1.0 + (pressure - 0.7) * 2.0 : 1.0;
    mean *= contention * pressureFactor * state.slownessFactor;

    // Chaos: DB slowdown
    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.databaseSlowdown &&
          state.component.type == ComponentType.database) {
        mean *= (event.parameters['multiplier'] ?? 6.0);
      }
    }

    final sigma = 0.35 + (prevCpu * 0.4);
    return sampleLogNormal(mean, sigma).clamp(0.5, 60000.0);
  }

  double sampleNetworkLatencyMs(SystemComponent source, SystemComponent target) {
    final sourceRegion = source.config.regions.isNotEmpty ? source.config.regions.first : 'us-east-1';
    final targetRegion = target.config.regions.isNotEmpty ? target.config.regions.first : 'us-east-1';
    final sameRegion = sourceRegion == targetRegion;
    var base = sameRegion ? 2.0 + random.nextDouble() * 4.0 : 40.0 + random.nextDouble() * 90.0;

    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.networkLatency) {
        base += (event.parameters['latencyMs'] ?? 300).toDouble();
      }
    }

    final jitter = base * (0.1 + random.nextDouble() * 0.3);
    return base + jitter;
  }

  final componentMetrics = <String, ComponentMetrics>{};
  final connectionTraffic = <String, double>{};
  final failures = <FailureEvent>[];

  if (components.isEmpty) {
    return (componentMetrics, connectionTraffic, failures);
  }

  // Build connection maps
  final outgoing = <String, List<Connection>>{};
  final incoming = <String, List<Connection>>{};
  for (final c in components) {
    outgoing[c.id] = [];
    incoming[c.id] = [];
  }
  for (final conn in connections) {
    outgoing[conn.sourceId]?.add(conn);
    incoming[conn.targetId]?.add(conn);
  }

  final entryPoints = components.where((c) => (incoming[c.id] ?? []).isEmpty).toList();
  final effectiveEntryPoints = entryPoints.isEmpty ? components : entryPoints;
  final entryCount = max(1, effectiveEntryPoints.length);

  final totalRequests = max(0, incomingRps) * simWindowSeconds;
  final sampleCount = chooseSampleCount(totalRequests);
  final tokenWeight = sampleCount > 0 ? totalRequests / sampleCount : 0.0;

  // Initialize component states
  final states = <String, _SimComponentState>{};
  for (final component in components) {
    final prev = previousMetrics[component.id];
    final estimatedRps = entryPoints.contains(component)
        ? (incomingRps / entryCount)
        : (prev?.currentRps ?? 0);

    final autoscale = computeAutoscaleState(component, estimatedRps.toDouble());
    final effectiveInstances = max(1, autoscale.effectiveInstances);

    bool isCrashed = false;
    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.componentCrash) {
        final targetId = event.parameters['componentId'];
        if (targetId == null || targetId == component.id) {
          isCrashed = random.nextDouble() < 0.1;
        }
      }
    }

    final isSlow = random.nextDouble() < 0.02;
    final slownessFactor = isSlow ? (1.5 + random.nextDouble() * 3.5) : 1.0;
    final circuitOpen = component.config.circuitBreaker &&
        (prev?.errorRate ?? 0.0) > 0.25;

    final capacityPerInstance = component.config.capacity;
    final baseLatencyMs = max(1.0, _getBaseLatency(component.type));
    final concurrencyPerInstance = max(1, ((capacityPerInstance * baseLatencyMs) / 1000).round());
    final servers = effectiveInstances * concurrencyPerInstance;
    final rateLimitRps = component.config.rateLimitRps ??
        (capacityPerInstance * effectiveInstances);
    final rateLimitTokens = tokenWeight > 0
        ? (rateLimitRps * simWindowSeconds / tokenWeight).floor()
        : null;

    final maxQueueTokens = tokenWeight > 0
        ? max(
            10,
            max(
              servers * 4,
              (capacityPerInstance *
                      effectiveInstances *
                      2 *
                      simWindowSeconds /
                      tokenWeight)
                  .round(),
            ),
          )
        : 10;

    states[component.id] = _SimComponentState(
      component: component,
      prevMetrics: prev,
      servers: servers,
      capacityPerInstance: capacityPerInstance,
      baseLatencyMs: baseLatencyMs,
      isCrashed: isCrashed,
      isSlow: isSlow,
      slownessFactor: slownessFactor,
      circuitOpen: circuitOpen,
      rateLimitTokens: component.config.rateLimiting ? rateLimitTokens : null,
      maxQueueTokens: maxQueueTokens,
      autoscale: autoscale,
    );
  }

  // Event-driven simulation
  final events = _MinHeap();
  for (int i = 0; i < sampleCount; i++) {
    final entry = effectiveEntryPoints[random.nextInt(entryCount)];
    final time = random.nextDouble() * simWindowSeconds;
    events.add(_Event(
      time: time,
      type: _EventType.arrival,
      componentId: entry.id,
      token: _Token(weight: tokenWeight, arrivedAt: time),
    ));
  }

  final connectionTrafficRps = <String, double>{};

  void scheduleArrival({
    required double time,
    required String componentId,
    required _Token token,
    String? connectionId,
  }) {
    if (time > simWindowSeconds) return;
    events.add(_Event(
      time: time,
      type: _EventType.arrival,
      componentId: componentId,
      token: token.copyWith(arrivedAt: time),
      connectionId: connectionId,
    ));
  }

  void startService(_SimComponentState state, double time, _Token token) {
    state.inService += 1;
    final serviceMs = sampleServiceTimeMs(state);
    events.add(_Event(
      time: time + (serviceMs / 1000.0),
      type: _EventType.completion,
      componentId: state.component.id,
      token: token,
    ));
  }

  void maybeRetry({
    required _Token token,
    required String targetComponentId,
    required double time,
  }) {
    if (token.callerId == null) return;
    if (token.retryCount >= 3) return;
    final caller = states[token.callerId!]?.component;
    if (caller == null || !caller.config.retries) return;
    final backoffMs = 50.0 * pow(2, token.retryCount).toDouble();
    final jitterMs = backoffMs * (0.2 + random.nextDouble() * 0.4);
    scheduleArrival(
      time: time + ((backoffMs + jitterMs) / 1000.0),
      componentId: targetComponentId,
      token: token.copyWith(retryCount: token.retryCount + 1),
    );
  }

  while (events.isNotEmpty) {
    final event = events.pop();
    if (event.time > simWindowSeconds) break;
    final state = states[event.componentId];
    if (state == null) continue;

    if (event.type == _EventType.arrival) {
      state.arrivals += 1;

      // Circuit breaker / crash handling
      if (state.circuitOpen || state.isCrashed) {
        state.errors += 1;
        maybeRetry(
          token: event.token,
          targetComponentId: state.component.id,
          time: event.time,
        );
        continue;
      }

      // Rate limiting
      if (state.rateLimitTokens != null && state.arrivals > state.rateLimitTokens!) {
        state.isThrottled = true;
        state.errors += 1;
        continue;
      }

      // Queue capacity / backpressure
      if (state.queue.length + state.inService >= state.maxQueueTokens) {
        state.errors += 1;
        continue;
      }

      if (state.inService < state.servers) {
        startService(state, event.time, event.token);
      } else {
        state.queue.add(event.token);
      }
    } else {
      // Completion
      if (state.inService > 0) state.inService -= 1;
      state.processed += 1;
      final latencyMs = (event.time - event.token.arrivedAt) * 1000.0;
      state.totalLatencyMs += latencyMs;

      if (state.latencySamples.length < 200) {
        state.latencySamples.add(latencyMs);
      } else if (random.nextDouble() < 0.1) {
        final idx = random.nextInt(state.latencySamples.length);
        state.latencySamples[idx] = latencyMs;
      }

      // Start next queued request
      if (state.queue.isNotEmpty) {
        final nextToken = state.queue.removeAt(0);
        startService(state, event.time, nextToken);
      }

      // Simulate component-level failure probability (pressure + timeouts)
      final pressure = state.utilization;
      final overloadProb = pressure > 1.1 ? (pressure - 1.0) * 0.25 : 0.0;
      final timeoutProb = latencyMs > 3000 ? 0.4 : (latencyMs > 1500 ? 0.1 : 0.0);
      var errorProb = (overloadProb + timeoutProb).clamp(0.0, 0.9);
      if (pressure < 0.8 && latencyMs < 1200) {
        errorProb = 0.0;
      }
      final isError = random.nextDouble() < errorProb;
      if (isError) {
        state.errors += 1;
        maybeRetry(
          token: event.token,
          targetComponentId: state.component.id,
          time: event.time,
        );
        continue;
      }

      // Route to downstream components
      final outgoingConns = outgoing[state.component.id] ?? [];
      if (outgoingConns.isEmpty) continue;

      List<Connection> targets = outgoingConns;
      final isFanout = state.component.type == ComponentType.pubsub ||
          state.component.type == ComponentType.stream;

      if (!isFanout && targets.length > 1) {
        // Choose least pressured target (simple load balancing)
        targets = targets.toList()
          ..sort((a, b) {
            final aUtil = states[a.targetId]?.utilization ?? 0.0;
            final bUtil = states[b.targetId]?.utilization ?? 0.0;
            return aUtil.compareTo(bUtil);
          });
        targets = [targets.first];
      }

      final fanoutCap = isFanout ? min(5, targets.length) : targets.length;
      for (int i = 0; i < fanoutCap; i++) {
        final conn = targets[i];
        final targetState = states[conn.targetId];
        if (targetState == null) continue;

        // Backpressure on synchronous calls
        double extraDelayMs = 0.0;
        if (conn.type == ConnectionType.request || conn.type == ConnectionType.response) {
          final pressure = targetState.utilization;
          if (pressure > 1.3) {
            extraDelayMs += (pressure - 1.0) * 80.0;
            final dropProb = ((pressure - 2.2) * 0.25).clamp(0.0, 0.7);
            if (random.nextDouble() < dropProb) {
              state.errors += 1;
              maybeRetry(
                token: event.token,
                targetComponentId: conn.targetId,
                time: event.time,
              );
              continue;
            }
          }
        }

        final networkMs = sampleNetworkLatencyMs(state.component, targetState.component);
        final arrivalTime = event.time + ((networkMs + extraDelayMs) / 1000.0);

        connectionTrafficRps[conn.id] =
            (connectionTrafficRps[conn.id] ?? 0.0) + event.token.weight;

        scheduleArrival(
          time: arrivalTime,
          componentId: conn.targetId,
          connectionId: conn.id,
          token: event.token.copyWith(callerId: state.component.id),
        );
      }
    }
  }

  // Build metrics
  for (final component in components) {
    final state = states[component.id]!;
    final prev = state.prevMetrics;
    final arrivalRps = tokenWeight > 0
        ? (state.arrivals * tokenWeight / simWindowSeconds)
        : 0.0;

    final capacity = component.config.capacity * state.autoscale.effectiveInstances;
    final effectiveLoad = capacity > 0 ? (arrivalRps / capacity) : 1.0;

    final avgLatency = state.latencySamples.isNotEmpty
        ? (state.totalLatencyMs / state.latencySamples.length)
        : (prev?.latencyMs ?? 0.0);
    final p95Latency = state.latencySamples.isNotEmpty
        ? percentile(state.latencySamples, 0.95)
        : (prev?.p95LatencyMs ?? avgLatency);

    final jitter = state.latencySamples.isNotEmpty
        ? (p95Latency - avgLatency).abs()
        : (prev?.jitter ?? 0.0);

    final rawErrorRate =
        state.arrivals > 0 ? (state.errors / state.arrivals) : 0.0;
    final errorRate = smooth(
      rawErrorRate,
      prev?.errorRate ?? 0.0,
      rawErrorRate > (prev?.errorRate ?? 0.0) ? 0.5 : 0.2,
    );

    final targetCpu = (effectiveLoad * 0.85 + random.nextDouble() * 0.15)
        .clamp(0.0, 1.0);
    final prevCpu = prev?.cpuUsage ?? 0.0;
    final cpuAlpha = targetCpu > prevCpu ? 0.15 : 0.35;
    final cpuUsage = smooth(targetCpu, prevCpu, cpuAlpha);

    final targetMemory =
        (effectiveLoad * 0.75 + random.nextDouble() * 0.25)
            .clamp(0.0, 1.0);
    final prevMemory = prev?.memoryUsage ?? 0.0;
    final memAlpha = targetMemory > prevMemory ? 0.15 : 0.35;
    final memoryUsage = smooth(targetMemory, prevMemory, memAlpha);

    double cacheHitRate = 0.0;
    double evictionRate = 0.0;
    if (component.type == ComponentType.cache) {
      cacheHitRate = (0.9 - effectiveLoad * 0.3).clamp(0.0, 1.0);
      if (memoryUsage > 0.8) {
        evictionRate = (memoryUsage - 0.8) * 5000;
      }
    }

    double queueDepth = (state.queue.length + state.inService) * tokenWeight;
    queueDepth = smooth(queueDepth, prev?.queueDepth ?? 0.0, 0.2);

    double connectionPoolUtilization = 0.0;
    int activeConnections = 0;
    final maxConnections = state.autoscale.effectiveInstances * 100;
    if (component.type == ComponentType.database ||
        component.type == ComponentType.appServer ||
        component.type == ComponentType.customService) {
      connectionPoolUtilization = smooth(
        effectiveLoad.clamp(0.0, 1.0),
        prev?.connectionPoolUtilization ?? 0.0,
        0.2,
      );
      activeConnections = (maxConnections * connectionPoolUtilization).toInt();
    }

    final metrics = ComponentMetrics(
      cpuUsage: cpuUsage,
      memoryUsage: memoryUsage,
      currentRps: arrivalRps.round(),
      latencyMs: avgLatency,
      p95LatencyMs: p95Latency,
      errorRate: errorRate,
      queueDepth: queueDepth,
      cacheHitRate: cacheHitRate,
      jitter: jitter,
      connectionPoolUtilization: connectionPoolUtilization,
      evictionRate: evictionRate,
      isThrottled: state.isThrottled,
      isCircuitOpen: state.circuitOpen,
      activeConnections: activeConnections,
      maxConnections: maxConnections,
      isScaling: state.autoscale.isScaling,
      targetInstances: state.autoscale.targetInstances,
      readyInstances: state.autoscale.readyInstances,
      coldStartingInstances: state.autoscale.coldStartingInstances,
      isSlow: state.isSlow,
      slownessFactor: state.slownessFactor,
      isCrashed: state.isCrashed,
    );

    componentMetrics[component.id] = metrics;
    failures.addAll(_checkFailures(component, metrics, problem, components, connections));
  }

  // Connection traffic visualization
  for (final connection in connections) {
    final flowRps = (connectionTrafficRps[connection.id] ?? 0.0) / simWindowSeconds;
    final flow = (flowRps / 2000.0).clamp(0.0, 1.0);
    connectionTraffic[connection.id] = flow;
  }

  return (componentMetrics, connectionTraffic, failures);
}

/// Sort components so dependencies are processed after sources
List<SystemComponent> _topologicalSort(List<SystemComponent> components, List<Connection> connections) {
  final result = <SystemComponent>[];
  final visited = <String>{};
  final processing = <String>{};

  void visit(String nodeId) {
    if (visited.contains(nodeId)) return;
    if (processing.contains(nodeId)) {
      // Cycle detected - treat as visited to break loop
      return; 
    }
    
    processing.add(nodeId);
    
    // Visit dependencies (downstream)
    // Actually for metrics flow (Traffic), we want Source -> Target.
    // So we want to process Source BEFORE Target.
    // Topological sort usually gives: if A -> B, A comes before B.
    // We visit children first? No.
    // Standard Algo:
    // Visit(N):
    //   processing.add(N)
    //   for each M in children(N): Visit(M)
    //   processing.remove(N)
    //   visited.add(N)
    //   result.prepend(N) -> giving Reverse Topological
    
    // BUT we want Traffic Flow Order: Sources First.
    // That means if A -> B, A processed first.
    // That is Topological Sort.
    
    // Find all nodes that are TARGETS of this node (Children)
    final children = connections.where((c) => c.sourceId == nodeId).map((c) => c.targetId);
    for (final childId in children) {
       // Wait, standard DFS topo sort puts leaves at start of list (Reverse Post-Order).
       // We need Reverse(Reverse Post-Order) i.e. Sources first.
    }
    // Let's implement Khan's Algorithm (BFS based) which is easier for "Levels"
  }
  
  // Khan's Algorithm
  final inDegree = <String, int>{};
  final graph = <String, List<String>>{};
  
  for (final c in components) {
    inDegree[c.id] = 0;
    graph[c.id] = [];
  }
  
  for (final conn in connections) {
    if (graph.containsKey(conn.sourceId)) {
      graph[conn.sourceId]!.add(conn.targetId);
    }
    // Increment In-Degree of Target
    if (inDegree.containsKey(conn.targetId)) {
      inDegree[conn.targetId] = inDegree[conn.targetId]! + 1;
    }
  }
  
  final queue = <String>[];
  // Add all sources (inDegree 0)
  inDegree.forEach((id, degree) {
    if (degree == 0) queue.add(id);
  });
  
  while (queue.isNotEmpty) {
    final u = queue.removeAt(0);
    final component = components.firstWhere((c) => c.id == u, orElse: () => SystemComponent(id: 'dummy', type: ComponentType.client, position: const Offset(0,0), size: const Size(0,0), config: const ComponentConfig()));
    if (component.id != 'dummy') {
      result.add(component);
    }
    
    if (graph.containsKey(u)) {
      for (final v in graph[u]!) {
        inDegree[v] = inDegree[v]! - 1;
        if (inDegree[v] == 0) {
          queue.add(v);
        }
      }
    }
  }
  
  // If result size < components size, we have cycles.
  // Add remaining components freely (cycle breakers)
  if (result.length < components.length) {
    final processedIds = result.map((c) => c.id).toSet();
    for (final c in components) {
      if (!processedIds.contains(c.id)) {
        result.add(c);
      }
    }
  }
  
  return result;
}

ComponentMetrics _calculateComponentMetrics(
  SystemComponent component,
  int incomingRps,
  Problem problem,
  Random random,
  List<Connection> connections,
  List<SystemComponent> allComponents,
  List<ChaosEvent> activeChaosEvents,
  ComponentMetrics? prevMetrics,
  double downstreamLatencyMs, // NEW
) {
  final baseLatency = _getBaseLatency(component.type);
  var effectiveInstances = component.config.instances;

  // Use previous metrics or default to component's current (which might be stale if optimization is on)
  // or better, default to 0/empty if actually first run.
  final lastMetrics = prevMetrics ?? component.metrics;
  
  // APPLY CHAOS: Component Crash
  bool isCrashed = false;
  for (final event in activeChaosEvents) {
    if (event.type == ChaosType.componentCrash) {
      if (random.nextDouble() < 0.01) isCrashed = true;
    }
  }

  // Simulate autoscaling: if autoscale enabled and load > 0.7, scale up
  final capacity = component.config.capacity * component.config.instances;
  final load = capacity > 0 ? incomingRps / capacity : 1.0;
  
  bool isScaling = false;
  int targetInstances = effectiveInstances;
  int readyInstances = effectiveInstances;
  int coldStartingInstances = 0;
  
  if (component.config.autoScale && load > 0.7) {
    targetInstances = (effectiveInstances * 1.5).ceil().clamp(
      component.config.minInstances,
      component.config.maxInstances,
    );
    
    if (targetInstances > effectiveInstances) {
      isScaling = true;
      // Simulate autoscaling delay: new instances are cold starting
      coldStartingInstances = targetInstances - effectiveInstances;
      // Cold instances only provide 50% capacity initially
      effectiveInstances = readyInstances + (coldStartingInstances * 0.5).ceil();
    }
  }
  
  // Recalculate with effective instances
  final effectiveCapacity = component.config.capacity * effectiveInstances;
  final effectiveLoad = effectiveCapacity > 0 ? incomingRps / effectiveCapacity : 1.0;

  // Slow node simulation (5% chance a node becomes slow)
  bool isSlow = random.nextDouble() < 0.05;
  double slownessFactor = isSlow ? (2.0 + random.nextDouble() * 8.0) : 1.0;

  // APPLY CHAOS: Latency & DB Slowdown
  for (final event in activeChaosEvents) {
    if (event.type == ChaosType.networkLatency) {
      // Add global latency
      slownessFactor += (event.parameters['latencyMs'] ?? 300) / 50.0; // Rough conversion
    } else if (event.type == ChaosType.databaseSlowdown && component.type == ComponentType.database) {
      slownessFactor *= (event.parameters['multiplier'] ?? 8.0);
    }
  }

  // Latency calculation with slowness factor
  double latencyMultiplier;
  if (effectiveLoad < 0.7) {
    latencyMultiplier = 1.0 + (effectiveLoad * 0.3);
  } else if (effectiveLoad < 0.9) {
    latencyMultiplier = 1.21 + ((effectiveLoad - 0.7) / 0.2) * 3.79;
  } else {
    latencyMultiplier = 5.0 + ((effectiveLoad - 0.9) / 0.1) * 15.0;
  }

  // Calculate Cross-Region Latency Penalty
  double crossRegionPenalty = 0.0;
  final incomingConnections = connections.where((c) => c.targetId == component.id);
  
  if (incomingConnections.isNotEmpty) {
    final region = component.config.regions.isNotEmpty ? component.config.regions.first : 'us-east-1';
    int crossRegionCount = 0;
    
    for (final conn in incomingConnections) {
      final source = allComponents.firstWhere((c) => c.id == conn.sourceId, orElse: () => component);
      final sourceRegion = source.config.regions.isNotEmpty ? source.config.regions.first : 'us-east-1';
      
      if (sourceRegion != region) {
        crossRegionCount++;
      }
    }
    
    // If >50% of traffic is cross-region, add penalty
    if (crossRegionCount > incomingConnections.length * 0.5) {
      crossRegionPenalty = 100.0 + random.nextDouble() * 50.0; // 100-150ms penalty
    }
  }

  // Inertia factor (0.1 = very slow/heavy, 1.0 = instant)
  // Low alpha makes the system feel "heavy" and realistic
  const alpha = 0.15; 
  
  // Calculate Target Latency
  // = (Base Processing + Load Penalty) * SlownessFactor + CrossRegion + Downstream Dependencies
  
  // Add downstream latency (Backpressure)
  // If this component calls others synchronously, their latency adds to ours.
  // For queues/pubsub, it's async, so downstream latency matters less (only for write ack)
  double downstreamPenalty = downstreamLatencyMs;
  if (component.type == ComponentType.queue || component.type == ComponentType.pubsub) {
    downstreamPenalty *= 0.1; // Async mostly
  }
  
  final rawLatency = (baseLatency * latencyMultiplier * slownessFactor) + crossRegionPenalty + downstreamPenalty;
  
  // Smooth latency: moves slowly towards rawLatency using LAST metrics
  final avgLatency = (rawLatency * alpha) + (lastMetrics.latencyMs * (1 - alpha));
  
  final p95Latency = avgLatency * (1.5 + random.nextDouble() * 0.5);

  // CPU and memory
  final targetCpu = (effectiveLoad * 0.85 + random.nextDouble() * 0.15).clamp(0.0, 1.0);
  final cpuUsage = (targetCpu * alpha) + (lastMetrics.cpuUsage * (1 - alpha));
  
  final targetMemory = (effectiveLoad * 0.75 + random.nextDouble() * 0.25).clamp(0.0, 1.0);
  final memoryUsage = (targetMemory * alpha) + (lastMetrics.memoryUsage * (1 - alpha));

  // Error rate - more aggressive when capacity exceeded
  double targetErrorRate = 0.0;
  if (isCrashed) {
    targetErrorRate = 1.0; // 100% failure rate
  } else if (effectiveLoad > 1.0) {
    // HARD overflow: immediate significant errors
    targetErrorRate = 0.1 + ((effectiveLoad - 1.0) * 0.8).clamp(0.0, 0.9);
  } else if (effectiveLoad > 0.95) {
    targetErrorRate = ((effectiveLoad - 0.95) / 0.05) * 0.5;
  } else if (effectiveLoad > 0.85) {
    targetErrorRate = ((effectiveLoad - 0.85) / 0.1) * 0.05;
  }
  // Error rate spikes instantly but recovers slowly
  final errorAlpha = (isCrashed || targetErrorRate > lastMetrics.errorRate) ? 0.5 : 0.1;
  double errorRate = (targetErrorRate * errorAlpha) + (lastMetrics.errorRate * (1 - errorAlpha));
  errorRate = errorRate.clamp(0.0, 1.0);

  // Cache hit rate and Resilience Metrics
  double cacheHitRate = 0.0;
  double evictionRate = 0.0;
  bool isThrottled = false;
  bool isCircuitOpen = false;

  if (component.type == ComponentType.cache) {
    cacheHitRate = (0.9 - effectiveLoad * 0.3).clamp(0.0, 1.0);
    
    // Simulate evictions if memory usage is high (>80%)
    if (memoryUsage > 0.8) {
      // Eviction rate drastically increases as memory fills up
      evictionRate = (memoryUsage - 0.8) * 5000; // up to 1000+ evictions/sec
    }
  }

  // Queue depth
  double queueDepth = 0.0;
  if (component.type == ComponentType.queue ||
      component.type == ComponentType.pubsub ||
      component.type == ComponentType.stream) {
    // Accumulate queue: Previous + (In - Out)
    // Simple model: Queue builds if load > capacity
    final targetQueue = (incomingRps * effectiveLoad * 0.1).clamp(0.0, 10000.0);
    queueDepth = (targetQueue * alpha) + (lastMetrics.queueDepth * (1 - alpha));
  }

  // Connection pool metrics (for databases and services)
  double connectionPoolUtilization = 0.0;
  int activeConnections = 0;
  final maxConnections = component.config.instances * 100;
  
  if (component.type == ComponentType.database ||
      component.type == ComponentType.appServer ||
      component.type == ComponentType.customService) {
    // Connection pool utilization tracks with load
    final targetUtil = effectiveLoad.clamp(0.0, 1.0);
    connectionPoolUtilization = (targetUtil * alpha) + (lastMetrics.connectionPoolUtilization * (1 - alpha));
    activeConnections = (maxConnections * connectionPoolUtilization).toInt();
  }

  final jitter = avgLatency * 0.1 * (1.0 + effectiveLoad);

  return ComponentMetrics(
    cpuUsage: cpuUsage,
    memoryUsage: memoryUsage,
    currentRps: incomingRps,
    latencyMs: avgLatency,
    p95LatencyMs: p95Latency,
    errorRate: errorRate,
    queueDepth: queueDepth,
    cacheHitRate: cacheHitRate,
    jitter: jitter,
    connectionPoolUtilization: connectionPoolUtilization,
    evictionRate: evictionRate,
    isThrottled: isThrottled,
    isCircuitOpen: isCircuitOpen,
    activeConnections: activeConnections,
    maxConnections: maxConnections,
    isScaling: isScaling,
    targetInstances: targetInstances,
    readyInstances: readyInstances,
    coldStartingInstances: coldStartingInstances,
    isSlow: isSlow,
    slownessFactor: slownessFactor,
    isCrashed: isCrashed,
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
    ComponentType.shardNode ||
    ComponentType.partitionNode ||
    ComponentType.replicaNode ||
    ComponentType.inputNode ||
    ComponentType.outputNode ||
    ComponentType.rectangle || 
    ComponentType.circle || 
    ComponentType.diamond ||
    ComponentType.arrow || 
    ComponentType.line => 0.0,
  };
}

/// Check for various failure conditions
List<FailureEvent> _checkFailures(
  SystemComponent component,
  ComponentMetrics metrics,
  Problem problem,
  List<SystemComponent> allComponents,
  List<Connection> allConnections,
) {
  final failures = <FailureEvent>[];

  // CHAOS: Crashed Component
  if (metrics.isCrashed) {
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.componentCrash,
      message: '${component.type.displayName} has crashed due to chaos event',
      recommendation: 'Wait for automated recovery or restart component',
      severity: 1.0,
      userVisible: true,
    ));
    // If crashed, return early or continue? 
    // Usually a crash masks other errors, so we can return early or keep adding.
    // Let's clear others? No, keep it simple.
    return failures; 
  }

  // 0. Traffic Overflow - Explicit check when incoming traffic exceeds capacity
  final totalCapacity = component.config.capacity * component.config.instances;
  if (metrics.currentRps > totalCapacity && totalCapacity > 0) {
    final overflowPct = ((metrics.currentRps - totalCapacity) / totalCapacity * 100).toInt();
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.trafficOverflow,
      message: '${component.type.displayName} receiving ${metrics.currentRps} RPS but capacity is ${totalCapacity} RPS (+${overflowPct}% overflow)',
      recommendation: component.config.autoScale 
          ? 'Autoscaling in progress - consider higher capacity per instance or more max instances'
          : 'Enable autoscaling OR increase instances/capacity to handle ${metrics.currentRps} RPS',
      severity: (overflowPct / 100).clamp(0.7, 0.95),
      userVisible: true,
      fixType: component.config.autoScale ? FixType.increaseReplicas : FixType.enableAutoscaling,
    ));
  }

  // 1. Overload - Only when incoming RPS exceeds effective capacity
  // Check actual capacity considering all scaling techniques
  final baseCapacity = component.config.capacity * component.config.instances;
  var effectiveCapacity = baseCapacity.toDouble();
  
  // Apply sharding multiplier (N shards = N× write capacity)
  if (component.config.sharding && component.config.partitionCount > 1) {
    effectiveCapacity *= component.config.partitionCount;
  }
  
  // Apply replication read scaling (Leader + followers boost read capacity)
  if (component.config.replication && component.config.replicationFactor > 1) {
    if (component.type == ComponentType.database || component.type == ComponentType.cache) {
      final readCapacity = effectiveCapacity * component.config.replicationFactor;
      // Assume 80% reads, 20% writes
      effectiveCapacity = (readCapacity * 0.8) + (effectiveCapacity * 0.2);
    }
  }
  
  // Only error if significantly over capacity (110% threshold to avoid flapping)
  if (metrics.currentRps > effectiveCapacity * 1.1 && effectiveCapacity > 0) {
    final overloadPct = ((metrics.currentRps / effectiveCapacity - 1.0) * 100).toInt();
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.overload,
      message: '${component.type.displayName} overloaded: ${metrics.currentRps} RPS exceeds ${effectiveCapacity.toInt()} RPS (+$overloadPct%)',
      recommendation: component.config.autoScale
          ? 'Autoscaling active - manually add instances via Increase Replicas if needed'
          : 'Enable autoscaling or manually add more instances',
      severity: ((metrics.currentRps / effectiveCapacity - 1.0) / 2.0).clamp(0.5, 0.95),
      userVisible: true,
      fixType: component.config.autoScale ? FixType.increaseReplicas : FixType.enableAutoscaling,
    ));
  }

  // 2. Single Point of Failure (Design-time warning - shows even without traffic)
  // SMARTER CHECK: Only show if component is actually receiving traffic AND there's no sibling redundancy
  if (component.config.instances == 1 && _isCriticalPath(component.type) && metrics.currentRps > 0) {
    if (!component.config.autoScale) {
      // Look for sibling components that provide redundancy
      // A sibling is a component of the same type that shares AT LEAST ONE common source
      final mySources = allConnections.where((c) => c.targetId == component.id).map((c) => c.sourceId).toSet();
      
      bool hasSiblingRedundancy = false;
      if (mySources.isNotEmpty) {
        final similarComponents = allComponents.where((c) => c.id != component.id && c.type == component.type);
        
        for (final other in similarComponents) {
          final otherSources = allConnections.where((c) => c.targetId == other.id).map((c) => c.sourceId).toSet();
          // If they share a source, they are redundant paths from that source
          if (mySources.intersection(otherSources).isNotEmpty) {
            hasSiblingRedundancy = true;
            break;
          }
        }
      }

      if (!hasSiblingRedundancy) {
        failures.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: component.id,
          type: FailureType.spof,
          message: '${component.type.displayName} is a single point of failure',
          recommendation: 'Increase instance count, enable autoscaling, or add a redundant ${component.type.displayName} node',
          severity: 0.8,
          userVisible: true,
          fixType: FixType.increaseReplicas,
        ));
      }
    }
  }

  // 3. Latency Breach (Runtime error - only check when processing traffic)
  if (metrics.currentRps > 0 && metrics.p95LatencyMs > problem.constraints.maxLatencyMs) {
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.latencyBreach,
      message: 'P95 latency ${metrics.p95LatencyMs.toStringAsFixed(0)}ms exceeds SLA (${problem.constraints.maxLatencyMs}ms)',
      recommendation: 'Optimize performance or add capacity',
      severity: 0.7,
      userVisible: true,
      fixType: component.config.autoScale ? FixType.increaseReplicas : FixType.enableAutoscaling,
    ));
  }

  // 3b. Upstream Timeout (Runtime error - severe tail latency)
  if (metrics.currentRps > 0 &&
      metrics.p95LatencyMs > (problem.constraints.maxLatencyMs * 2)) {
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.upstreamTimeout,
      message: 'Upstream timeouts likely: P95 ${metrics.p95LatencyMs.toStringAsFixed(0)}ms',
      recommendation: 'Add timeouts, fallbacks, or increase capacity to reduce tail latency',
      severity: 0.8,
      userVisible: true,
      fixType: component.config.autoScale ? FixType.increaseReplicas : FixType.enableAutoscaling,
    ));
  }

  // 4. Data Loss Risk
  if (component.type == ComponentType.database && !component.config.replication) {
    // HOLISTIC CHECK: Only show if no sibling redundancy
    final mySources = allConnections.where((c) => c.targetId == component.id).map((c) => c.sourceId).toSet();
    bool hasSiblingRedundancy = false;
    if (mySources.isNotEmpty) {
      hasSiblingRedundancy = allComponents.any((other) => 
        other.id != component.id && 
        other.type == component.type &&
        allConnections.where((c) => c.targetId == other.id).any((c) => mySources.contains(c.sourceId))
      );
    }

    if (!hasSiblingRedundancy) {
      failures.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: component.id,
        type: FailureType.dataLoss,
        message: 'Database has no replication - risk of data loss',
        recommendation: 'Enable replication with factor >= 2 or add a redundant database node',
        severity: 0.9,
        userVisible: false,
        fixType: FixType.enableReplication,
      ));
    }
  }

  // 5. Queue Overflow
  if (component.type == ComponentType.queue || 
      component.type == ComponentType.pubsub ||
      component.type == ComponentType.stream) {
    if (metrics.queueDepth > 2000 && metrics.queueDepth <= 5000) {
      failures.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: component.id,
        type: FailureType.consumerLag,
        message: 'Consumer lag building: queue depth ${metrics.queueDepth.toStringAsFixed(0)}',
        recommendation: 'Scale consumers or increase processing capacity',
        severity: (metrics.queueDepth / 8000).clamp(0.4, 0.8),
        userVisible: true,
        fixType: component.config.autoScale ? FixType.increaseReplicas : FixType.enableAutoscaling,
      ));
    }
    if (metrics.queueDepth > 5000) {
      failures.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: component.id,
        type: FailureType.queueOverflow,
        message: 'Queue depth at ${metrics.queueDepth.toStringAsFixed(0)} - backpressure building',
        recommendation: 'Add more consumers or increase processing capacity',
        severity: (metrics.queueDepth / 10000).clamp(0.5, 0.9),
        userVisible: true,
        fixType: component.config.dlq ? FixType.increaseReplicas : FixType.addDlq,
      ));
    }
  }

  // NEW: 6. Connection Pool Exhaustion (Runtime error - only when processing)
  if (metrics.currentRps > 0 && metrics.connectionPoolUtilization > 0.9) {
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.connectionExhaustion,
      message: 'Connection pool ${(metrics.connectionPoolUtilization * 100).toStringAsFixed(0)}% full (${metrics.activeConnections}/${metrics.maxConnections})',
      recommendation: 'Increase connection pool size or add more instances',
      severity: 0.8,
      userVisible: true,
      fixType: FixType.increaseConnectionPool,
    ));
  }

  // NEW: 7. Slow Node Detection (Runtime error - only when processing)
  if (metrics.currentRps > 0 && metrics.isSlow) {
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.slowNode,
      message: '${component.type.displayName} responding ${metrics.slownessFactor.toStringAsFixed(1)}× slower than normal',
      recommendation: 'Investigate node health, restart or replace slow instance',
      severity: 0.7,
      expectedRecoveryTime: const Duration(seconds: 60),
      userVisible: true,
      fixType: FixType.increaseReplicas, // Add capacity to mitigate slow node
    ));
  }

  // NEW: 8. Autoscaling Delay Warning
  if (metrics.isScaling && metrics.coldStartingInstances > 0) {
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.scaleUpDelay,
      message: 'Scaling up: ${metrics.coldStartingInstances} instances still warming up',
      recommendation: 'Already autoscaling - wait 30-300s for new capacity',
      severity: 0.4,
      expectedRecoveryTime: const Duration(seconds: 120),
      userVisible: false,
    ));
    
    // Also add cold start penalty notice
    failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.coldStart,
      message: 'Cold start penalty: new instances at 50% capacity',
      recommendation: 'Consider keeping min instances higher to avoid cold starts',
      severity: 0.3,
      userVisible: false,
    ));
  }

  // NEW: 9. Cache Eviction / Stampede Warning
  if (component.type == ComponentType.cache && metrics.evictionRate > 500) {
     failures.add(FailureEvent(
      timestamp: DateTime.now(),
      componentId: component.id,
      type: FailureType.cacheStampede,
      message: 'High eviction rate (${metrics.evictionRate.toStringAsFixed(0)}/sec) - Cache is thrashing',
      recommendation: 'Increase cache memory or optimize TTL strategy',
      severity: 0.6,
      userVisible: true,
      fixType: FixType.increaseReplicas, // Effectively adds more total memory
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
  double maxP95Latency = 0;
  double totalErrorRate = 0;
  double totalCost = 0;

  // We'll calculate a weighted average for latency based on component types
  // and their relative importance in the path.
  int pathLength = 0;
  for (final component in components) {
    final metrics = componentMetrics[component.id];
    if (metrics != null) {
      if (_isCriticalPath(component.type)) {
        totalLatency += metrics.latencyMs;
        pathLength++;
      }
      
      if (metrics.p95LatencyMs > maxP95Latency) {
        maxP95Latency = metrics.p95LatencyMs;
      }
      
      // Error rate is probabilistic: P(success) = P(s1) * P(s2) * ...
      // So totalErrorRate = 1 - (1-e1)*(1-e2)*...
      totalErrorRate = totalErrorRate + metrics.errorRate - (totalErrorRate * metrics.errorRate);
    }
    totalCost += component.hourlyCost;
  }

  final availability = (1 - totalErrorRate).clamp(0.0, 1.0);
  final avgLatency = pathLength > 0 ? totalLatency : 0.0;

  return GlobalMetrics(
    totalRps: totalRps,
    avgLatencyMs: avgLatency,
    p50LatencyMs: avgLatency * 1.1, // P50 is usually slightly higher than avg
    p95LatencyMs: maxP95Latency,
    p99LatencyMs: maxP95Latency * 1.8, // P99 is significantly higher
    errorRate: totalErrorRate,
    availability: availability,
    totalCostPerHour: totalCost,
    totalRequests: totalRps,
    successfulRequests: ((1 - totalErrorRate) * totalRps).toInt(),
    failedRequests: (totalErrorRate * totalRps).toInt(),
  );
}

bool _isCriticalPath(ComponentType type) {
  return switch (type) {
    ComponentType.loadBalancer ||
    ComponentType.apiGateway ||
    ComponentType.appServer ||
    ComponentType.database ||
    ComponentType.cache ||
    ComponentType.serverless ||
    ComponentType.customService => true,
    _ => false,
  };
}

double _getTrafficMultiplier(int tickCount) {
  final random = Random(tickCount);
  
  // 1. Base Cyclic Load (Day/Night cycle)
  // Period of 200 ticks for a partial day cycle during the 300-tick sim
  final phase = (tickCount / 200.0) * 2 * pi;
  // Base varies between 0.7 (night) and 1.3 (peak day)
  double multiplier = 1.0 + 0.3 * sin(phase - pi / 2);
  
  // 2. Random Noise/Jitter (±15%) which is realistic for web traffic
  final noise = (random.nextDouble() - 0.5) * 0.3;
  multiplier += noise;
  
  // 3. Random Spikes (Flash Crowds / Viral Events)
  // 4% chance of a sharp spike (1.5x to 3.0x load)
  if (random.nextDouble() > 0.96) {
    final spikeFactor = 1.5 + random.nextDouble() * 1.5;
    multiplier *= spikeFactor;
  } 
  // 4. Occasional Dips (Network issues elsewhere)
  // 2% chance of traffic drop
  else if (random.nextDouble() < 0.02) {
    multiplier *= 0.6;
  }
  
  // Ensure we don't go negative or too close to zero
  return multiplier.clamp(0.2, 10.0);
}

/// Check for consistency issues using the consistency validator
List<FailureEvent> _checkConsistencyIssues(
  List<SystemComponent> components,
  List<Connection> connections,
  Map<String, ComponentMetrics> componentMetrics,
  int tickCount,
) {
  // Import consistency validator logic inline to avoid import issues in isolate
  final issues = <FailureEvent>[];
  final random = Random(tickCount);
  
  // Check database replication lag
  for (final db in components.where((c) => c.type == ComponentType.database)) {
    if (db.config.replication && db.config.replicationFactor > 1) {
      final metrics = componentMetrics[db.id];
      if (metrics == null) continue;
      
      final load = metrics.cpuUsage;
      final lagMs = (50 + load * 2000).toInt();
      
      if (lagMs > 500) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: db.id,
          type: FailureType.replicationLag,
          message: 'Replication lag ${lagMs}ms - users may see stale data',
          recommendation: 'Use read-your-writes consistency or strong reads',
          severity: (lagMs / 2000).clamp(0.3, 0.7),
          userVisible: true,
          fixType: FixType.increaseReplicas,
        ));
      }
    }
    
    // Check for lost updates
    final metrics = componentMetrics[db.id];
    if (metrics != null && metrics.currentRps > 100) {
      final hasQuorum = db.config.quorumWrite != null && db.config.quorumWrite! > 1;
      if (!hasQuorum && random.nextDouble() < 0.02) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: db.id,
          type: FailureType.lostUpdate,
          message: 'Concurrent write conflict detected',
          recommendation: 'Use optimistic locking or quorum writes',
          severity: 0.8,
          userVisible: true,
        ));
      }
    }
  }
  
  // Check for cache stampede
  for (final cache in components.where((c) => c.type == ComponentType.cache)) {
    final metrics = componentMetrics[cache.id];
    if (metrics != null && metrics.cacheHitRate < 0.3 && metrics.currentRps > 1000) {
      final connectedDbs = connections
          .where((c) => c.sourceId == cache.id)
          .map((c) => c.targetId)
          .toList();
      
      if (connectedDbs.isNotEmpty) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: cache.id,
          type: FailureType.cacheStampede,
          message: 'Cache stampede overwhelming database',
          recommendation: 'Use cache warming or probabilistic early expiration',
          severity: 0.7,
          affectedComponents: connectedDbs,
          userVisible: true,
        ));
      }
    }
  }
  
  return issues;
}

/// Check if failures should cascade to dependent components
List<FailureEvent> _checkCascadingFailures(
  List<SystemComponent> components,
  List<Connection> connections,
  Map<String, ComponentMetrics> componentMetrics,
  List<FailureEvent> currentFailures,
) {
  final cascaded = <FailureEvent>[];
  
  // Only cascade severe failures
  final severeFailures = currentFailures.where((f) => 
    f.severity > 0.6 && 
    (f.type == FailureType.overload || 
     f.type == FailureType.latencyBreach ||
     f.type == FailureType.cacheStampede)
  ).toList();
  
  for (final failure in severeFailures) {
    // Find all downstream components
    final downstreamIds = connections
        .where((c) => c.sourceId == failure.componentId)
        .map((c) => c.targetId)
        .toSet();
    
    // Track components that already have a cascading failure this tick
    final cascadedTargetIds = <String>{};
    
    for (final downstreamId in downstreamIds) {
      if (cascadedTargetIds.contains(downstreamId)) continue;
      
      try {
        final component = components.firstWhere((c) => c.id == downstreamId);
        
        // Circuit breaker check
        if (component.config.circuitBreaker) {
          // Circuit breaker prevents cascade but adds its own failure
          cascaded.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: downstreamId,
            type: FailureType.circuitBreakerOpen,
            message: '${component.type.displayName} circuit breaker opened',
            recommendation: 'Circuit breaker protecting from cascade - good!',
            severity: 0.3,
            affectedComponents: [failure.componentId],
            userVisible: false,
          ));
          cascadedTargetIds.add(downstreamId);
        } else {
          // Failure cascades (50% probability for realism)
          if (Random().nextDouble() > 0.5) {
            cascaded.add(FailureEvent(
              timestamp: DateTime.now(),
              componentId: downstreamId,
              type: FailureType.cascadingFailure,
              message: '${component.type.displayName} affected by upstream failure',
              recommendation: 'Add circuit breaker or fallback logic',
              severity: failure.severity * 0.8,
              affectedComponents: [failure.componentId, downstreamId],
              userVisible: true,
              fixType: FixType.addCircuitBreaker,
            ));
            cascadedTargetIds.add(downstreamId);
          }
        }
      } catch (_) {
        // Component not found, skip
      }
    }
  }
  
  return cascaded;
}

/// Simulate rare network partition events
/// Simulate network partitions (split-brain) and Regional Outages
FailureEvent? _simulateNetworkPartition(
  List<SystemComponent> components,
  int tickCount,
  Random random,
) {
  // Very rare event (0.05% chance per tick)
  if (random.nextDouble() > 0.0005) return null;

  // 1. Regional Outage Simulation
  // Pick a random region to fail
  final regions = ['us-east-1', 'us-west-2', 'eu-central-1', 'ap-southeast-1'];
  final failedRegion = regions[random.nextInt(regions.length)];
  
  final affectedComponents = components.where((c) {
    // Check if component is in the failed region
    // Default to us-east-1 if implementation is missing regions list
    final region = c.config.regions.isNotEmpty ? c.config.regions.first : 'us-east-1';
    return region == failedRegion;
  }).toList();

  if (affectedComponents.isEmpty) return null;

  // Impact: Set availability to 0 for all components in the region
  // Note: We can't modify components directly here as they are copies
  // The impact is simulated by returning a critical failure event
  
  return FailureEvent(
    timestamp: DateTime.now(),
    componentId: 'infrastructure', // System-wide event
    type: FailureType.networkPartition,
    message: 'Regional Outage: $failedRegion is down',
    recommendation: 'Enable multi-region failover and active-active replication',
    severity: 1.0,
    affectedComponents: affectedComponents.map((c) => c.id).toList(),
    expectedRecoveryTime: const Duration(minutes: 5),
    userVisible: true,
  );
}

/// Detect retry storms (exponential retry amplification)
List<FailureEvent> _detectRetryStorms(
  List<SystemComponent> components,
  Map<String, ComponentMetrics> componentMetrics,
  List<Connection> connections,
) {
  final storms = <FailureEvent>[];
  
  for (final component in components) {
    // Check components with retries enabled but no circuit breaker
    if (component.config.retries && !component.config.circuitBreaker) {
      final metrics = componentMetrics[component.id];
      if (metrics == null) continue;
      
      // Retry storm occurs when error rate is high
      if (metrics.errorRate > 0.2) {
        // Find all downstream targets
        final downstreamIds = connections
            .where((c) => c.sourceId == component.id)
            .map((c) => c.targetId)
            .toList();
        
        // Calculate retry amplification factor
        // With 20% error rate and 3 retries: 1 + 0.2 + 0.2² + 0.2³ = 1.208× traffic
        // With 50% error rate and 3 retries: 1 + 0.5 + 0.5² + 0.5³ = 1.875× traffic
        final amplification = 1 + metrics.errorRate + 
            (metrics.errorRate * metrics.errorRate) +
            (metrics.errorRate * metrics.errorRate * metrics.errorRate);
        
        if (amplification > 1.5) {
          storms.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: component.id,
            type: FailureType.retryStorm,
            message: '${component.type.displayName} retry storm: ${amplification.toStringAsFixed(2)}× traffic amplification',
            recommendation: 'Add circuit breaker to prevent retry storms, or use exponential backoff',
            severity: ((amplification - 1) / 2).clamp(0.5, 0.9),
            affectedComponents: downstreamIds,
            userVisible: true,
            fixType: FixType.addCircuitBreaker,
          ));
        }
      }
    }
  }
  
  return storms;
}
