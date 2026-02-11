import 'dart:math';
import 'dart:ui'; // Needed for Offset
import '../models/component.dart';
import '../models/connection.dart';
import '../models/metrics.dart';
import '../models/problem.dart';
import '../utils/cost_model.dart';

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

const Map<String, Map<String, double>> _regionLatencyMatrixMs = {
  'us-east-1': {
    'us-west-2': 70,
    'eu-west-1': 80,
    'eu-central-1': 95,
    'ap-south-1': 210,
    'ap-northeast-1': 170,
    'ap-southeast-1': 200,
    'sa-east-1': 120,
  },
  'us-west-2': {
    'eu-west-1': 130,
    'eu-central-1': 150,
    'ap-south-1': 220,
    'ap-northeast-1': 140,
    'ap-southeast-1': 160,
    'sa-east-1': 180,
  },
  'eu-west-1': {
    'eu-central-1': 25,
    'ap-south-1': 160,
    'ap-northeast-1': 210,
    'ap-southeast-1': 220,
    'sa-east-1': 190,
  },
  'eu-central-1': {
    'ap-south-1': 170,
    'ap-northeast-1': 220,
    'ap-southeast-1': 230,
    'sa-east-1': 200,
  },
  'ap-south-1': {
    'ap-northeast-1': 120,
    'ap-southeast-1': 80,
    'sa-east-1': 250,
  },
  'ap-northeast-1': {
    'ap-southeast-1': 110,
    'sa-east-1': 260,
  },
  'ap-southeast-1': {
    'sa-east-1': 270,
  },
};

const Map<String, String> _regionGroups = {
  'us-east-1': 'na',
  'us-west-2': 'na',
  'eu-west-1': 'eu',
  'eu-central-1': 'eu',
  'ap-south-1': 'ap',
  'ap-northeast-1': 'ap',
  'ap-southeast-1': 'ap',
  'sa-east-1': 'sa',
};

String _normalizeRegion(String? region) {
  if (region == null || region.isEmpty) return 'us-east-1';
  return region;
}

double _baseRegionLatencyMs(String from, String to) {
  final source = _normalizeRegion(from);
  final target = _normalizeRegion(to);
  if (source == target) return 4.0;
  final direct = _regionLatencyMatrixMs[source]?[target] ??
      _regionLatencyMatrixMs[target]?[source];
  if (direct != null) return direct;
  final sourceGroup = _regionGroups[source];
  final targetGroup = _regionGroups[target];
  if (sourceGroup != null && targetGroup != null) {
    if (sourceGroup == targetGroup) return 45.0;
    final pair = {sourceGroup, targetGroup};
    if (pair.contains('na') && pair.contains('eu')) return 95.0;
    if (pair.contains('na') && pair.contains('sa')) return 140.0;
    if (pair.contains('eu') && pair.contains('ap')) return 180.0;
    if (pair.contains('na') && pair.contains('ap')) return 190.0;
  }
  return 140.0;
}

String _pickRegionForComponent(SystemComponent component, String currentRegion) {
  final regions = component.config.regions;
  final normalized = _normalizeRegion(currentRegion);
  if (regions.isEmpty) return normalized;
  if (regions.contains(normalized)) return normalized;
  var best = regions.first;
  var bestLatency = _baseRegionLatencyMs(normalized, best);
  for (final region in regions.skip(1)) {
    final latency = _baseRegionLatencyMs(normalized, region);
    if (latency < bestLatency) {
      bestLatency = latency;
      best = region;
    }
  }
  return best;
}

double _chaosSeverity(ChaosEvent event) {
  final raw = event.parameters['severity'];
  if (raw is num) {
    return raw.toDouble().clamp(0.0, 1.0);
  }
  return 1.0;
}

double _chaosIntensity(ChaosEvent event) {
  final severity = _chaosSeverity(event);
  if (event.duration.inMilliseconds <= 0) return severity;
  if (event.type == ChaosType.componentCrash ||
      event.type == ChaosType.networkPartition) {
    return severity;
  }
  final p = event.progress.clamp(0.0, 1.0);
  // Start with immediate impact so users see feedback right away
  // ramp peaks at mid-duration but never drops to zero
  final ramp = 0.35 + 0.65 * sin(pi * p);
  return (ramp * severity).clamp(0.0, 1.0);
}

String? _eventTargetId(ChaosEvent event) {
  final target = event.parameters['targetId'] ?? event.parameters['componentId'];
  return target is String ? target : null;
}

String? _eventRegion(ChaosEvent event) {
  final region = event.parameters['region'];
  return region is String ? region : null;
}

bool _affectsComponent(ChaosEvent event, SystemComponent component) {
  final targetId = _eventTargetId(event);
  if (targetId != null) return component.id == targetId;
  final region = _eventRegion(event);
  if (region != null) {
    final componentRegion =
        component.config.regions.isNotEmpty ? component.config.regions.first : 'us-east-1';
    return componentRegion == region;
  }
  return true;
}

bool _affectsConnection(
  ChaosEvent event,
  SystemComponent source,
  SystemComponent target,
) {
  final targetId = _eventTargetId(event);
  if (targetId != null) {
    return source.id == targetId || target.id == targetId;
  }
  final region = _eventRegion(event);
  if (region != null) {
    final sourceRegion =
        source.config.regions.isNotEmpty ? source.config.regions.first : 'us-east-1';
    final targetRegion =
        target.config.regions.isNotEmpty ? target.config.regions.first : 'us-east-1';
    return sourceRegion == region || targetRegion == region;
  }
  return true;
}

Set<String> _collectDisconnectedComponents(
  List<ChaosEvent> activeChaosEvents,
  List<SystemComponent> components,
) {
  final disconnected = <String>{};
  for (final event in activeChaosEvents) {
    if (event.type != ChaosType.networkPartition) continue;
    if (_chaosIntensity(event) <= 0) continue;
    for (final component in components) {
      if (_affectsComponent(event, component)) {
        disconnected.add(component.id);
      }
    }
  }
  return disconnected;
}

class _Token {
  final double weight; // How many real requests this token represents
  final double arrivedAt; // Arrival time at current component (seconds)
  final String? callerId; // Upstream component that sent this token
  final int retryCount;
  final int clientId; // Stable-ish key for hashing-based routing
  final int keyId; // Key for shard/hot-key routing
  final String region; // Client region hint
  final bool isWrite;
  final bool requiresAuth;
  final bool featureEnabled;
  final bool isPremium;
  final bool isCanary;
  final bool isHotKey;

  const _Token({
    required this.weight,
    required this.arrivedAt,
    required this.clientId,
    required this.keyId,
    required this.region,
    required this.isWrite,
    required this.requiresAuth,
    required this.featureEnabled,
    required this.isPremium,
    required this.isCanary,
    required this.isHotKey,
    this.callerId,
    this.retryCount = 0,
  });

