import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/problem.dart';

class AiAnalysisResult {
  final int score;
  final List<String> issues; // Critical issues
  final List<String> suggestions; // Improvements
  final String summary;

  AiAnalysisResult({
    required this.score,
    required this.issues,
    required this.suggestions,
    required this.summary,
  });

  factory AiAnalysisResult.fromMap(Map<String, dynamic> map) {
    return AiAnalysisResult(
      score: map['score'] as int? ?? 0,
      issues: List<String>.from(map['issues'] ?? []),
      suggestions: List<String>.from(map['suggestions'] ?? []),
      summary: map['summary'] as String? ?? '',
    );
  }
}

class AiAssistService {
  /* 
     NOTE: In a real app, do NOT hardcode API keys. 
     Use --dart-define or a backend proxy.
     For this demo, we'll try to find a valid key or ask user.
  */
  static const String _kDemoApiKey = 'AIzaSyD-Lvv4nPB7Zl1v8upCZWFFQfs28FxKeuY'; 

  static bool get hasDemoKey => _kDemoApiKey.isNotEmpty;

  final String _apiKey;

  AiAssistService({String? apiKey}) 
      : _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY', defaultValue: _kDemoApiKey);

  Future<AiAnalysisResult> analyzeDesign({
    required Map<String, dynamic> designData,
    required Problem problem,
  }) async {
    // List of models to try in order of preference
    const modelsToTry = [
      'gemini-1.5-flash',
      'gemini-1.5-flash-latest',
      'gemini-pro',
      'gemini-1.0-pro',
    ];

    String? lastError;

    for (final modelName in modelsToTry) {
      try {
        debugPrint('AI Analysis: Trying model $modelName...');
        final model = GenerativeModel(
          model: modelName,
          apiKey: _apiKey,
        );

        final prompt = _buildPrompt(designData, problem);
        final content = [Content.text(prompt)];
        
        final response = await model.generateContent(content);
        final text = response.text;

        if (text == null) throw Exception('Empty response from AI');

        // Extract JSON from response (handle markdown code blocks if any)
        final jsonString = _extractJson(text);
        final map = jsonDecode(jsonString);
        
        return AiAnalysisResult.fromMap(map);
      } catch (e) {
        debugPrint('Model $modelName failed: $e');
        lastError = e.toString();
        // Continue to next model
      }
    }

    // All models failed
    return AiAnalysisResult(
      score: 0,
      issues: ['Analysis failed on all models. Last error: $lastError'],
      suggestions: ['Check your internet connection or API key.', 'Ensure Google Generative AI API is enabled.'],
      summary: 'Unable to analyze design.',
    );
  }

  String _buildPrompt(Map<String, dynamic> design, Problem problem) {
    // Simplify design data for token efficiency
    // NOTE: 'components' is a Map<String, dynamic>, so we iterate its values
    final componentsMap = design['components'] as Map<String, dynamic>? ?? {};
    final components = componentsMap.values.map((c) {
      return '${c['type']} (Label: ${c['name']})'; 
    }).join(', ');

    final connections = (design['connections'] as List? ?? []).map((c) {
      return '${c['from']} -> ${c['to']}'; // NOTE: Blueprint uses 'from'/'to', not sourceId/targetId
    }).join(', ');

    return '''
You are a Senior System Design Architect. Analyze the following system design solution for the problem: "${problem.title}".

Problem Context:
${problem.description}

User's Design:
- Components: [$components]
- Connections: [$connections]

Analyze strictly based on system scalability, reliability, and correctness.
Return ONLY valid JSON with this structure:
{
  "score": <0-100 integer>,
  "summary": "<1-2 sentence high-level feedback>",
  "issues": ["<critical flaw 1>", "<critical flaw 2>"],
  "suggestions": ["<improvement tip 1>", "<improvement tip 2>"]
}
''';
  }

  String _extractJson(String text) {
    text = text.trim();
    if (text.startsWith('```json')) {
      final index = text.indexOf('```json');
      final lastIndex = text.lastIndexOf('```');
      if (index != -1 && lastIndex != -1) {
        return text.substring(index + 7, lastIndex).trim();
      }
    } else if (text.startsWith('```')) {
       final index = text.indexOf('```');
      final lastIndex = text.lastIndexOf('```');
      if (index != -1 && lastIndex != -1) {
        return text.substring(index + 3, lastIndex).trim();
      }
    }
    // Fallback: assume bare JSON if starts with {
    if (text.startsWith('{')) return text;
    
    throw Exception('Invalid JSON format from AI');
  }
}
