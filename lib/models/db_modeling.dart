import 'dart:math';
import 'component.dart';

enum DbFamily {
  sql('SQL (Relational)'),
  nosql('NoSQL (Key-Value)'),
  document('Document DB'),
  newsql('NewSQL'),
  graph('Graph DB'),
  timeSeries('Time-Series DB'),
  search('Search Engine'),
  vector('Vector DB'),
  analytics('Analytical DB');

  final String label;
  const DbFamily(this.label);
}

enum QueryPattern {
  pointReads('Point Reads'),
  rangeScans('Range Scans'),
  graphTraversal('Graph Traversal'),
  timeSeries('Time-Series Writes'),
  fullText('Full-Text Search'),
  analytics('Analytics / OLAP'),
  vectorSearch('Vector Search');

  final String label;
  const QueryPattern(this.label);
}

enum ConsistencyNeed {
  strong('Strong'),
  causal('Causal'),
  eventual('Eventual');

  final String label;
  const ConsistencyNeed(this.label);
}

enum LatencySensitivity {
  strict('Strict'),
  balanced('Balanced'),
  relaxed('Relaxed');

  final String label;
  const LatencySensitivity(this.label);
}

class DbWorkload {
  final double readWriteRatio;
  final Set<QueryPattern> patterns;
  final ConsistencyNeed consistency;
  final LatencySensitivity latencySensitivity;
  final bool needsTransactions;
  final bool flexibleSchema;
  final double dataSizeGb;

  const DbWorkload({
    required this.readWriteRatio,
    required this.patterns,
    required this.consistency,
    required this.latencySensitivity,
    required this.needsTransactions,
    required this.flexibleSchema,
    required this.dataSizeGb,
  });
}

class DbRecommendation {
  final DbFamily family;
  final double score;
  final List<String> reasons;

  const DbRecommendation({
    required this.family,
    required this.score,
    required this.reasons,
  });
}

class DbComparisonRow {
  final DbFamily family;
  final double fitScore;
  final int throughputRps;
  final double latencyMs;
  final String consistencyRisk;

  const DbComparisonRow({
    required this.family,
    required this.fitScore,
    required this.throughputRps,
    required this.latencyMs,
    required this.consistencyRisk,
  });
}

class DbHybridStack {
  final DbFamily primary;
  final List<DbFamily> secondary;
  final List<String> reasons;

  const DbHybridStack({
    required this.primary,
    required this.secondary,
    required this.reasons,
  });
}

class DbModeling {
  DbModeling._();

  static List<DbRecommendation> recommend(DbWorkload workload) {
    final recommendations = DbFamily.values.map((family) {
      final reasons = <String>[];
      double score = 0.45;

      if (workload.flexibleSchema) {
        if (family == DbFamily.document || family == DbFamily.nosql) {
          score += 0.18;
          reasons.add('Flexible schema');
        }
        if (family == DbFamily.sql) {
          score -= 0.08;
        }
      }

      if (workload.needsTransactions) {
        if (family == DbFamily.sql || family == DbFamily.newsql) {
          score += 0.22;
          reasons.add('ACID transactions');
        } else {
          score -= 0.1;
        }
      }

      if (workload.readWriteRatio >= 20) {
        if (family == DbFamily.search || family == DbFamily.document) {
          score += 0.12;
          reasons.add('Read-heavy workload');
        }
      } else if (workload.readWriteRatio <= 2) {
        if (family == DbFamily.timeSeries || family == DbFamily.nosql) {
          score += 0.12;
          reasons.add('Write-heavy workload');
        }
      }

      if (workload.patterns.contains(QueryPattern.graphTraversal)) {
        if (family == DbFamily.graph) {
          score += 0.45;
          reasons.add('Graph traversal workload');
        } else {
          score -= 0.15;
        }
      }
      if (workload.patterns.contains(QueryPattern.timeSeries)) {
        if (family == DbFamily.timeSeries) {
          score += 0.42;
          reasons.add('High ingest time-series');
        }
      }
      if (workload.patterns.contains(QueryPattern.fullText)) {
        if (family == DbFamily.search) {
          score += 0.5;
          reasons.add('Full-text search');
        }
      }
      if (workload.patterns.contains(QueryPattern.analytics)) {
        if (family == DbFamily.analytics) {
          score += 0.5;
          reasons.add('Analytical queries');
        } else if (family == DbFamily.sql) {
          score += 0.1;
        }
      }
      if (workload.patterns.contains(QueryPattern.vectorSearch)) {
        if (family == DbFamily.vector) {
          score += 0.5;
          reasons.add('Vector similarity search');
        }
      }

      switch (workload.consistency) {
        case ConsistencyNeed.strong:
          if (family == DbFamily.sql || family == DbFamily.newsql) {
            score += 0.25;
            reasons.add('Strong consistency');
          } else {
            score -= 0.12;
          }
          break;
        case ConsistencyNeed.causal:
          if (family == DbFamily.graph || family == DbFamily.document) {
            score += 0.1;
            reasons.add('Causal consistency');
          }
          break;
        case ConsistencyNeed.eventual:
          if (family == DbFamily.nosql || family == DbFamily.document) {
            score += 0.12;
            reasons.add('Eventual consistency OK');
          }
          break;
      }

      switch (workload.latencySensitivity) {
        case LatencySensitivity.strict:
          if (family == DbFamily.nosql || family == DbFamily.document) {
            score += 0.12;
            reasons.add('Low-latency reads');
          }
          break;
        case LatencySensitivity.relaxed:
          if (family == DbFamily.analytics) {
            score += 0.08;
            reasons.add('Latency-tolerant analytics');
          }
          break;
        case LatencySensitivity.balanced:
          break;
      }

      if (workload.dataSizeGb >= 1000) {
        if (family == DbFamily.timeSeries || family == DbFamily.analytics) {
          score += 0.15;
          reasons.add('Large data volume');
        }
      }

      score = score.clamp(0.05, 0.98);
      if (reasons.isEmpty) {
        reasons.add('General-purpose fit');
      }

      return DbRecommendation(
        family: family,
        score: score,
        reasons: reasons.take(3).toList(),
      );
    }).toList();

    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations;
  }

