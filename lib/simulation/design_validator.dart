import 'package:flutter/material.dart';
import '../models/component.dart';
import '../models/connection.dart';
import '../models/problem.dart';
import '../theme/app_theme.dart';

/// Validation result for system design
class ValidationResult {
  final bool isValid;
  final List<ValidationIssue> issues;
  final List<String> suggestions;
  final int score;

  const ValidationResult({
    required this.isValid,
    required this.issues,
    required this.suggestions,
    required this.score,
  });

  factory ValidationResult.empty() => const ValidationResult(
        isValid: false,
        issues: [],
        suggestions: [],
        score: 0,
      );
}

/// Single validation issue
class ValidationIssue {
  final String title;
  final String description;
  final ValidationSeverity severity;
  final String? componentId;

  const ValidationIssue({
    required this.title,
    required this.description,
    required this.severity,
    this.componentId,
  });
}

enum ValidationSeverity { error, warning, info }

/// Validates system design before and during simulation
class DesignValidator {
  /// Validate the current design against problem requirements
  static ValidationResult validate({
    required List<SystemComponent> components,
    required List<Connection> connections,
    required Problem problem,
  }) {
    final issues = <ValidationIssue>[];
    final suggestions = <String>[];
    int score = 0;

    // Check 1: Has any components
    if (components.isEmpty) {
      issues.add(const ValidationIssue(
        title: 'No components',
        description: 'Add at least one component to build your system',
        severity: ValidationSeverity.error,
      ));
      return ValidationResult(
        isValid: false,
        issues: issues,
        suggestions: ['Start by adding a Load Balancer or App Server'],
        score: 0,
      );
    }

    // Check 2: Has entry point (component that can receive traffic)
    final entryComponents = components.where((c) =>
        c.type == ComponentType.loadBalancer ||
        c.type == ComponentType.apiGateway ||
        c.type == ComponentType.cdn ||
        c.type == ComponentType.dns ||
        c.type == ComponentType.customService);
    
    if (entryComponents.isEmpty) {
      issues.add(const ValidationIssue(
        title: 'No entry point',
        description: 'Add a Load Balancer, API Gateway, or CDN to receive traffic',
        severity: ValidationSeverity.error,
      ));
    } else {
      score += 20;
    }

    // Check 3: Has data storage
    final hasStorage = components.any((c) =>
        c.type == ComponentType.database ||
        c.type == ComponentType.objectStore);
    
    if (!hasStorage) {
      issues.add(const ValidationIssue(
        title: 'No data storage',
        description: 'Add a Database to store your data persistently',
        severity: ValidationSeverity.warning,
      ));
      suggestions.add('Most systems need a database for persistent storage');
    } else {
      score += 20;
    }

    // Check 4: Has application server
    final hasAppServer = components.any((c) =>
        c.type == ComponentType.appServer ||
        c.type == ComponentType.serverless ||
        c.type == ComponentType.customService);
    
    if (!hasAppServer) {
      issues.add(const ValidationIssue(
        title: 'No compute layer',
        description: 'Add an App Server or Serverless function to process requests',
        severity: ValidationSeverity.warning,
      ));
    } else {
      score += 20;
    }

    // Check 5: Are components connected?
    final connectedIds = <String>{};
    for (final conn in connections) {
      connectedIds.add(conn.sourceId);
      connectedIds.add(conn.targetId);
    }
    
    final disconnectedComponents = components
        .where((c) => !connectedIds.contains(c.id))
        .toList();
    
    if (disconnectedComponents.isNotEmpty) {
      for (final comp in disconnectedComponents) {
        issues.add(ValidationIssue(
          title: '${comp.type.displayName} not connected',
          description: 'Connect to other components for data to flow',
          severity: ValidationSeverity.warning,
          componentId: comp.id,
        ));
      }
    } else if (connections.isNotEmpty) {
      score += 20;
    }

    // Check 6: Read-heavy systems should have cache
    if (problem.constraints.readWriteRatio > 10) {
      final hasCache = components.any((c) => c.type == ComponentType.cache);
      if (!hasCache) {
        suggestions.add('This is a read-heavy system. Adding a Cache would improve performance.');
      } else {
        score += 10;
      }
    }

    // Check 7: High DAU should have load balancing
    if (problem.constraints.dau > 1000000) {
      final hasLb = components.any((c) => c.type == ComponentType.loadBalancer);
      if (!hasLb) {
        suggestions.add('High traffic systems benefit from a Load Balancer');
      } else {
        score += 10;
      }
    }

    // Check optimal components
    final componentTypes = components.map((c) => c.type.name).toSet();
    final optimalTypes = problem.optimalComponents.toSet();
    final matchingTypes = componentTypes.intersection(optimalTypes);
    
    if (matchingTypes.length == optimalTypes.length) {
      suggestions.add('Great! You have all the recommended components.');
    } else if (matchingTypes.length >= optimalTypes.length * 0.7) {
      suggestions.add('Good progress! You have most recommended components.');
    }

    // Check Flow (Solution Direction)
    if (problem.optimalConnections.isNotEmpty) {
      for (final optConn in problem.optimalConnections) {
        // Look for a matching connection in user design
        final hasConnection = connections.any((conn) {
          final source = components.firstWhere((c) => c.id == conn.sourceId, orElse: () => components.first);
          final target = components.firstWhere((c) => c.id == conn.targetId, orElse: () => components.first);
          if (source == components.first || target == components.first) return false;
          
          return source.type.name == optConn.fromType && target.type.name == optConn.toType;
        });

        if (!hasConnection) {
          suggestions.add(
            'Tip: Consider connecting ${optConn.fromType} to ${optConn.toType} for better flow.',
          );
        }
      }
    }

    final hasErrors = issues.any((i) => i.severity == ValidationSeverity.error);
    
    return ValidationResult(
      isValid: !hasErrors,
      issues: issues,
      suggestions: suggestions,
      score: score.clamp(0, 100),
    );
  }

  /// Get icon for severity
  static IconData severityIcon(ValidationSeverity severity) {
    return switch (severity) {
      ValidationSeverity.error => Icons.error_outline,
      ValidationSeverity.warning => Icons.warning_amber_outlined,
      ValidationSeverity.info => Icons.info_outline,
    };
  }

  /// Get color for severity
  static Color severityColor(ValidationSeverity severity) {
    return switch (severity) {
      ValidationSeverity.error => AppTheme.error,
      ValidationSeverity.warning => AppTheme.warning,
      ValidationSeverity.info => AppTheme.primary,
    };
  }
}
