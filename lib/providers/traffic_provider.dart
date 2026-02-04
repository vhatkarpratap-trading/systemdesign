import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/traffic_particle.dart';
import '../providers/game_provider.dart';

final trafficProvider = StateNotifierProvider<TrafficNotifier, List<TrafficParticle>>((ref) {
  return TrafficNotifier(ref);
});

class TrafficNotifier extends StateNotifier<List<TrafficParticle>> {
  final Ref _ref;
  Timer? _timer;
  final Random _random = Random();

  TrafficNotifier(this._ref) : super([]) {
    _startTimer();
  }

  void _startTimer() {
    // 60 FPS = ~16ms
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _updateParticles(0.016);
    });
  }

  void _updateParticles(double dt) {
    // 1. Update existing particles
    final canvas = _ref.read(canvasProvider);
    final simulationState = _ref.read(simulationProvider);
    
    // If paused, don't move particles
    if (!simulationState.isRunning && simulationState.simulationSpeed < 0.1) {
       return;
    }

    // Speed multiplier from simulation speed
    // Cap animation speed multiplier so it doesn't look ridiculous at 100x sim speed
    final timeScale = (simulationState.simulationSpeed).clamp(0.0, 5.0); 
    
    final nextParticles = <TrafficParticle>[];
    
    for (final p in state) {
      final newProgress = p.progress + (p.speed * dt * timeScale);
      if (newProgress < 1.0) {
        nextParticles.add(p.copyWith(progress: newProgress));
      }
    }

    // 2. Spawn new particles based on connection traffic
    if (simulationState.isRunning) {
        final connections = canvas.connections;
        final metricsMap = _ref.read(simulationMetricsProvider);

        for (final connection in connections) {
          final flow = connection.trafficFlow; // 0.0 to 5.0+
          
          if (flow > 0.01) {
            // Spawn probability proportional to flow
            final spawnProb = flow * dt * 20.0;
            
            // Allow multiple particles per frame for high traffic
            int spawnCount = spawnProb.floor();
            if (_random.nextDouble() < (spawnProb - spawnCount)) {
              spawnCount++;
            }
            
            // Limit max particles
            if (state.length > 800) spawnCount = 0;

            if (spawnCount > 0) {
              final sourceMetrics = metricsMap[connection.sourceId];
              
              // Latency affects speed: High latency = Slower particles
              // Avg speed ~0.5. 
              // If latency is 500ms, speed should be slower?
              // Let's say base traversal is 1 second.
              // If latency is high, maybe they move slower?
              // Actually, visual intuition: Fast moving = Fast/Good. Slow/Stuck = Lag.
              double speed = 0.5;
              Color color = Colors.greenAccent;
              
              if (sourceMetrics != null) {
                 // Speed mapping
                 // 10ms -> Speed 1.0 (Fast)
                 // 1000ms -> Speed 0.1 (Slow)
                 speed = (100.0 / (sourceMetrics.latencyMs + 50.0)).clamp(0.1, 1.5);
                 
                 // Color mapping based on Error Rate
                 if (sourceMetrics.errorRate > 0.2) color = Colors.redAccent;
                 else if (sourceMetrics.errorRate > 0.05) color = Colors.orangeAccent;
                 else if (sourceMetrics.latencyMs > 300) color = Colors.yellowAccent;
              }

              for (int i = 0; i < spawnCount; i++) {
                // Add some velocity jitter
                final particleSpeed = speed * (0.8 + _random.nextDouble() * 0.4);
                
                nextParticles.add(TrafficParticle(
                  id: '${connection.id}-${DateTime.now().microsecondsSinceEpoch}-$i',
                  connectionId: connection.id,
                  progress: 0.0,
                  speed: particleSpeed, 
                  color: color,
                ));
              }
            }
          }
        }
    }

    state = nextParticles;
  }
  


  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