  static List<DbComparisonRow> compare(DbWorkload workload) {
    final baseLatency = <DbFamily, double>{
      DbFamily.sql: 9,
      DbFamily.nosql: 4,
      DbFamily.document: 5,
      DbFamily.newsql: 10,
      DbFamily.graph: 14,
      DbFamily.timeSeries: 6,
      DbFamily.search: 8,
      DbFamily.vector: 12,
      DbFamily.analytics: 18,
    };

    final baseThroughput = <DbFamily, int>{
      DbFamily.sql: 2500,
      DbFamily.nosql: 6000,
      DbFamily.document: 5000,
      DbFamily.newsql: 3500,
      DbFamily.graph: 1800,
      DbFamily.timeSeries: 8000,
      DbFamily.search: 4500,
      DbFamily.vector: 2200,
      DbFamily.analytics: 2000,
    };

    final recs = recommend(workload).toList();
    final scoreMap = {for (final r in recs) r.family: r.score};

    return [
      DbFamily.sql,
      DbFamily.nosql,
      DbFamily.newsql,
      DbFamily.graph,
      DbFamily.timeSeries,
      DbFamily.document,
    ].map((family) {
      final baseLat = baseLatency[family] ?? 10;
      final baseRps = baseThroughput[family] ?? 2000;

      final readHeavyBoost = workload.readWriteRatio >= 20 ? 1.2 : 1.0;
      final writeHeavyBoost = workload.readWriteRatio <= 2 ? 1.15 : 1.0;
      final throughput = (baseRps * readHeavyBoost * writeHeavyBoost).round();

      double latency = baseLat;
      if (workload.consistency == ConsistencyNeed.strong &&
          (family == DbFamily.nosql || family == DbFamily.document)) {
        latency *= 1.35;
      }
      if (workload.latencySensitivity == LatencySensitivity.strict) {
        latency *= 0.9;
      }
      if (workload.latencySensitivity == LatencySensitivity.relaxed) {
        latency *= 1.1;
      }

      String risk = 'Low';
      if (workload.consistency == ConsistencyNeed.strong &&
          (family == DbFamily.nosql || family == DbFamily.document)) {
        risk = 'High';
      } else if (workload.consistency == ConsistencyNeed.causal &&
          family == DbFamily.sql) {
        risk = 'Medium';
      }

      return DbComparisonRow(
        family: family,
        fitScore: (scoreMap[family] ?? 0.4) * 100,
        throughputRps: throughput,
        latencyMs: latency,
        consistencyRisk: risk,
      );
    }).toList();
  }

  static DbHybridStack buildHybridStack(DbWorkload workload) {
    final recommendations = recommend(workload);
    final primary = recommendations.first.family;

    final secondary = <DbFamily>{};
    final reasons = <String>[];

    if (workload.readWriteRatio >= 20) {
      secondary.add(DbFamily.search);
      reasons.add('Read-heavy + full-text needs');
    }
    if (workload.patterns.contains(QueryPattern.fullText)) {
      secondary.add(DbFamily.search);
      reasons.add('Full-text queries benefit from search engine');
    }
    if (workload.patterns.contains(QueryPattern.analytics)) {
      secondary.add(DbFamily.analytics);
      reasons.add('Analytics separated from OLTP');
    }
    if (workload.patterns.contains(QueryPattern.timeSeries)) {
      secondary.add(DbFamily.timeSeries);
      reasons.add('High ingest telemetry');
    }
    if (workload.patterns.contains(QueryPattern.graphTraversal)) {
      secondary.add(DbFamily.graph);
      reasons.add('Relationship queries');
    }
    if (workload.patterns.contains(QueryPattern.vectorSearch)) {
      secondary.add(DbFamily.vector);
      reasons.add('Embedding similarity search');
    }

    secondary.remove(primary);
    if (secondary.isEmpty) {
      reasons.add('Single-store is sufficient for current workload');
    }

    return DbHybridStack(
      primary: primary,
      secondary: secondary.toList(),
      reasons: reasons.take(3).toList(),
    );
  }

  static ComponentType? componentForFamily(DbFamily family) {
    return switch (family) {
      DbFamily.sql => ComponentType.database,
      DbFamily.newsql => ComponentType.database,
      DbFamily.nosql => ComponentType.keyValueStore,
      DbFamily.document => ComponentType.database,
      DbFamily.graph => ComponentType.graphDb,
      DbFamily.timeSeries => ComponentType.timeSeriesDb,
      DbFamily.search => ComponentType.searchIndex,
      DbFamily.vector => ComponentType.vectorDb,
      DbFamily.analytics => ComponentType.dataWarehouse,
    };
  }
}