  _Token copyWith({
    double? arrivedAt,
    String? callerId,
    int? retryCount,
    String? region,
    bool? isWrite,
    bool? requiresAuth,
    bool? featureEnabled,
    bool? isPremium,
    bool? isCanary,
    bool? isHotKey,
  }) {
    return _Token(
      weight: weight,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      clientId: clientId,
      keyId: keyId,
      region: region ?? this.region,
      isWrite: isWrite ?? this.isWrite,
      requiresAuth: requiresAuth ?? this.requiresAuth,
      featureEnabled: featureEnabled ?? this.featureEnabled,
      isPremium: isPremium ?? this.isPremium,
      isCanary: isCanary ?? this.isCanary,
      isHotKey: isHotKey ?? this.isHotKey,
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
  int writeArrivals = 0;
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
      final mult = (event.parameters['multiplier'] as num?)?.toDouble() ?? 4.0;
      final intensity = _chaosIntensity(event);
      chaosMultiplier *= 1.0 + ((mult - 1.0) * intensity);
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
    data.activeChaosEvents,
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

  final chaosFailures = _buildChaosFailures(
    components,
    data.activeChaosEvents,
  );
  
  // Check for network partitions (rare but impactful)
  final networkFailure = _simulateNetworkPartition(components, data.tickCount, random);

  // Combine all failures
  final allFailures = [
    ...failures,
    ...consistencyIssues,
    ...cascadingFailures,
    ...retryStorms,
    ...chaosFailures,
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

  _AutoscaleState computeAutoscaleState(
    SystemComponent component,
    double estimatedRps,
    ComponentMetrics? prev,
  ) {
    final config = component.config;
    final minInstances = config.autoScale ? max(1, config.minInstances) : max(1, config.instances);

    var currentInstances = prev?.readyInstances ?? config.instances;
    currentInstances = max(minInstances, currentInstances);

    var targetInstances = currentInstances;
    var readyInstances = currentInstances;
    var coldStartingInstances = 0;
    var isScaling = false;

    final baseCapacity = config.capacity * max(1, currentInstances);
    final load = baseCapacity > 0 ? (estimatedRps / baseCapacity) : 1.0;

    if (config.autoScale) {
      if (load > 0.7) {
        targetInstances = (currentInstances * 1.5)
            .ceil()
            .clamp(minInstances, config.maxInstances);
      } else if (load < 0.35) {
        targetInstances = (currentInstances * 0.7)
            .floor()
            .clamp(minInstances, config.maxInstances);
      }
    }

    if (targetInstances > currentInstances) {
      isScaling = true;
      coldStartingInstances = targetInstances - currentInstances;
      // Cold instances are half capacity initially
      final warmGain = (coldStartingInstances * 0.5).ceil();
      readyInstances = currentInstances;
      final effectiveInstances = readyInstances + warmGain;
      return _AutoscaleState(
        effectiveInstances: effectiveInstances,
        isScaling: isScaling,
        targetInstances: targetInstances,
        readyInstances: readyInstances,
        coldStartingInstances: coldStartingInstances,
      );
    }

    if (targetInstances < currentInstances) {
      isScaling = true;
      readyInstances = targetInstances;
      return _AutoscaleState(
        effectiveInstances: targetInstances,
        isScaling: isScaling,
        targetInstances: targetInstances,
        readyInstances: readyInstances,
        coldStartingInstances: 0,
      );
    }

    return _AutoscaleState(
      effectiveInstances: currentInstances,
      isScaling: false,
      targetInstances: currentInstances,
      readyInstances: currentInstances,
      coldStartingInstances: 0,
    );
  }

  double sampleServiceTimeMs(_SimComponentState state, _Token token) {
    var mean = max(state.baseLatencyMs, 1.0);
    final prevCpu = state.prevMetrics?.cpuUsage ?? 0.0;
    final contention = 1.0 + (prevCpu * 0.6);
    final pressure = state.utilization;
    final pressureFactor = pressure > 0.7 ? 1.0 + (pressure - 0.7) * 2.0 : 1.0;
    mean *= contention * pressureFactor * state.slownessFactor;

    // Chaos: DB slowdown
    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.databaseSlowdown &&
          _isDatabaseLike(state.component.type) &&
          _affectsComponent(event, state.component)) {
        final mult = (event.parameters['multiplier'] as num?)?.toDouble() ?? 6.0;
        final intensity = _chaosIntensity(event);
        mean *= 1.0 + ((mult - 1.0) * intensity);
      }
      if (event.type == ChaosType.cacheMissStorm &&
          _isDatabaseLike(state.component.type) &&
          _affectsComponent(event, state.component)) {
        final drop = (event.parameters['hitRateDrop'] as num?)?.toDouble() ?? 0.9;
        final intensity = _chaosIntensity(event);
        mean *= 1.0 + (drop * 2.0 * intensity);
      }
    }

    if (_isDatabaseLike(state.component.type)) {
      final component = state.component;
      final config = component.config;
      final localRegion = _pickRegionForComponent(component, token.region);
      final replicaRegions = config.regions.where((r) => r != localRegion).toList();
      final latencies =
          replicaRegions.map((r) => _baseRegionLatencyMs(localRegion, r)).toList()
            ..sort();

      final isWrite = token.isWrite;
      final requiredQuorum =
          isWrite ? (config.quorumWrite ?? 1) : (config.quorumRead ?? 1);
      if (requiredQuorum > 1) {
        final remoteNeeded = max(0, requiredQuorum - 1);
        double quorumLatency = 0.0;
        if (remoteNeeded > 0) {
          if (latencies.isNotEmpty) {
            final index = min(remoteNeeded - 1, latencies.length - 1);
            quorumLatency = latencies[index];
          } else {
            quorumLatency = _baseRegionLatencyMs(localRegion, localRegion);
          }
        }
        final quorumFactor = isWrite ? 0.7 : 0.5;
        mean += quorumLatency * quorumFactor;
      }

      if (isWrite &&
          config.replication &&
          config.replicationFactor > 1 &&
          config.replicationType != ReplicationType.none) {
        final factor = max(1, config.replicationFactor - 1);
        final maxLatency = latencies.isNotEmpty ? latencies.last : 4.0;
        final avgLatency = latencies.isNotEmpty
            ? latencies.reduce((a, b) => a + b) / latencies.length
            : 4.0;
        final strategy = (config.replicationStrategy ?? '').toLowerCase();
        double replicationPenalty = 0.0;
        switch (config.replicationType) {
          case ReplicationType.synchronous:
            replicationPenalty = (maxLatency * 0.6) + (2.0 * factor);
            break;
          case ReplicationType.streaming:
            replicationPenalty = (avgLatency * 0.35) + (1.5 * min(3, factor));
            break;
          case ReplicationType.asynchronous:
            replicationPenalty = (avgLatency * 0.15) + (0.5 * min(2, factor));
            break;
          case ReplicationType.none:
            replicationPenalty = 0.0;
            break;
        }
        if (strategy.contains('leaderless')) {
          replicationPenalty *= 1.2;
        } else if (strategy.contains('multi')) {
          replicationPenalty *= 1.1;
        }
        mean += replicationPenalty;
      }
    }

    final sigma = 0.35 + (prevCpu * 0.4);
    return sampleLogNormal(mean, sigma).clamp(0.5, 60000.0);
  }

  double sampleNetworkLatencyMs(
    SystemComponent source,
    SystemComponent target,
    String sourceRegion,
    String targetRegion,
  ) {
    final normalizedSource = _normalizeRegion(sourceRegion);
    final normalizedTarget = _normalizeRegion(targetRegion);
    final sameRegion = normalizedSource == normalizedTarget;
    final baseLatency = _baseRegionLatencyMs(normalizedSource, normalizedTarget);
    var base = baseLatency +
        (sameRegion
            ? random.nextDouble() * 3.0
            : random.nextDouble() * (baseLatency * 0.25 + 6.0));

    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.networkLatency &&
          _affectsConnection(event, source, target)) {
        final latencyMs = (event.parameters['latencyMs'] as num?)?.toDouble() ?? 300.0;
        base += latencyMs * _chaosIntensity(event);
      }
    }

    final jitter = base * (0.08 + random.nextDouble() * 0.25);
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

    final autoscale = computeAutoscaleState(component, estimatedRps.toDouble(), prev);
    final effectiveInstances = max(1, autoscale.effectiveInstances);

