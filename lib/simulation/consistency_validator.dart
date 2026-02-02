import 'dart:math';
import '../models/component.dart';
import '../models/connection.dart';
import '../models/metrics.dart';

/// Validates data consistency and detects anomalies during simulation
class ConsistencyValidator {
  /// Check for potential consistency issues in the system
  static List<FailureEvent> checkConsistency({
    required List<SystemComponent> components,
    required List<Connection> connections,
    required Map<String, ComponentMetrics> componentMetrics,
    required int tickCount,
  }) {
    final issues = <FailureEvent>[];
    final random = Random(tickCount);
    
    // Check database replication lag
    issues.addAll(_checkReplicationLag(components, componentMetrics));
    
    // Check for lost updates
    issues.addAll(_checkLostUpdates(components, componentMetrics, random));
    
    // Check message queue duplicate delivery
    issues.addAll(_checkDuplicateDelivery(components, componentMetrics, random));
    
    // Check cache stampede scenarios
    issues.addAll(_checkCacheStampede(components, connections, componentMetrics, random));
    
    return issues;
  }
  
  /// Check for replication lag in databases
  static List<FailureEvent> _checkReplicationLag(
    List<SystemComponent> components,
    Map<String, ComponentMetrics> componentMetrics,
  ) {
    final issues = <FailureEvent>[];
    
    for (final db in components.where((c) => c.type == ComponentType.database)) {
      if (db.config.replication && db.config.replicationFactor > 1) {
        final metrics = componentMetrics[db.id];
        if (metrics == null) continue;
        
        // Model replication lag (increases under load)
        final load = metrics.cpuUsage;
        final lagMs = (50 + load * 2000).toInt(); // 50ms to 2s lag
        
        if (lagMs > 500) {
          issues.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: db.id,
            type: FailureType.replicationLag,
            message: 'Replication lag ${lagMs}ms - users may see stale data',
            recommendation: 'Use read-your-writes consistency or strong reads for critical data',
            severity: (lagMs / 2000).clamp(0.3, 0.7),
            userVisible: true,
          ));
        }
        
        // Stale read detection
        if (lagMs > 1000) {
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
      }
    }
    
    return issues;
  }
  
  /// Check for lost updates due to concurrent writes
  static List<FailureEvent> _checkLostUpdates(
    List<SystemComponent> components,
    Map<String, ComponentMetrics> componentMetrics,
    Random random,
  ) {
    final issues = <FailureEvent>[];
    
    for (final db in components.where((c) => c.type == ComponentType.database)) {
      final metrics = componentMetrics[db.id];
      if (metrics == null) continue;
      
      // Check for lost updates (concurrent writes without proper locking)
      final hasQuorum = db.config.quorumWrite != null && db.config.quorumWrite! > 1;
      
      if (metrics.currentRps > 100 && !hasQuorum) {
        // Higher RPS = higher chance of concurrent write conflicts
        final conflictProbability = (metrics.currentRps / 1000).clamp(0.02, 0.1);
        
        if (random.nextDouble() < conflictProbability) {
          issues.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: db.id,
            type: FailureType.lostUpdate,
            message: 'Concurrent write conflict detected - data may be inconsistent',
            recommendation: 'Use optimistic locking, quorum writes, or transactions',
            severity: 0.8,
            userVisible: true,
          ));
        }
      }
    }
    
    return issues;
  }
  
  /// Check for duplicate message delivery in queues
  static List<FailureEvent> _checkDuplicateDelivery(
    List<SystemComponent> components,
    Map<String, ComponentMetrics> componentMetrics,
    Random random,
  ) {
    final issues = <FailureEvent>[];
    
    for (final queue in components.where((c) => 
        c.type == ComponentType.queue || c.type == ComponentType.pubsub)) {
      final metrics = componentMetrics[queue.id];
      if (metrics == null || metrics.currentRps == 0) continue;
      
      // At-least-once delivery: ~5% of messages may be duplicated
      if (random.nextDouble() < 0.05) {
        issues.add(FailureEvent(
          timestamp: DateTime.now(),
          componentId: queue.id,
          type: FailureType.duplicateDelivery,
          message: 'At-least-once delivery caused duplicate message processing',
          recommendation: 'Implement idempotent consumers or deduplication logic',
          severity: 0.4,
          userVisible: false,
        ));
      }
    }
    
    return issues;
  }
  
  /// Check for cache stampede scenarios
  static List<FailureEvent> _checkCacheStampede(
    List<SystemComponent> components,
    List<Connection> connections,
    Map<String, ComponentMetrics> componentMetrics,
    Random random,
  ) {
    final issues = <FailureEvent>[];
    
    for (final cache in components.where((c) => c.type == ComponentType.cache)) {
      final metrics = componentMetrics[cache.id];
      if (metrics == null) continue;
      
      // Cache stampede: sudden drop in hit rate with high traffic
      if (metrics.cacheHitRate < 0.3 && metrics.currentRps > 1000) {
        // Find connected databases
        final connectedDbs = connections
            .where((c) => c.sourceId == cache.id)
            .map((c) => c.targetId)
            .toList();
        
        if (connectedDbs.isNotEmpty) {
          issues.add(FailureEvent(
            timestamp: DateTime.now(),
            componentId: cache.id,
            type: FailureType.cacheStampede,
            message: 'Cache stampede: mass cache miss overwhelming database',
            recommendation: 'Use cache warming, probabilistic early expiration, or locking',
            severity: 0.7,
            affectedComponents: connectedDbs,
            userVisible: true,
          ));
        }
      }
    }
    
    return issues;
  }
}
