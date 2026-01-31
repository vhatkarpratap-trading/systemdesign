/// Multi-dimensional scoring for system designs
class Score {
  final double scalability; // 0-100
  final double reliability; // 0-100
  final double performance; // 0-100
  final double cost; // 0-100 (lower cost = higher score)
  final double simplicity; // 0-100 (fewer components = higher score)

  const Score({
    this.scalability = 0,
    this.reliability = 0,
    this.performance = 0,
    this.cost = 0,
    this.simplicity = 0,
  });

  /// Calculate overall score (weighted average)
  double get overall {
    return (scalability * 0.25 +
            reliability * 0.25 +
            performance * 0.25 +
            cost * 0.15 +
            simplicity * 0.10);
  }

  /// Get letter grade
  String get grade {
    final score = overall;
    if (score >= 90) return 'S';
    if (score >= 80) return 'A';
    if (score >= 70) return 'B';
    if (score >= 60) return 'C';
    if (score >= 50) return 'D';
    return 'F';
  }

  /// Get star rating (1-5)
  int get stars {
    final score = overall;
    if (score >= 90) return 5;
    if (score >= 75) return 4;
    if (score >= 60) return 3;
    if (score >= 40) return 2;
    return 1;
  }

  Score copyWith({
    double? scalability,
    double? reliability,
    double? performance,
    double? cost,
    double? simplicity,
  }) {
    return Score(
      scalability: scalability ?? this.scalability,
      reliability: reliability ?? this.reliability,
      performance: performance ?? this.performance,
      cost: cost ?? this.cost,
      simplicity: simplicity ?? this.simplicity,
    );
  }

  Map<String, double> toMap() => {
        'Scalability': scalability,
        'Reliability': reliability,
        'Performance': performance,
        'Cost Efficiency': cost,
        'Simplicity': simplicity,
      };
}

/// Detailed score breakdown with explanations
class ScoreBreakdown {
  final Score score;
  final List<ScoreFactor> positiveFactors;
  final List<ScoreFactor> negativeFactors;
  final List<String> improvements;

  const ScoreBreakdown({
    required this.score,
    this.positiveFactors = const [],
    this.negativeFactors = const [],
    this.improvements = const [],
  });
}

/// A factor that affects the score
class ScoreFactor {
  final String category;
  final String description;
  final double impact; // Points added or subtracted
  final String? componentId;

  const ScoreFactor({
    required this.category,
    required this.description,
    required this.impact,
    this.componentId,
  });
}

/// Level completion result
class LevelResult {
  final String problemId;
  final ScoreBreakdown scoreBreakdown;
  final Duration completionTime;
  final int attempts;
  final bool passed;
  final List<String> unlockedContent;

  const LevelResult({
    required this.problemId,
    required this.scoreBreakdown,
    required this.completionTime,
    this.attempts = 1,
    this.passed = false,
    this.unlockedContent = const [],
  });

  /// Check if score qualifies for passing
  static bool isPassing(Score score) => score.overall >= 60;
}
