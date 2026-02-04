import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_component.dart';

/// Repository for storing and retrieving custom component definitions
class CustomComponentRepository {
  static const String _storageKey = 'custom_components';
  final SharedPreferences _prefs;

  CustomComponentRepository(this._prefs);

  /// Get all saved custom components
  List<CustomComponentDefinition> getAll() {
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((e) => CustomComponentDefinition.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If parsing fails, return empty list
      return [];
    }
  }

  /// Get only published custom components (for palette)
  List<CustomComponentDefinition> getPublished() {
    return getAll().where((c) => c.isPublished).toList();
  }

  /// Get a single custom component by ID
  CustomComponentDefinition? getById(String id) {
    final all = getAll();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Save a custom component (create or update)
  Future<void> save(CustomComponentDefinition definition) async {
    final all = getAll();
    final index = all.indexWhere((c) => c.id == definition.id);
    
    final updated = definition.copyWith(updatedAt: DateTime.now());
    
    if (index >= 0) {
      all[index] = updated;
    } else {
      all.add(updated);
    }
    
    await _saveAll(all);
  }

  /// Delete a custom component by ID
  Future<void> delete(String id) async {
    final all = getAll();
    all.removeWhere((c) => c.id == id);
    await _saveAll(all);
  }

  /// Publish a custom component (make it available in palette)
  Future<void> publish(String id) async {
    final component = getById(id);
    if (component != null) {
      await save(component.copyWith(isPublished: true));
    }
  }

  /// Unpublish a custom component
  Future<void> unpublish(String id) async {
    final component = getById(id);
    if (component != null) {
      await save(component.copyWith(isPublished: false));
    }
  }

  /// Import a custom component from JSON string
  Future<CustomComponentDefinition?> importFromJson(String jsonString) async {
    try {
      final definition = CustomComponentDefinition.fromJsonString(jsonString);
      await save(definition);
      return definition;
    } catch (e) {
      return null;
    }
  }

  /// Export a custom component to JSON string
  String? exportToJson(String id) {
    final component = getById(id);
    return component?.toJsonString();
  }

  Future<void> _saveAll(List<CustomComponentDefinition> components) async {
    final jsonList = components.map((c) => c.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(jsonList));
  }
}
