/// A system design problem/level definition
class Problem {
  final String id;
  final String title;
  final String description;
  final String scenario;
  final ProblemConstraints constraints;
  final List<String> hints;
  final List<String> optimalComponents;
  final List<ConnectionDefinition> optimalConnections; // Solution flow
  final int difficulty; // 1-5
  final bool isUnlocked;
  final String? iconPath;

  const Problem({
    required this.id,
    required this.title,
    required this.description,
    required this.scenario,
    required this.constraints,
    this.hints = const [],
    this.optimalComponents = const [],
    this.optimalConnections = const [],
    this.difficulty = 1,
    this.isUnlocked = false,
    this.iconPath,
  });

  Problem copyWith({
    String? id,
    String? title,
    String? description,
    String? scenario,
    ProblemConstraints? constraints,
    List<String>? hints,
    List<String>? optimalComponents,
    List<ConnectionDefinition>? optimalConnections,
    int? difficulty,
    bool? isUnlocked,
    String? iconPath,
  }) {
    return Problem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      scenario: scenario ?? this.scenario,
      constraints: constraints ?? this.constraints,
      hints: hints ?? this.hints,
      optimalComponents: optimalComponents ?? this.optimalComponents,
      optimalConnections: optimalConnections ?? this.optimalConnections,
      difficulty: difficulty ?? this.difficulty,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      iconPath: iconPath ?? this.iconPath,
    );
  }
}

/// Simplified connection definition for solution matching
class ConnectionDefinition {
  final String fromType; // e.g., 'loadBalancer'
  final String toType;   // e.g., 'apiGateway'
  
  const ConnectionDefinition(this.fromType, this.toType);
}

/// Constraints for a system design problem
class ProblemConstraints {
  final int dau; // Daily Active Users
  final int qps; // Queries per second (calculated from DAU)
  final double readWriteRatio; // e.g., 100 means 100:1 read:write
  final int latencySlaMsP50; // P50 latency target
  final int latencySlaMsP95; // P95 latency target
  final double availabilityTarget; // e.g., 0.9999 for 99.99%
  final int budgetPerMonth; // Monthly budget in USD
  final int dataStorageGb; // Total data storage needed
  final List<String> regions; // Required regions
  final Map<String, dynamic> customConstraints;

  const ProblemConstraints({
    required this.dau,
    this.qps = 0, // Will be calculated if not provided
    this.readWriteRatio = 10.0,
    this.latencySlaMsP50 = 50,
    this.latencySlaMsP95 = 200,
    this.availabilityTarget = 0.999,
    this.budgetPerMonth = 10000,
    this.dataStorageGb = 100,
    this.regions = const ['us-east-1'],
    this.customConstraints = const {},
  });

  /// Calculate QPS from DAU (assuming 10 requests per user per day, distributed over 8 peak hours)
  int get effectiveQps {
    if (qps > 0) return qps;
    // Assume 10 requests per user per day, 80% during 8 peak hours
    final dailyRequests = dau * 10;
    final peakHoursRequests = (dailyRequests * 0.8).toInt();
    final peakSeconds = 8 * 60 * 60;
    return (peakHoursRequests / peakSeconds).ceil();
  }

  /// Get read QPS
  int get readQps => (effectiveQps * readWriteRatio / (readWriteRatio + 1)).toInt();

  /// Get write QPS
  int get writeQps => (effectiveQps / (readWriteRatio + 1)).toInt();

  /// Format availability as percentage string
  String get availabilityString {
    final percentage = availabilityTarget * 100;
    if (percentage >= 99.99) return '99.99%';
    if (percentage >= 99.9) return '99.9%';
    if (percentage >= 99) return '99%';
    return '${percentage.toStringAsFixed(1)}%';
  }
  
  /// Alias for latencySlaMsP95 for convenience
  int get maxLatencyMs => latencySlaMsP95;

  /// Format DAU for display
  String get dauFormatted {
    if (dau >= 1000000000) return '${(dau / 1000000000).toStringAsFixed(1)}B';
    if (dau >= 1000000) return '${(dau / 1000000).toStringAsFixed(1)}M';
    if (dau >= 1000) return '${(dau / 1000).toStringAsFixed(1)}K';
    return dau.toString();
  }

  /// Format QPS for display
  String get qpsFormatted {
    final qps = effectiveQps;
    if (qps >= 1000000) return '${(qps / 1000000).toStringAsFixed(1)}M';
    if (qps >= 1000) return '${(qps / 1000).toStringAsFixed(1)}K';
    return qps.toString();
  }

  ProblemConstraints copyWith({
    int? dau,
    int? qps,
    double? readWriteRatio,
    int? latencySlaMsP50,
    int? latencySlaMsP95,
    double? availabilityTarget,
    int? budgetPerMonth,
    int? dataStorageGb,
    List<String>? regions,
    Map<String, dynamic>? customConstraints,
  }) {
    return ProblemConstraints(
      dau: dau ?? this.dau,
      qps: qps ?? this.qps,
      readWriteRatio: readWriteRatio ?? this.readWriteRatio,
      latencySlaMsP50: latencySlaMsP50 ?? this.latencySlaMsP50,
      latencySlaMsP95: latencySlaMsP95 ?? this.latencySlaMsP95,
      availabilityTarget: availabilityTarget ?? this.availabilityTarget,
      budgetPerMonth: budgetPerMonth ?? this.budgetPerMonth,
      dataStorageGb: dataStorageGb ?? this.dataStorageGb,
      regions: regions ?? this.regions,
      customConstraints: customConstraints ?? this.customConstraints,
    );
  }

  Map<String, dynamic> toJson() => {
        'dau': dau,
        'qps': qps,
        'readWriteRatio': readWriteRatio,
        'latencySlaMsP50': latencySlaMsP50,
        'latencySlaMsP95': latencySlaMsP95,
        'availabilityTarget': availabilityTarget,
        'budgetPerMonth': budgetPerMonth,
        'dataStorageGb': dataStorageGb,
        'regions': regions,
        'customConstraints': customConstraints,
      };
}
