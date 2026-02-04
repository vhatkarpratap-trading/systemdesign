import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_component.dart';
import '../services/custom_component_repository.dart';

/// Provider for SharedPreferences instance - initialized lazily
final sharedPreferencesProvider = StateProvider<SharedPreferences?>((ref) => null);

/// State for custom components list
class CustomComponentState {
  final List<CustomComponentDefinition> components;
  final bool isLoading;
  final String? error;

  const CustomComponentState({
    this.components = const [],
    this.isLoading = false,
    this.error,
  });

  CustomComponentState copyWith({
    List<CustomComponentDefinition>? components,
    bool? isLoading,
    String? error,
  }) {
    return CustomComponentState(
      components: components ?? this.components,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  /// Get only published components (for palette)
  List<CustomComponentDefinition> get published => 
      components.where((c) => c.isPublished).toList();

  /// Get only draft components (not published)
  List<CustomComponentDefinition> get drafts => 
      components.where((c) => !c.isPublished).toList();
}

/// Notifier for managing custom components (in-memory only, no persistence crash)
class CustomComponentNotifier extends StateNotifier<CustomComponentState> {
  CustomComponentRepository? _repository;

  CustomComponentNotifier() : super(const CustomComponentState());
  
  /// Attach persistence layer when SharedPreferences is ready
  void attachRepository(SharedPreferences prefs) {
    _repository = CustomComponentRepository(prefs);
    _loadFromStorage();
  }
  
  void _loadFromStorage() {
    if (_repository == null) return;
    try {
      final components = _repository!.getAll();
      state = state.copyWith(components: components);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  Future<void> _persistAll() async {
    if (_repository == null) return;
    for (final comp in state.components) {
      await _repository!.save(comp);
    }
  }

  /// Create a new empty custom component
  CustomComponentDefinition create() {
    final newComponent = CustomComponentDefinition.empty();
    state = state.copyWith(components: [...state.components, newComponent]);
    _persistAll();
    return newComponent;
  }

  /// Save (create or update) a custom component
  void save(CustomComponentDefinition component) {
    final exists = state.components.any((c) => c.id == component.id);
    if (exists) {
      state = state.copyWith(
        components: state.components.map((c) => c.id == component.id ? component : c).toList(),
      );
    } else {
      state = state.copyWith(components: [...state.components, component]);
    }
    _repository?.save(component);
  }

  /// Delete a custom component
  void delete(String id) {
    state = state.copyWith(
      components: state.components.where((c) => c.id != id).toList(),
    );
    _repository?.delete(id);
  }

  /// Publish a custom component (make it available in palette)
  void publish(String id) {
    state = state.copyWith(
      components: state.components.map((c) =>
        c.id == id ? c.copyWith(isPublished: true) : c
      ).toList(),
    );
    _repository?.publish(id);
  }

  /// Unpublish a custom component
  void unpublish(String id) {
    state = state.copyWith(
      components: state.components.map((c) =>
        c.id == id ? c.copyWith(isPublished: false) : c
      ).toList(),
    );
    _repository?.unpublish(id);
  }

  /// Get a component by ID
  CustomComponentDefinition? getById(String id) {
    try {
      return state.components.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Add an internal node to a component
  void addInternalNode(String componentId, InternalNode node) {
    final component = getById(componentId);
    if (component != null) {
      final updated = component.copyWith(
        internalNodes: [...component.internalNodes, node],
      );
      save(updated);
    }
  }

  /// Remove an internal node from a component
  void removeInternalNode(String componentId, String nodeId) {
    final component = getById(componentId);
    if (component != null) {
      final updatedNodes = component.internalNodes.where((n) => n.id != nodeId).toList();
      final updatedConnections = component.internalConnections
          .where((c) => c.sourceNodeId != nodeId && c.targetNodeId != nodeId)
          .toList();
      final updatedInputPorts = component.inputPorts
          .where((p) => p.connectedToNodeId != nodeId)
          .toList();
      final updatedOutputPorts = component.outputPorts
          .where((p) => p.connectedToNodeId != nodeId)
          .toList();
      
      final updated = component.copyWith(
        internalNodes: updatedNodes,
        internalConnections: updatedConnections,
        inputPorts: updatedInputPorts,
        outputPorts: updatedOutputPorts,
      );
      save(updated);
    }
  }

  /// Add an internal connection
  void addInternalConnection(String componentId, InternalConnection connection) {
    final component = getById(componentId);
    if (component != null) {
      final updated = component.copyWith(
        internalConnections: [...component.internalConnections, connection],
      );
      save(updated);
    }
  }

  /// Remove an internal connection
  void removeInternalConnection(String componentId, String connectionId) {
    final component = getById(componentId);
    if (component != null) {
      final updated = component.copyWith(
        internalConnections: component.internalConnections
            .where((c) => c.id != connectionId)
            .toList(),
      );
      save(updated);
    }
  }

  /// Add an input port
  void addInputPort(String componentId, Port port) {
    final component = getById(componentId);
    if (component != null) {
      final updated = component.copyWith(
        inputPorts: [...component.inputPorts, port],
      );
      save(updated);
    }
  }

  /// Add an output port
  void addOutputPort(String componentId, Port port) {
    final component = getById(componentId);
    if (component != null) {
      final updated = component.copyWith(
        outputPorts: [...component.outputPorts, port],
      );
      save(updated);
    }
  }
}

/// Provider for custom component state
final customComponentProvider = StateNotifierProvider<CustomComponentNotifier, CustomComponentState>((ref) {
  return CustomComponentNotifier();
});

/// Provider for published custom components only (for palette)
final publishedCustomComponentsProvider = Provider<List<CustomComponentDefinition>>((ref) {
  return ref.watch(customComponentProvider).published;
});
