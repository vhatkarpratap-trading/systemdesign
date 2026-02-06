import 'dart:math';
import '../models/component.dart';
import '../models/metrics.dart';
import '../models/problem.dart';

class CostEstimate {
  final double base;
  final double storage;
  final double request;
  final double dataTransfer;
  final double network;

  const CostEstimate({
    this.base = 0,
    this.storage = 0,
    this.request = 0,
    this.dataTransfer = 0,
    this.network = 0,
  });

  double get total => base + storage + request + dataTransfer + network;
}

class CostModel {
  static const double hoursPerMonth = 24 * 30;
  static const double _egressPerGb = 0.085;
  static const double _crossRegionPerGb = 0.02;
  static const double _lambdaRequestPerMillion = 0.20;
  static const double _lambdaGbSecondPrice = 0.0000167;
  static const double _cachePerGbMonth = 5.0;

  static const Map<ComponentType, double> _requestPricePerMillion = {
    ComponentType.apiGateway: 3.50,
    ComponentType.waf: 0.60,
    ComponentType.cdn: 0.75,
    ComponentType.queue: 0.40,
    ComponentType.pubsub: 0.40,
    ComponentType.stream: 0.20,
    ComponentType.notificationService: 0.50,
  };

  static CostEstimate estimateComponentHourlyCost({
    required SystemComponent component,
    required Problem problem,
    required int storageComponentCount,
    required int dbComponentCount,
    ComponentMetrics? metrics,
  }) {
    final config = component.config;
    final baseConfig = ComponentConfig.defaultFor(component.type);
    final capacityFactor = _ratio(config.capacity, baseConfig.capacity, min: 0.5, max: 4.0);

    final effectiveInstances = _effectiveInstances(component, metrics);
    final regionCount = config.regions.isEmpty ? 1 : config.regions.length;
    final regionFactor = _isGlobalEdge(component.type) ? 1 : regionCount;

    double base = 0;
    if (!_isUsageOnly(component.type)) {
      base = config.costPerHour * capacityFactor * effectiveInstances * regionFactor;
    }

    double storage = 0;
    if (_isStorageComponent(component.type)) {
      if (component.type == ComponentType.cache) {
        final memoryGb = _estimateCacheMemoryGb(config);
        storage += memoryGb * _cachePerGbMonth / hoursPerMonth * regionFactor;
      } else {
        final storageGb = _allocateStorageGb(
          component.type,
          problem,
          storageComponentCount,
          dbComponentCount,
        );
        final perGbMonth = _storagePricePerGbMonth(component.type);
        final replicationCopies = config.replication ? max(1, config.replicationFactor) : 1;
        storage += storageGb * perGbMonth / hoursPerMonth * replicationCopies * regionFactor;
      }
    }

    double request = 0;
    double dataTransfer = 0;
    double network = 0;

    final currentRps = metrics?.currentRps ?? 0;
    if (currentRps > 0) {
      final requestsPerHour = currentRps * 3600;
      final perMillion = _requestPricePerMillion[component.type] ?? 0;
      request += (requestsPerHour / 1000000) * perMillion;

      if (component.type == ComponentType.serverless) {
        request += (requestsPerHour / 1000000) * _lambdaRequestPerMillion;
        final durationSec = max(0.05, (metrics?.latencyMs ?? 50) / 1000);
        const memoryGb = 0.5;
        final gbSeconds = requestsPerHour * durationSec * memoryGb;
        request += gbSeconds * _lambdaGbSecondPrice;
      }

      final dataKbPerRequest = _dataKbPerRequest(component.type, problem);
      if (dataKbPerRequest > 0) {
        final dataGb = requestsPerHour * dataKbPerRequest / (1024 * 1024);
        dataTransfer += dataGb * _egressPerGb;
      }

      if (_isStateful(component.type) && regionFactor > 1) {
        final writeFraction = 1 / (problem.constraints.readWriteRatio + 1);
        final writeRps = currentRps * writeFraction;
        final writeGb = writeRps * _requestKb(problem) * 3600 / (1024 * 1024);
        network += writeGb * (regionFactor - 1) * _crossRegionPerGb;
      }
    }

    return CostEstimate(
      base: base,
      storage: storage,
      request: request,
      dataTransfer: dataTransfer,
      network: network,
    );
  }

