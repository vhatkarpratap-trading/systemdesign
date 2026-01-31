import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/canvas_state.dart';

class DesignMetadata {
  final String id;
  final String name;
  final String problemId;
  final DateTime timestamp;

  DesignMetadata({
    required this.id,
    required this.name,
    required this.problemId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'problemId': problemId,
    'timestamp': timestamp.toIso8601String(),
  };

  factory DesignMetadata.fromJson(Map<String, dynamic> json) => DesignMetadata(
    id: json['id'],
    name: json['name'],
    problemId: json['problemId'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class ProgressRepository {
  static const String _prefix = 'design_state_';
  static const String _manifestKey = 'designs_manifest';

  Future<void> saveDesign(String id, String name, String problemId, CanvasState state) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save state
    final jsonString = jsonEncode(state.toJson());
    await prefs.setString('$_prefix$id', jsonString);

    // Update manifest
    final manifest = await _loadManifest();
    final index = manifest.indexWhere((m) => m.id == id);
    
    final meta = DesignMetadata(
      id: id,
      name: name,
      problemId: problemId,
      timestamp: DateTime.now(),
    );

    if (index >= 0) {
      manifest[index] = meta;
    } else {
      manifest.add(meta);
    }

    await _saveManifest(manifest);
  }

  Future<CanvasState?> loadDesign(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('$_prefix$id');
    
    if (jsonString == null) return null;

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return CanvasState.fromJson(json);
    } catch (e) {
      print('Error loading design $id: $e');
      return null;
    }
  }

  Future<List<DesignMetadata>> listDesigns() async {
    return _loadManifest();
  }

  Future<void> deleteDesign(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');

    final manifest = await _loadManifest();
    manifest.removeWhere((m) => m.id == id);
    await _saveManifest(manifest);
  }

  // Legacy support for problem-based progress
  Future<void> saveProgress(String problemId, CanvasState state) async {
    await saveDesign('legacy_$problemId', 'Autosave', problemId, state);
  }

  Future<CanvasState?> loadProgress(String problemId) async {
    return loadDesign('legacy_$problemId');
  }

  Future<List<DesignMetadata>> _loadManifest() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_manifestKey);
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.map((item) => DesignMetadata.fromJson(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveManifest(List<DesignMetadata> manifest) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(manifest.map((m) => m.toJson()).toList());
    await prefs.setString(_manifestKey, jsonString);
  }
}
