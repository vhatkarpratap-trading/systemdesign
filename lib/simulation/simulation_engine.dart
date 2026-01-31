import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/metrics.dart';
import '../models/score.dart';
import '../models/component.dart';
import '../models/connection.dart';
import '../models/problem.dart';
import '../models/canvas_state.dart';
import '../providers/game_provider.dart';
import 'design_validator.dart';
import 'simulation_isolate.dart';

/// Core simulation engine that runs the system design simulation
class SimulationEngine {
  final Ref _ref;
  Timer? _simulationTimer;
  bool _isProcessingTick = false;

  SimulationEngine(this._ref);

  /// Start the simulation
  void start() {
    final canvasState = _ref.read(canvasProvider);
    final problem = _ref.read(currentProblemProvider);
    
    // Validate design before starting
    _runValidationAndStart();
  }

  Future<void> _runValidationAndStart() async {
    final canvasState = _ref.read(canvasProvider);
    final problem = _ref.read(currentProblemProvider);

    final validation = await compute(_validateDesign, _ValidationData(
      components: canvasState.components,
      connections: canvasState.connections,
      problem: problem,
    ));

    if (!validation.isValid) {
      return;
    }

    final simulationNotifier = _ref.read(simulationProvider.notifier);
    simulationNotifier.start();

    // Run at 10 ticks per second (100ms interval)
    _simulationTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _tick(),
    );
  }

  static ValidationResult _validateDesign(_ValidationData data) {
    return DesignValidator.validate(
      components: data.components,
      connections: data.connections,
      problem: data.problem,
    );
  }

  /// Pause the simulation
  void pause() {
    _ref.read(simulationProvider.notifier).pause();
  }

  /// Resume the simulation
  void resume() {
    _ref.read(simulationProvider.notifier).resume();
  }

  /// Stop the simulation
  void stop() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isProcessingTick = false;
    _ref.read(simulationProvider.notifier).stop();
  }

  /// Complete the simulation and calculate score
  Future<void> complete() async {
    stop();
    _ref.read(simulationProvider.notifier).complete();

    // Calculate final score in background
    final canvas = _ref.read(canvasProvider);
    final simState = _ref.read(simulationProvider);
    final problem = _ref.read(currentProblemProvider);

    final score = await compute(_calculateScoreIsolate, _ScoreData(
      canvas: canvas,
      simState: simState,
      problem: problem,
    ));
    
    _ref.read(scoreProvider.notifier).state = score;
  }

  /// Single simulation tick
  Future<void> _tick() async {
    // Avoid overlapping calculations if one tick takes > 100ms
    if (_isProcessingTick) return;

    final simState = _ref.read(simulationProvider);
    if (!simState.isRunning) return;

    _isProcessingTick = true;

    try {
      final canvasState = _ref.read(canvasProvider);
      final problem = _ref.read(currentProblemProvider);
      
      // Prepare data for isolate
      final data = SimulationData(
        components: canvasState.components,
        connections: canvasState.connections,
        problem: problem,
        currentGlobalMetrics: simState.globalMetrics,
        tickCount: simState.tickCount,
      );

      // Run simulation in background
      final result = await compute(runSimulationTick, data);

      // back on main thread, update UI
      final canvasNotifier = _ref.read(canvasProvider.notifier);
      final simNotifier = _ref.read(simulationProvider.notifier);

      simNotifier.tick();
      
      canvasNotifier.updateMetrics(result.componentMetrics);
      canvasNotifier.updateConnectionTraffic(result.connectionTraffic);

      for (final failure in result.failures) {
        simNotifier.addFailure(failure);
      }

      simNotifier.updateMetrics(result.globalMetrics);

      // Auto-complete after 10 seconds (100 ticks at 10 ticks/sec)
      if (simState.tickCount >= 100 || result.isCompleted) {
        complete();
      }
    } catch (e) {
      debugPrint('Simulation error: $e');
    } finally {
      _isProcessingTick = false;
    }
  }

  /// Calculate final score (Now static for Isolate support)
  static Score _calculateScoreIsolate(_ScoreData data) {
    final canvas = data.canvas;
    final simState = data.simState;
    final problem = data.problem;
    final metrics = simState.globalMetrics;

    // Scalability score (based on handling target RPS)
    double scalability = 100;
    final targetRps = problem.constraints.effectiveQps;
    final handledRps = metrics.successfulRequests;
    scalability = (handledRps / targetRps * 100).clamp(0.0, 100.0);

    // Reliability score (based on availability and SPOF)
    double reliability = 100;
    final availabilityDelta = 
        (1 - metrics.availability) / (1 - problem.constraints.availabilityTarget);
    reliability = (100 - availabilityDelta * 50).clamp(0.0, 100.0);
    
    // Penalize for SPOFs
    final spofCount = simState.failures
        .where((f) => f.type == FailureType.spof)
        .map((f) => f.componentId)
        .toSet()
        .length;
    reliability -= spofCount * 10;
    reliability = reliability.clamp(0.0, 100.0);

    // Performance score (based on latency)
    double performance = 100;
    if (metrics.p95LatencyMs > problem.constraints.latencySlaMsP95) {
      final latencyRatio = metrics.p95LatencyMs / problem.constraints.latencySlaMsP95;
      performance = (100 / latencyRatio).clamp(0.0, 100.0);
    }

    // Cost score (lower cost = higher score)
    double cost = 100;
    final monthlyBudget = problem.constraints.budgetPerMonth;
    final monthlyCost = metrics.monthlyCost;
    if (monthlyCost > monthlyBudget) {
      cost = (monthlyBudget / monthlyCost * 100).clamp(0.0, 100.0);
    } else {
      // Bonus for being under budget
      cost = 100 - (monthlyCost / monthlyBudget * 20);
    }

    // Simplicity score (fewer components = higher score)
    double simplicity = 100;
    final componentCount = canvas.components.length;
    final optimalCount = problem.optimalComponents.length;
    if (componentCount > optimalCount * 1.5) {
      simplicity = (optimalCount / componentCount * 100).clamp(0.0, 100.0);
    } else if (componentCount < optimalCount * 0.5) {
      // Too few components (missing critical parts)
      simplicity = 50;
    }

    return Score(
      scalability: scalability,
      reliability: reliability,
      performance: performance,
      cost: cost,
      simplicity: simplicity,
    );
  }

  /// Dispose of resources
  void dispose() {
    stop();
  }
}

/// Helper classes for data passing to isolates
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

class _ScoreData {
  final CanvasState canvas;
  final SimulationState simState;
  final Problem problem;

  _ScoreData({
    required this.canvas,
    required this.simState,
    required this.problem,
  });
}

/// Provider for the simulation engine
final simulationEngineProvider = Provider((ref) => SimulationEngine(ref));