    bool isCrashed = false;
    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.componentCrash) {
        final targetId = _eventTargetId(event);
        final intensity = _chaosIntensity(event);
        if (intensity <= 0) continue;
        if (targetId != null) {
          if (component.id == targetId) {
            isCrashed = true;
          }
        } else {
          if (random.nextDouble() < (0.15 * intensity)) {
            isCrashed = true;
          }
        }
      }
    }

    final hadTraffic = estimatedRps > 0 || (prev?.currentRps ?? 0) > 0;
    final isSlow = hadTraffic && random.nextDouble() < 0.02;
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

  final disconnected = _collectDisconnectedComponents(activeChaosEvents, components);

  final rrCursor = <String, int>{};

  int hashIndex(int hash, int length) {
    if (length <= 0) return 0;
    final mod = hash % length;
    return mod < 0 ? mod + length : mod;
  }

  List<Connection> filterHealthyTargets(List<Connection> candidates) {
    if (candidates.isEmpty) return candidates;
    final healthy = <Connection>[];
    for (final conn in candidates) {
      if (disconnected.contains(conn.targetId)) continue;
      final targetState = states[conn.targetId];
      if (targetState == null) continue;
      if (targetState.isCrashed || targetState.circuitOpen) continue;
      healthy.add(conn);
    }
    return healthy.isNotEmpty ? healthy : candidates;
  }

  List<Connection> buildWeightedRoundRobinList(List<Connection> candidates) {
    if (candidates.length <= 1) return candidates;
    final weights = <double>[];
    for (final conn in candidates) {
      final targetState = states[conn.targetId];
      final capacity = targetState == null
          ? 1.0
          : (targetState.capacityPerInstance *
                  targetState.autoscale.effectiveInstances)
              .toDouble();
      weights.add(max(1.0, capacity));
    }
    final minWeight = weights.reduce(min).clamp(1.0, double.infinity);
    const maxSlotsPerTarget = 10;
    final list = <Connection>[];
    for (int i = 0; i < candidates.length; i++) {
      final ratio = (weights[i] / minWeight);
      final slots = ratio.isFinite
          ? ratio.round().clamp(1, maxSlotsPerTarget)
          : 1;
      for (int j = 0; j < slots; j++) {
        list.add(candidates[i]);
      }
    }
    return list.isNotEmpty ? list : candidates;
  }

  final labelById = <String, String>{
    for (final component in components)
      component.id: (component.customName ?? component.type.displayName).toLowerCase(),
  };

  bool labelHasAny(String label, List<String> tags) {
    for (final tag in tags) {
      if (label.contains(tag)) return true;
    }
    return false;
  }

  bool isAuthTarget(String label) =>
      labelHasAny(label, ['auth', 'login', 'identity', 'oauth', 'sso']);
  bool isFeatureTarget(String label) =>
      labelHasAny(label, ['feature', 'exp', 'experiment', 'variant', 'beta']);
  bool isCanaryTarget(String label) => label.contains('canary');
  bool isBlueTarget(String label) => label.contains('blue');
  bool isGreenTarget(String label) => label.contains('green');
  bool isPremiumTarget(String label) =>
      labelHasAny(label, ['premium', 'gold', 'pro', 'enterprise', 'paid']);
  bool isStandardTarget(String label) =>
      labelHasAny(label, ['free', 'standard', 'basic', 'community']);
  bool isBatchTarget(String label) => labelHasAny(label, ['batch', 'offline', 'bulk']);
  bool isFallbackTarget(String label) =>
      labelHasAny(label, ['fallback', 'degraded', 'backup']);
  bool isHotTarget(String label) => labelHasAny(label, ['hot', 'hotspot', 'hot-shard']);
  bool isL1Cache(String label) => labelHasAny(label, ['l1', 'tier1', 'edge']);
  bool isL2Cache(String label) => labelHasAny(label, ['l2', 'tier2']);
  bool isReplicaTarget(SystemComponent component, String label) =>
      component.type == ComponentType.replicaNode ||
      labelHasAny(label, ['replica', 'read']);
  bool isPrimaryTarget(String label) =>
      labelHasAny(label, ['primary', 'leader', 'master', 'write']);
  bool isStatefulTarget(SystemComponent component, String label) =>
      labelHasAny(label, ['stateful', 'session']) ||
      component.type == ComponentType.cache ||
      _isDatabaseLike(component.type);
  bool isOriginTarget(SystemComponent component) =>
      _isServiceLike(component.type) ||
      component.type == ComponentType.apiGateway ||
      component.type == ComponentType.objectStore ||
      component.type == ComponentType.dataLake ||
      component.type == ComponentType.serverless ||
      component.type == ComponentType.worker;

  Connection pickByAdaptiveScore(
    SystemComponent source,
    List<Connection> candidates,
    _Token token,
  ) {
    final shuffled = candidates.toList()..shuffle(random);
    final utilList = <double>[];
    final latencyList = <double>[];
    final costList = <double>[];

    for (final conn in shuffled) {
      final targetState = states[conn.targetId];
      final util = targetState?.utilization ?? 0.0;
      final prev = targetState?.prevMetrics;
      final latency = (prev?.p95LatencyMs ?? prev?.latencyMs ?? _getBaseLatency(targetState?.component.type ?? ComponentType.appServer)).toDouble();
      final cost = targetState?.component.config.costPerHour ?? 0.1;
      utilList.add(util);
      latencyList.add(latency);
      costList.add(cost);
    }

    final maxUtil = utilList.isNotEmpty ? utilList.reduce(max) : 1.0;
    final maxLatency = latencyList.isNotEmpty ? latencyList.reduce(max) : 1.0;
    final maxCost = costList.isNotEmpty ? costList.reduce(max) : 1.0;

    final sourceUtil = states[source.id]?.utilization ?? 0.0;
    final costWeight = sourceUtil < 0.6 ? 0.2 : 0.1;
    final latencyWeight = sourceUtil > 0.8 ? 0.45 : 0.35;
    final utilWeight = 1.0 - costWeight - latencyWeight;

    double bestScore = double.infinity;
    Connection best = shuffled.first;
    for (int i = 0; i < shuffled.length; i++) {
      final conn = shuffled[i];
      final targetState = states[conn.targetId];
      final util = maxUtil > 0 ? utilList[i] / maxUtil : 0.0;
      final latency = maxLatency > 0 ? latencyList[i] / maxLatency : 0.0;
      final cost = maxCost > 0 ? costList[i] / maxCost : 0.0;
      final label = labelById[conn.targetId] ?? '';
      final targetRegions = targetState?.component.config.regions ?? const ['us-east-1'];
      final regionPenalty = targetRegions.contains(token.region) ? 0.0 : 0.15;
      final errorPenalty = (targetState?.prevMetrics?.errorRate ?? 0.0) > 0.2 ? 0.2 : 0.0;
      final statefulPenalty = isStatefulTarget(targetState?.component ?? source, label) && !token.requiresAuth ? 0.0 : 0.0;
      final score = util * utilWeight + latency * latencyWeight + cost * costWeight + regionPenalty + errorPenalty + statefulPenalty;
      if (score < bestScore) {
        bestScore = score;
        best = conn;
      }
    }
    return best;
  }

  Connection selectTargetConnection({
    required SystemComponent source,
    required List<Connection> candidates,
    required _Token token,
  }) {
    var viable = filterHealthyTargets(candidates);
    if (viable.length == 1) return viable.first;

    final sourceLabel = labelById[source.id] ?? source.type.displayName.toLowerCase();

    final featureTargets = <Connection>[];
    final canaryTargets = <Connection>[];
    final authTargets = <Connection>[];
    final blueTargets = <Connection>[];
    final greenTargets = <Connection>[];
    final premiumTargets = <Connection>[];
    final standardTargets = <Connection>[];
    final batchTargets = <Connection>[];
    final fallbackTargets = <Connection>[];
    final hotTargets = <Connection>[];
    final cacheTargets = <Connection>[];
    final cacheL1Targets = <Connection>[];
    final cacheL2Targets = <Connection>[];
    final dbTargets = <Connection>[];
    final dbReplicaTargets = <Connection>[];
    final dbPrimaryTargets = <Connection>[];
    final cdnTargets = <Connection>[];
    final originTargets = <Connection>[];
    final queueTargets = <Connection>[];
    final shardTargets = <Connection>[];

    for (final conn in viable) {
      final targetState = states[conn.targetId];
      final targetComponent = targetState?.component;
      final label = labelById[conn.targetId] ?? '';

      if (isFeatureTarget(label)) featureTargets.add(conn);
      if (isCanaryTarget(label)) canaryTargets.add(conn);
      if (isAuthTarget(label)) authTargets.add(conn);
      if (isBlueTarget(label)) blueTargets.add(conn);
      if (isGreenTarget(label)) greenTargets.add(conn);
      if (isPremiumTarget(label)) premiumTargets.add(conn);
      if (isStandardTarget(label)) standardTargets.add(conn);
      if (isBatchTarget(label)) batchTargets.add(conn);
      if (isFallbackTarget(label)) fallbackTargets.add(conn);
      if (isHotTarget(label)) hotTargets.add(conn);

      if (targetComponent?.type == ComponentType.cache) {
        cacheTargets.add(conn);
        if (isL1Cache(label)) cacheL1Targets.add(conn);
        if (isL2Cache(label)) cacheL2Targets.add(conn);
      }
      if (targetComponent != null && _isDatabaseLike(targetComponent.type)) {
        dbTargets.add(conn);
        if (isReplicaTarget(targetComponent!, label)) {
          dbReplicaTargets.add(conn);
        } else if (isPrimaryTarget(label)) {
          dbPrimaryTargets.add(conn);
        }
      }
      if (targetComponent?.type == ComponentType.cdn) {
        cdnTargets.add(conn);
      }
      if (targetComponent != null && isOriginTarget(targetComponent)) {
        originTargets.add(conn);
      }
      if (targetComponent?.type == ComponentType.queue) {
        queueTargets.add(conn);
      }
      if (targetComponent?.type == ComponentType.shardNode ||
          targetComponent?.type == ComponentType.partitionNode ||
          labelHasAny(label, ['shard', 'partition'])) {
        shardTargets.add(conn);
      }
    }

    // Feature flag routing
    if (featureTargets.isNotEmpty) {
      if (token.featureEnabled) {
        viable = featureTargets;
      } else {
        viable = viable.where((c) => !featureTargets.contains(c)).toList();
        if (viable.isEmpty) viable = featureTargets;
      }
    }

    // SLA tier routing
    if (premiumTargets.isNotEmpty || standardTargets.isNotEmpty) {
      if (token.isPremium && premiumTargets.isNotEmpty) {
        viable = premiumTargets;
      } else if (!token.isPremium && standardTargets.isNotEmpty) {
        viable = standardTargets;
      }
    }

    // Canary deployments
    if (canaryTargets.isNotEmpty) {
      if (token.isCanary) {
        viable = canaryTargets;
      } else {
        viable = viable.where((c) => !canaryTargets.contains(c)).toList();
        if (viable.isEmpty) viable = canaryTargets;
      }
    }

    // Blue/Green deployment
    if (blueTargets.isNotEmpty && greenTargets.isNotEmpty) {
      bool greenActive = false;
      final greenActiveTag = greenTargets.any((c) => (labelById[c.targetId] ?? '').contains('active'));
      final blueActiveTag = blueTargets.any((c) => (labelById[c.targetId] ?? '').contains('active'));
      if (greenActiveTag && !blueActiveTag) {
        greenActive = true;
      } else if (!greenActiveTag && blueActiveTag) {
        greenActive = false;
      } else {
        final greenErr = greenTargets
            .map((c) => states[c.targetId]?.prevMetrics?.errorRate ?? 0.0)
            .fold(0.0, (a, b) => a + b);
        final blueErr = blueTargets
            .map((c) => states[c.targetId]?.prevMetrics?.errorRate ?? 0.0)
            .fold(0.0, (a, b) => a + b);
        greenActive = greenErr <= blueErr;
      }
      viable = greenActive ? greenTargets : blueTargets;
    }

    // Auth gating: only some traffic hits auth services
    if (authTargets.isNotEmpty &&
        viable.length > 1 &&
        (source.type == ComponentType.apiGateway || sourceLabel.contains('gateway'))) {
      if (token.requiresAuth) {
        viable = authTargets;
      } else {
        viable = viable.where((c) => !authTargets.contains(c)).toList();
        if (viable.isEmpty) viable = authTargets;
      }
    }

    // Region preference
    if (token.region.isNotEmpty) {
      final regional = viable.where((c) {
        final targetRegions = states[c.targetId]?.component.config.regions ?? const ['us-east-1'];
        return targetRegions.contains(token.region);
      }).toList();
      if (regional.isNotEmpty) viable = regional;
    }

    // Shard routing (hash-based)
    if (shardTargets.isNotEmpty && (source.config.sharding || shardTargets.length > 1)) {
      final stable = shardTargets.toList()
        ..sort((a, b) => a.targetId.compareTo(b.targetId));
      final idx = hashIndex(Object.hash(token.keyId, source.id), stable.length);
      return stable[idx];
    }

    // Read/write split for DB replicas
    if (dbTargets.isNotEmpty && dbTargets.length >= 2) {
      if (!token.isWrite && dbReplicaTargets.isNotEmpty) {
        viable = dbReplicaTargets;
      } else if (token.isWrite && dbPrimaryTargets.isNotEmpty) {
        viable = dbPrimaryTargets;
      }
    }

    // Hot-key routing
    if (token.isHotKey) {
      if (hotTargets.isNotEmpty) {
        viable = hotTargets;
      } else if (cacheTargets.isNotEmpty) {
        viable = cacheTargets;
      }
    }

    // Tiered cache preference
    if (cacheL1Targets.isNotEmpty && cacheL2Targets.isNotEmpty) {
      final l1Health = cacheL1Targets.every((c) {
        final prev = states[c.targetId]?.prevMetrics;
        return (prev?.errorRate ?? 0.0) < 0.1 && (states[c.targetId]?.utilization ?? 0.0) < 1.2;
      });
      final useL1 = l1Health ? (random.nextDouble() < 0.9) : (random.nextDouble() < 0.3);
      viable = useL1 ? cacheL1Targets : cacheL2Targets;
    }

    // Cache/DB bias (dynamic by cache hit rate)
    if (cacheTargets.isNotEmpty && dbTargets.isNotEmpty) {
      final cacheHitAvg = cacheTargets
          .map((c) => states[c.targetId]?.prevMetrics?.cacheHitRate ?? 0.85)
          .fold(0.0, (a, b) => a + b) / cacheTargets.length;
      final cacheHealthPenalty = cacheTargets.any((c) {
        final prev = states[c.targetId]?.prevMetrics;
        return (prev?.errorRate ?? 0.0) > 0.15 || (states[c.targetId]?.utilization ?? 0.0) > 1.4;
      });
      // Default: 90% of traffic to cache when both are present
      double cacheBias = cacheHealthPenalty ? 0.2 : 0.9;
      // If cache looks healthy and hit-rate is high, keep bias near 0.9; else drop toward 0.6
      cacheBias = cacheHealthPenalty
          ? cacheBias
          : max(0.6, min(0.95, cacheHitAvg + 0.05));
      if (token.isHotKey) cacheBias = min(0.99, cacheBias + 0.05);

      // If cache is invalidated by chaos, bypass it entirely
      final cacheUnavailable = cacheTargets.any((t) =>
          activeChaosEvents.any((e) =>
              e.type == ChaosType.cacheMissStorm &&
              _chaosIntensity(e) > 0.2 &&
              _affectsComponent(e, states[t.targetId]!.component)));

      if (cacheTargets.length + dbTargets.length == viable.length) {
        final useCache = !token.isWrite &&
            !cacheUnavailable &&
            (random.nextDouble() < cacheBias);
        viable = useCache ? cacheTargets : dbTargets;
      }
    }

    // CDN vs Origin bias
    if (cdnTargets.isNotEmpty && originTargets.isNotEmpty) {
      final useCdn = random.nextDouble() < 0.95;
      viable = useCdn ? cdnTargets : originTargets;
    }

    // Queue offload under overload or throttling
    if (queueTargets.isNotEmpty) {
      final nonQueueTargets = viable.where((c) => !queueTargets.contains(c)).toList();
      if (nonQueueTargets.isNotEmpty && token.isWrite) {
        final overloaded = nonQueueTargets.any((c) {
          final util = states[c.targetId]?.utilization ?? 0.0;
          final err = states[c.targetId]?.prevMetrics?.errorRate ?? 0.0;
          final throttled = states[c.targetId]?.prevMetrics?.isThrottled ?? false;
          return util > 1.1 || err > 0.2 || throttled;
        });
        final queueBias = overloaded ? 0.6 : 0.1;
        if (random.nextDouble() < queueBias) {
          viable = queueTargets;
        }
      }
    }

    // Batch path for cost efficiency
    if (batchTargets.isNotEmpty) {
      final nonBatchTargets = viable.where((c) => !batchTargets.contains(c)).toList();
      if (nonBatchTargets.isNotEmpty && token.isWrite) {
        final sourceLoad = states[source.id]?.utilization ?? 0.0;
        final batchBias = sourceLoad < 0.6 ? 0.2 : 0.05;
        if (random.nextDouble() < batchBias) {
          viable = batchTargets;
        }
      }
    }

    // Rate-limit spillover to fallback
    if (fallbackTargets.isNotEmpty) {
      final throttledTargets = viable.where((c) => states[c.targetId]?.prevMetrics?.isThrottled ?? false).toList();
      if (throttledTargets.isNotEmpty) {
        if (random.nextDouble() < 0.6) {
          viable = fallbackTargets;
        }
      }
    }

    if (viable.length == 1) return viable.first;

    var algorithm = source.config.algorithm?.toLowerCase();
    final hasStateful = viable.any((c) {
      final targetState = states[c.targetId];
      final label = labelById[c.targetId] ?? '';
      return isStatefulTarget(targetState?.component ?? source, label);
    });
    if (algorithm == null && (source.config.consistentHashing || hasStateful)) {
      algorithm = 'ip_hash';
    }
    if (algorithm == null && source.type == ComponentType.loadBalancer) {
      algorithm = 'round_robin';
    }
    algorithm ??= 'adaptive';

    switch (algorithm) {
      case 'round_robin':
        final rrList = buildWeightedRoundRobinList(viable);
        final idx = rrCursor[source.id] ?? 0;
        rrCursor[source.id] = (idx + 1) % rrList.length;
        return rrList[idx % rrList.length];
      case 'ip_hash':
      case 'consistent_hashing':
        final stable = viable.toList()
          ..sort((a, b) => a.targetId.compareTo(b.targetId));
        final hash = Object.hash(token.clientId, source.id);
        final idx = hashIndex(hash, stable.length);
        return stable[idx];
      case 'least_conn':
        final shuffled = viable.toList()..shuffle(random);
        shuffled.sort((a, b) {
          final aUtil = states[a.targetId]?.utilization ?? 0.0;
          final bUtil = states[b.targetId]?.utilization ?? 0.0;
          return aUtil.compareTo(bUtil);
        });
        return shuffled.first;
      case 'adaptive':
      default:
        return pickByAdaptiveScore(source, viable, token);
    }
  }

  final configuredRegions = <String>{
    ...problem.constraints.regions,
    ...components.expand((c) => c.config.regions),
  }.where((r) => r.isNotEmpty).toList();
  final regionPool = configuredRegions.isNotEmpty
      ? configuredRegions
      : const ['us-east-1', 'us-west-2', 'eu-central-1', 'ap-southeast-1'];

  final readRatio = max(0.0, problem.constraints.readWriteRatio);
  final readProbability = readRatio / (readRatio + 1.0);

  // Event-driven simulation
  final events = _MinHeap();
  final clientPool = max(50, min(5000, sampleCount));
  for (int i = 0; i < sampleCount; i++) {
    final entry = effectiveEntryPoints[random.nextInt(entryCount)];
    final time = random.nextDouble() * simWindowSeconds;
    final clientId = random.nextInt(clientPool);
    final keyId = Object.hash(clientId, i, random.nextInt(1 << 16));
    final isWrite = random.nextDouble() > readProbability;
    final requiresAuth = isWrite ? (random.nextDouble() < 0.7) : (random.nextDouble() < 0.2);
    final featureEnabled = random.nextDouble() < 0.1;
    final isPremium = random.nextDouble() < 0.1;
    final isCanary = random.nextDouble() < 0.05;
    final isHotKey = random.nextDouble() < 0.02;
    final clientRegion = regionPool[random.nextInt(regionPool.length)];
    final entryRegion = _pickRegionForComponent(entry, clientRegion);
    events.add(_Event(
      time: time,
      type: _EventType.arrival,
      componentId: entry.id,
      token: _Token(
        weight: tokenWeight,
        arrivedAt: time,
        clientId: clientId,
        keyId: keyId,
        region: entryRegion,
        isWrite: isWrite,
        requiresAuth: requiresAuth,
        featureEnabled: featureEnabled,
        isPremium: isPremium,
        isCanary: isCanary,
        isHotKey: isHotKey,
      ),
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
    final serviceMs = sampleServiceTimeMs(state, token);
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
    final callerState = states[token.callerId!];
    final caller = callerState?.component;
    if (caller == null || !caller.config.retries) return;

    // Retry storm control: dampen retries under high error or pressure
    final errorRate = callerState?.prevMetrics?.errorRate ?? 0.0;
    final utilization = callerState?.utilization ?? 0.0;
    var retryChance = 1.0;
    if (errorRate > 0.2) {
      retryChance *= max(0.2, 1.0 - errorRate);
    }
    if (utilization > 1.2) {
      retryChance *= 0.5;
    }
    if (callerState != null &&
        callerState.queue.length > callerState.maxQueueTokens * 0.8) {
      retryChance *= 0.5;
    }
    if (token.retryCount >= 1) {
      retryChance *= 0.7;
    }
    if (random.nextDouble() > retryChance) return;
    final backoffMs = 50.0 * pow(2, token.retryCount).toDouble();
    final jitterMs = backoffMs * (0.2 + random.nextDouble() * 0.4);
    final targetState = states[targetComponentId];
    final targetRegion = targetState != null
        ? _pickRegionForComponent(targetState.component, token.region)
        : token.region;
    scheduleArrival(
      time: time + ((backoffMs + jitterMs) / 1000.0),
      componentId: targetComponentId,
      token: token.copyWith(
        retryCount: token.retryCount + 1,
        region: targetRegion,
      ),
    );
  }

  while (events.isNotEmpty) {
    final event = events.pop();
    if (event.time > simWindowSeconds) break;
    final state = states[event.componentId];
    if (state == null) continue;
    final resolvedRegion = _pickRegionForComponent(state.component, event.token.region);
    final token = resolvedRegion == event.token.region
        ? event.token
        : event.token.copyWith(region: resolvedRegion);

    if (event.type == _EventType.arrival) {
      state.arrivals += 1;
      if (token.isWrite) state.writeArrivals += 1;

      if (disconnected.contains(state.component.id)) {
        state.errors += 1;
        maybeRetry(
          token: token,
          targetComponentId: state.component.id,
          time: event.time,
        );
        continue;
      }

      // Circuit breaker / crash handling
      if (state.circuitOpen || state.isCrashed) {
        state.errors += 1;
        maybeRetry(
          token: token,
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
        startService(state, event.time, token);
      } else {
        state.queue.add(token);
      }
    } else {
      // Completion
      if (state.inService > 0) state.inService -= 1;
      state.processed += 1;
      final latencyMs = (event.time - token.arrivedAt) * 1000.0;
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

      // Enforce quorum requirements for database-like components
      if (_isDatabaseLike(state.component.type)) {
        final config = state.component.config;
        final requiredQuorum =
            token.isWrite ? (config.quorumWrite ?? 1) : (config.quorumRead ?? 1);
        if (requiredQuorum > 1) {
          int availableReplicas = config.replication && config.replicationFactor > 0
              ? config.replicationFactor
              : 1;
          if (config.regions.isNotEmpty) {
            availableReplicas = min(availableReplicas, config.regions.length);
          }
          final partitioned = activeChaosEvents.any((event) =>
              event.type == ChaosType.networkPartition &&
              _chaosIntensity(event) > 0 &&
              _affectsComponent(event, state.component));
          if (partitioned && availableReplicas > 1) {
            availableReplicas = max(1, (availableReplicas * 0.6).floor());
          }
          if (requiredQuorum > availableReplicas) {
            state.errors += 1;
            maybeRetry(
              token: token,
              targetComponentId: state.component.id,
              time: event.time,
            );
            continue;
          }
        }
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
          token: token,
          targetComponentId: state.component.id,
          time: event.time,
        );
        continue;
      }

      // Route to downstream components
      final outgoingConns = outgoing[state.component.id] ?? [];
      if (outgoingConns.isEmpty) continue;

      final isFanoutComponent = state.component.type == ComponentType.pubsub ||
          state.component.type == ComponentType.stream;

      final fanoutTargets = <Connection>[];
      final selectableTargets = <Connection>[];

      if (isFanoutComponent) {
        fanoutTargets.addAll(outgoingConns);
      } else {
        for (final conn in outgoingConns) {
          if (conn.type == ConnectionType.replication) {
            fanoutTargets.add(conn);
          } else {
            selectableTargets.add(conn);
          }
        }
      }

      if (selectableTargets.isNotEmpty) {
        final chosen = selectableTargets.length == 1
            ? selectableTargets.first
            : selectTargetConnection(
                source: state.component,
                candidates: selectableTargets,
                token: token,
              );
        fanoutTargets.add(chosen);
      }

      if (fanoutTargets.isEmpty) continue;

      var targets = filterHealthyTargets(fanoutTargets);
      if (isFanoutComponent && targets.length > 1) {
        targets = targets.toList()..shuffle(random);
      }

      final fanoutCap =
          isFanoutComponent ? min(5, targets.length) : targets.length;
      for (int i = 0; i < fanoutCap; i++) {
        final conn = targets[i];
        if (disconnected.contains(conn.targetId)) {
          state.errors += 1;
          maybeRetry(
            token: token,
            targetComponentId: conn.targetId,
            time: event.time,
          );
          continue;
        }
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
                token: token,
                targetComponentId: conn.targetId,
                time: event.time,
              );
              continue;
            }
          }
        }

        final sourceRegion = token.region;
        final targetRegion = _pickRegionForComponent(targetState.component, sourceRegion);
        final networkMs = sampleNetworkLatencyMs(
          state.component,
          targetState.component,
          sourceRegion,
          targetRegion,
        );
        final arrivalTime = event.time + ((networkMs + extraDelayMs) / 1000.0);

        connectionTrafficRps[conn.id] =
            (connectionTrafficRps[conn.id] ?? 0.0) + token.weight;

        scheduleArrival(
          time: arrivalTime,
          componentId: conn.targetId,
          connectionId: conn.id,
          token: token.copyWith(
            callerId: state.component.id,
            region: targetRegion,
          ),
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
    final highLoadSeconds = effectiveLoad >= 0.8
        ? ((prev?.highLoadSeconds ?? 0.0) + simWindowSeconds)
        : 0.0;

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
      final ttlSeconds = max(1, component.config.cacheTtlSeconds);
      final ttlFactor = (ttlSeconds / 300).clamp(0.2, 1.1);
      cacheHitRate = (cacheHitRate * ttlFactor).clamp(0.0, 1.0);

      // Global write pressure fallback (if writes don’t route through cache directly)
      final globalWriteFraction =
          1.0 / (problem.constraints.readWriteRatio.toDouble() + 1.0);
      final localWriteFraction =
          state.arrivals > 0 ? state.writeArrivals / state.arrivals : null;
      final writeFraction = localWriteFraction ?? globalWriteFraction;

      // Writes invalidate cache: higher write ratio → lower hit rate
      final invalidationPenalty = (writeFraction * 0.85).clamp(0.0, 0.8);
      cacheHitRate = (cacheHitRate * (1 - invalidationPenalty)).clamp(0.0, 1.0);

      if (memoryUsage > 0.8) {
        evictionRate = (memoryUsage - 0.8) * 5000;
      }
      if (ttlSeconds <= 30 && effectiveLoad > 0.8) {
        evictionRate += (0.3 + (0.2 * random.nextDouble())) * 1200;
      }
      for (final event in activeChaosEvents) {
        if (event.type == ChaosType.cacheMissStorm &&
            _affectsComponent(event, component)) {
          final drop = (event.parameters['hitRateDrop'] as num?)?.toDouble() ?? 0.9;
          final intensity = _chaosIntensity(event);
          cacheHitRate = (cacheHitRate * (1 - drop * intensity)).clamp(0.0, 1.0);
          evictionRate += (drop * 1200 * intensity);
        }
      }
    }

    double queueDepth = (state.queue.length + state.inService) * tokenWeight;
    queueDepth = smooth(queueDepth, prev?.queueDepth ?? 0.0, 0.2);

    double connectionPoolUtilization = 0.0;
    int activeConnections = 0;
    final maxConnections = state.autoscale.effectiveInstances * 100;
    if (_isDatabaseLike(component.type) || _isServiceLike(component.type)) {
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
      highLoadSeconds: highLoadSeconds,
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
  final highLoadSeconds = effectiveLoad >= 0.8
      ? ((prevMetrics?.highLoadSeconds ?? 0.0) + 0.1)
      : 0.0;

  // Slow node simulation (5% chance a node becomes slow) - only when traffic exists
  final hadTraffic = incomingRps > 0 || (prevMetrics?.currentRps ?? 0) > 0;
  bool isSlow = hadTraffic && random.nextDouble() < 0.05;
  double slownessFactor = isSlow ? (2.0 + random.nextDouble() * 8.0) : 1.0;

  // APPLY CHAOS: Latency & DB Slowdown
  for (final event in activeChaosEvents) {
    if (event.type == ChaosType.networkLatency) {
      // Add global latency
      if (_affectsComponent(event, component)) {
        final latencyMs = (event.parameters['latencyMs'] as num?)?.toDouble() ?? 300.0;
        slownessFactor += (latencyMs / 50.0) * _chaosIntensity(event); // Rough conversion
      }
    } else if (event.type == ChaosType.databaseSlowdown && _isDatabaseLike(component.type)) {
      if (_affectsComponent(event, component)) {
        final mult = (event.parameters['multiplier'] as num?)?.toDouble() ?? 8.0;
        slownessFactor *= 1.0 + ((mult - 1.0) * _chaosIntensity(event));
      }
    } else if (event.type == ChaosType.cacheMissStorm && _isDatabaseLike(component.type)) {
      if (_affectsComponent(event, component)) {
        final drop = (event.parameters['hitRateDrop'] as num?)?.toDouble() ?? 0.9;
        slownessFactor *= 1.0 + (drop * 2.0 * _chaosIntensity(event));
      }
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

    // Global write pressure fallback (captures invalidations even if writes bypass cache)
    final globalWriteFraction =
        1.0 / (problem.constraints.readWriteRatio.toDouble() + 1.0);
    // This fast path doesn’t track per-cache write arrivals; use global ratio.
    final writeFraction = globalWriteFraction;

    // Write-heavy traffic lowers hit rate
    final invalidationPenalty = (writeFraction * 0.85).clamp(0.0, 0.8);
    cacheHitRate = (cacheHitRate * (1 - invalidationPenalty)).clamp(0.0, 1.0);

    // Simulate evictions if memory usage is high (>80%)
    if (memoryUsage > 0.8) {
      // Eviction rate drastically increases as memory fills up
      evictionRate = (memoryUsage - 0.8) * 5000; // up to 1000+ evictions/sec
    }

    for (final event in activeChaosEvents) {
      if (event.type == ChaosType.cacheMissStorm &&
          _affectsComponent(event, component)) {
        final drop = (event.parameters['hitRateDrop'] as num?)?.toDouble() ?? 0.9;
        final intensity = _chaosIntensity(event);
        cacheHitRate = (cacheHitRate * (1 - drop * intensity)).clamp(0.0, 1.0);
        evictionRate += (drop * 1200 * intensity);
      }
    }

    // Low TTLs under write pressure should purge faster
    if (component.config.cacheTtlSeconds <= 45 && writeFraction > 0.1) {
      evictionRate += 300 * writeFraction;
      cacheHitRate = (cacheHitRate * (1 - 0.1 * writeFraction)).clamp(0.0, 1.0);
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
  
  if (_isDatabaseLike(component.type) || _isServiceLike(component.type)) {
    // Connection pool utilization tracks with load
    final targetUtil = effectiveLoad.clamp(0.0, 1.0);
    connectionPoolUtilization = (targetUtil * alpha) + (lastMetrics.connectionPoolUtilization * (1 - alpha));
    activeConnections = (maxConnections * connectionPoolUtilization).toInt();
  }

  final jitter = avgLatency * 0.1 * (1.0 + effectiveLoad);

  // TRACKING: Glow/Blast Logic
  // A component "glows" (red/orange) if it's overloaded (>90% CPU) or has high errors (>5%)
  final isGlowing = cpuUsage > 0.9 || errorRate > 0.05 || isSlow;
  
  // Increment or reset the glow counter
  int consecutiveGlowTicks = lastMetrics.consecutiveGlowTicks;
  if (isGlowing) {
    consecutiveGlowTicks++;
  } else {
    consecutiveGlowTicks = 0;
  }
  
  // BLAST CHECK: If glowing for 30 seconds (assuming 10 ticks/sec -> 300 ticks)
  // Force a crash
  bool finalIsCrashed = isCrashed;
  if (consecutiveGlowTicks >= 300 && !finalIsCrashed) {
    finalIsCrashed = true;
    consecutiveGlowTicks = 0; // Reset counter after crash
  }

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
    isCrashed: finalIsCrashed,
    consecutiveGlowTicks: consecutiveGlowTicks,
    highLoadSeconds: highLoadSeconds,
  );
}

double _getBaseLatency(ComponentType type) {
  return switch (type) {
    ComponentType.dns => 1.0,
    ComponentType.cdn => 5.0,
    ComponentType.loadBalancer => 1.0,
    ComponentType.apiGateway => 5.0,
    ComponentType.waf => 2.0,
    ComponentType.ingress => 2.0,
    ComponentType.appServer => 20.0,
    ComponentType.worker => 100.0,
    ComponentType.serverless => 50.0,
    ComponentType.authService => 15.0,
    ComponentType.notificationService => 30.0,
    ComponentType.searchService => 25.0,
    ComponentType.analyticsService => 40.0,
    ComponentType.scheduler => 80.0,
    ComponentType.serviceDiscovery => 5.0,
    ComponentType.configService => 5.0,
    ComponentType.secretsManager => 10.0,
    ComponentType.featureFlag => 8.0,
    ComponentType.llmGateway => 25.0,
    ComponentType.toolRegistry => 12.0,
    ComponentType.memoryFabric => 15.0,
    ComponentType.agentOrchestrator => 30.0,
    ComponentType.safetyMesh => 10.0,
    ComponentType.cache => 2.0,
    ComponentType.database => 10.0,
    ComponentType.objectStore => 50.0,
    ComponentType.keyValueStore => 5.0,
    ComponentType.timeSeriesDb => 15.0,
    ComponentType.graphDb => 25.0,
    ComponentType.vectorDb => 25.0,
    ComponentType.searchIndex => 20.0,
    ComponentType.dataWarehouse => 60.0,
    ComponentType.dataLake => 80.0,
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
    if (_isDatabaseLike(component.type) || component.type == ComponentType.cache) {
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
  if (component.config.instances == 1 && _isSpofCandidate(component.type) && metrics.currentRps > 0) {
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
  if (_isDatabaseLike(component.type) && !component.config.replication) {
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

  // NEW: 6b. Disk I/O Saturation (primarily stateful storage)
  if (_isDatabaseLike(component.type) && metrics.currentRps > 0) {
    final ioPressure = (metrics.queueDepth / 2000).clamp(0.0, 2.0);
    if (ioPressure > 0.9 && metrics.p95LatencyMs > 250) {
      failures.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: component.id,
        type: FailureType.diskIoSaturation,
        message: 'Disk I/O saturation - requests are queuing on storage',
        recommendation: 'Increase IOPS, add replicas, or shard hot data',
        severity: (ioPressure / 2.0).clamp(0.6, 0.9),
        userVisible: true,
        fixType: FixType.increaseReplicas,
      ));
    }
  }

  // NEW: 6c. Thread Starvation (CPU-bound services under heavy load)
  if (_isServiceLike(component.type) && metrics.currentRps > 0) {
    final pressure = metrics.cpuUsage;
    if (pressure > 0.9 && metrics.queueDepth > 1200) {
      failures.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: component.id,
        type: FailureType.threadStarvation,
        message: 'Thread starvation - all workers are busy',
        recommendation: 'Increase worker pool or add instances',
        severity: (pressure).clamp(0.6, 0.9),
        userVisible: true,
        fixType: FixType.increaseReplicas,
      ));
    }
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

  // NEW: 10. Thundering Herd (low TTL + high load causes synchronized misses)
  if (component.type == ComponentType.cache && metrics.currentRps > 0) {
    final ttlSeconds = component.config.cacheTtlSeconds;
    if (ttlSeconds <= 30 &&
        metrics.currentRps > 1500 &&
        metrics.cacheHitRate < 0.45) {
      failures.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: component.id,
        type: FailureType.thunderingHerd,
        message: 'Thundering herd: low TTL and high traffic causing synchronized cache misses',
        recommendation: 'Use request coalescing, jittered TTL, or stale-while-revalidate',
        severity: 0.7,
        userVisible: true,
        fixType: FixType.increaseReplicas,
      ));
    }
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
  final storageCount = components.where((c) => CostModel.isStorageComponentType(c.type)).length;
  final dbCount = components.where((c) => CostModel.isDatabaseComponentType(c.type)).length;

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
    totalCost += CostModel.estimateComponentHourlyCost(
      component: component,
      problem: problem,
      storageComponentCount: storageCount,
      dbComponentCount: dbCount,
      metrics: metrics,
    ).total;
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

bool _isDatabaseLike(ComponentType type) {
  return switch (type) {
    ComponentType.database ||
    ComponentType.keyValueStore ||
    ComponentType.timeSeriesDb ||
    ComponentType.graphDb ||
    ComponentType.vectorDb ||
    ComponentType.searchIndex ||
    ComponentType.dataWarehouse ||
    ComponentType.dataLake => true,
    _ => false,
  };
}

bool _isServiceLike(ComponentType type) {
  return switch (type) {
    ComponentType.appServer ||
    ComponentType.customService ||
    ComponentType.authService ||
    ComponentType.notificationService ||
    ComponentType.searchService ||
    ComponentType.analyticsService ||
    ComponentType.scheduler ||
    ComponentType.serviceDiscovery ||
    ComponentType.configService ||
    ComponentType.secretsManager ||
    ComponentType.featureFlag ||
    ComponentType.llmGateway ||
    ComponentType.toolRegistry ||
    ComponentType.memoryFabric ||
    ComponentType.agentOrchestrator ||
    ComponentType.safetyMesh => true,
    _ => false,
  };
}

bool _isCriticalPath(ComponentType type) {
  if (_isDatabaseLike(type) || _isServiceLike(type)) return true;
  return switch (type) {
    ComponentType.loadBalancer ||
    ComponentType.apiGateway ||
    ComponentType.waf ||
    ComponentType.ingress ||
    ComponentType.cache ||
    ComponentType.serverless ||
    ComponentType.llmGateway ||
    ComponentType.agentOrchestrator ||
    ComponentType.memoryFabric => true,
    _ => false,
  };
}

bool _isSpofCandidate(ComponentType type) {
  // Treat managed edge components (API Gateway, Load Balancer, CDN, DNS, Serverless)
  // as non-SPOF by default. Focus SPOF on self-managed/stateful services.
  return switch (type) {
    ComponentType.appServer ||
    ComponentType.database ||
    ComponentType.keyValueStore ||
    ComponentType.timeSeriesDb ||
    ComponentType.graphDb ||
    ComponentType.vectorDb ||
    ComponentType.searchIndex ||
    ComponentType.dataWarehouse ||
    ComponentType.dataLake ||
    ComponentType.cache ||
    ComponentType.queue ||
    ComponentType.pubsub ||
    ComponentType.stream ||
    ComponentType.worker ||
    ComponentType.customService ||
    ComponentType.authService ||
    ComponentType.notificationService ||
    ComponentType.searchService ||
    ComponentType.analyticsService ||
    ComponentType.scheduler ||
    ComponentType.serviceDiscovery ||
    ComponentType.configService ||
    ComponentType.secretsManager ||
    ComponentType.featureFlag ||
    ComponentType.llmGateway ||
    ComponentType.toolRegistry ||
    ComponentType.memoryFabric ||
    ComponentType.agentOrchestrator ||
    ComponentType.safetyMesh => true,
    ComponentType.objectStore => false,
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
  List<ChaosEvent> activeChaosEvents,
) {
  // Import consistency validator logic inline to avoid import issues in isolate
  final issues = <FailureEvent>[];
  final random = Random(tickCount);
  final hasPartition = activeChaosEvents.any(
    (event) => event.type == ChaosType.networkPartition && _chaosIntensity(event) > 0,
  );
  
  // Check database replication lag
  for (final db in components.where((c) => _isDatabaseLike(c.type))) {
    final metrics = componentMetrics[db.id];
    if (metrics == null) continue;
    final config = db.config;
    final strategy = (config.replicationStrategy ?? '').toLowerCase();
    final replicationEnabled = config.replication && config.replicationFactor > 1;
    final quorumRead = config.quorumRead ?? 1;
    final quorumWrite = config.quorumWrite ?? 1;

    int availableReplicas = replicationEnabled ? config.replicationFactor : 1;
    if (config.regions.isNotEmpty) {
      availableReplicas = min(availableReplicas, config.regions.length);
    }
    final partitioned = activeChaosEvents.any((event) =>
        event.type == ChaosType.networkPartition &&
        _chaosIntensity(event) > 0 &&
        _affectsComponent(event, db));
    final effectiveReplicas =
        partitioned ? max(1, (availableReplicas * 0.6).floor()) : availableReplicas;

    if (quorumRead > effectiveReplicas || quorumWrite > effectiveReplicas) {
      issues.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: db.id,
        type: FailureType.quorumNotMet,
        message: 'Quorum (${max(quorumRead, quorumWrite)}) exceeds available replicas ($effectiveReplicas)',
        recommendation: 'Increase replication factor or lower quorum requirements',
        severity: 0.85,
        userVisible: true,
        fixType: FixType.increaseReplicas,
      ));
    }

    if (replicationEnabled && config.replicationType != ReplicationType.none) {
      final load = metrics.cpuUsage;
      final regionPenalty = max(0, config.regions.length - 1) * 35;
      double baseLagMs;
      double loadScale;
      switch (config.replicationType) {
        case ReplicationType.synchronous:
          baseLagMs = 20;
          loadScale = 900;
          break;
        case ReplicationType.streaming:
          baseLagMs = 60;
          loadScale = 1500;
          break;
        case ReplicationType.asynchronous:
          baseLagMs = 120;
          loadScale = 2300;
          break;
        case ReplicationType.none:
          baseLagMs = 0;
          loadScale = 0;
          break;
      }

      final lagMs = (baseLagMs + (load * loadScale) + regionPenalty).toInt();
      if (lagMs > 400) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: db.id,
          type: FailureType.replicationLag,
          message: 'Replication lag ${lagMs}ms - users may see stale data',
          recommendation: 'Use read-your-writes consistency or strong reads',
          severity: (lagMs / 2200).clamp(0.3, 0.8),
          userVisible: true,
          fixType: FixType.increaseReplicas,
        ));
      }

      if (config.replicationType != ReplicationType.synchronous && lagMs > 700) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: db.id,
          type: FailureType.staleRead,
          message: 'High replication lag causing stale reads',
          recommendation: 'Route critical reads to primary or enable session consistency',
          severity: 0.6,
          userVisible: true,
        ));
      }

      if (config.replicationType == ReplicationType.asynchronous &&
          metrics.currentRps > 500 &&
          random.nextDouble() < 0.03) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: db.id,
          type: FailureType.readAfterWriteFailure,
          message: 'Read-after-write not guaranteed under async replication',
          recommendation: 'Use read-your-writes consistency or synchronous replication',
          severity: 0.7,
          userVisible: true,
        ));
      }
    }

    // Check for lost updates (leaderless without quorum)
    if (metrics.currentRps > 100) {
      final hasQuorum = config.quorumWrite != null && config.quorumWrite! > 1;
      final isLeaderless = strategy.contains('leaderless');
      if ((!hasQuorum && isLeaderless) && random.nextDouble() < 0.03) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: db.id,
          type: FailureType.lostUpdate,
          message: 'Leaderless writes without quorum can lose updates',
          recommendation: 'Enable quorum writes or add conflict resolution',
          severity: 0.8,
          userVisible: true,
        ));
      }
    }

    if (hasPartition &&
        replicationEnabled &&
        (strategy.contains('multi') || strategy.contains('leaderless'))) {
      issues.add(FailureEvent(
        timestamp: DateTime.now(),
        componentId: db.id,
        type: FailureType.networkPartition,
        message: 'Split-brain risk under network partition with multi-writer replication',
        recommendation: 'Use quorum writes, leader election, or conflict resolution',
        severity: 0.9,
        userVisible: true,
      ));
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

List<FailureEvent> _buildChaosFailures(
  List<SystemComponent> components,
  List<ChaosEvent> activeChaosEvents,
) {
  final failures = <FailureEvent>[];

  for (final event in activeChaosEvents) {
    final intensity = _chaosIntensity(event);
    if (intensity <= 0) continue;

    if (event.type == ChaosType.networkPartition ||
        event.type == ChaosType.networkLatency) {
      final affectedComponents = components
          .where((c) => _affectsComponent(event, c))
          .where((c) =>
              c.type != ComponentType.rectangle &&
              c.type != ComponentType.circle &&
              c.type != ComponentType.diamond &&
              c.type != ComponentType.arrow &&
              c.type != ComponentType.line)
          .toList();

      if (affectedComponents.isEmpty) continue;

      final affectedIds = affectedComponents.map((c) => c.id).toList();
      final targetId = _eventTargetId(event);
      final region = _eventRegion(event);
      String scope = 'network';
      if (targetId != null) {
        final targetName = components
            .firstWhere((c) => c.id == targetId, orElse: () => components.first)
            .type
            .displayName;
        scope = '$targetName';
      } else if (region != null) {
        scope = region;
      }

      if (event.type == ChaosType.networkPartition) {
        for (final component in affectedComponents) {
          failures.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: component.id,
            type: FailureType.networkPartition,
            message: 'Network partition: $scope isolated',
            recommendation: 'Enable multi-region failover, retries, and circuit breakers',
            severity: 0.9,
            affectedComponents: affectedIds,
            expectedRecoveryTime: event.duration,
            userVisible: true,
          ));
        }
      } else if (event.type == ChaosType.networkLatency) {
        final latencyMs =
            (event.parameters['latencyMs'] as num?)?.toDouble() ?? 300.0;
        final addedMs = (latencyMs * intensity).round();
        if (addedMs <= 0) continue;
        final severity = (0.4 + (addedMs / 1000.0)).clamp(0.4, 0.9);

        for (final component in affectedComponents) {
          failures.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: component.id,
            type: FailureType.latencyBreach,
            message: 'Network lag +${addedMs}ms (${scope})',
            recommendation:
                'Co-locate services, reduce cross-region calls, add caching/edge, and tune timeouts',
            severity: severity,
            affectedComponents: affectedIds,
            expectedRecoveryTime: event.duration,
            userVisible: true,
          ));
        }
      }
    }
  }

  return failures;
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