  static double estimateTotalHourlyCost({
    required List<SystemComponent> components,
    required Map<String, ComponentMetrics> metricsById,
    required Problem problem,
  }) {
    final storageCount = components.where((c) => isStorageComponentType(c.type)).length;
    final dbCount = components.where((c) => isDatabaseComponentType(c.type)).length;
    double total = 0;

    for (final component in components) {
      final metrics = metricsById[component.id];
      total += estimateComponentHourlyCost(
        component: component,
        problem: problem,
        storageComponentCount: storageCount,
        dbComponentCount: dbCount,
        metrics: metrics,
      ).total;
    }
    return total;
  }

  static bool isStorageComponentType(ComponentType type) => _isPersistentStorage(type);
  static bool isDatabaseComponentType(ComponentType type) => _isDatabaseLike(type);

  static int _effectiveInstances(SystemComponent component, ComponentMetrics? metrics) {
    final config = component.config;
    final floorInstances = config.autoScale ? max(1, config.minInstances) : max(1, config.instances);
    int effective = floorInstances;

    if (metrics != null) {
      final running = max(1, metrics.readyInstances) + metrics.coldStartingInstances;
      effective = max(effective, running);
      if (config.autoScale) {
        effective = max(effective, metrics.targetInstances);
      } else {
        effective = max(effective, config.instances);
      }
    }

    if (_isStateful(component.type) &&
        config.replication &&
        config.replicationFactor > effective) {
      effective = config.replicationFactor;
    }
    return effective;
  }

  static double _ratio(int value, int baseline, {double min = 0.5, double max = 4.0}) {
    if (baseline <= 0) return 1.0;
    final ratio = value / baseline;
    return ratio.clamp(min, max);
  }

  static double _storagePricePerGbMonth(ComponentType type) {
    return switch (type) {
      ComponentType.objectStore => 0.023,
      ComponentType.dataLake => 0.012,
      ComponentType.dataWarehouse => 0.20,
      ComponentType.searchIndex => 0.15,
      ComponentType.vectorDb => 0.18,
      _ => 0.12,
    };
  }

  static double _allocateStorageGb(
    ComponentType type,
    Problem problem,
    int storageComponentCount,
    int dbComponentCount,
  ) {
    final totalGb = problem.constraints.dataStorageGb.toDouble();
    if (_isDatabaseLike(type)) {
      return totalGb / max(1, dbComponentCount);
    }
    return totalGb / max(1, storageComponentCount);
  }

  static double _estimateCacheMemoryGb(ComponentConfig config) {
    final ttlFactor = (config.cacheTtlSeconds / 300).clamp(0.5, 6.0);
    final size = (config.capacity / 20000) * ttlFactor;
    return size.clamp(1.0, 128.0);
  }

  static double _dataKbPerRequest(ComponentType type, Problem problem) {
    return switch (type) {
      ComponentType.cdn => _constraint(problem, 'avgCdnResponseKb', 256.0),
      ComponentType.objectStore => _constraint(problem, 'avgObjectResponseKb', 256.0),
      _ => 0.0,
    };
  }

  static double _requestKb(Problem problem) {
    return _constraint(problem, 'avgRequestKb', 8.0);
  }

  static double _constraint(Problem problem, String key, double fallback) {
    final value = problem.constraints.customConstraints[key];
    if (value is num) return value.toDouble();
    return fallback;
  }

  static bool _isUsageOnly(ComponentType type) => type == ComponentType.serverless;

  static bool _isStorageComponent(ComponentType type) {
    return type == ComponentType.cache || _isPersistentStorage(type);
  }

  static bool _isPersistentStorage(ComponentType type) {
    return _isDatabaseLike(type) ||
        type == ComponentType.objectStore ||
        type == ComponentType.dataLake ||
        type == ComponentType.dataWarehouse;
  }

  static bool _isDatabaseLike(ComponentType type) {
    return type == ComponentType.database ||
        type == ComponentType.keyValueStore ||
        type == ComponentType.timeSeriesDb ||
        type == ComponentType.graphDb ||
        type == ComponentType.vectorDb ||
        type == ComponentType.searchIndex ||
        type == ComponentType.dataWarehouse;
  }

  static bool _isStateful(ComponentType type) {
    return _isStorageComponent(type);
  }

  static bool _isGlobalEdge(ComponentType type) {
    return type == ComponentType.dns || type == ComponentType.cdn;
  }
}
