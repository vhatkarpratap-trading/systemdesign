import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'component.dart';
import 'connection.dart';

/// Port direction for custom component inputs/outputs
enum PortDirection { input, output }

/// A port that exposes an internal node for external connections
class Port {
  final String id;
  final String name;
  final PortDirection direction;
  final String? connectedToNodeId;  // Which internal node this port maps to

  const Port({
    required this.id,
    required this.name,
    required this.direction,
    this.connectedToNodeId,
  });

  Port copyWith({
    String? id,
    String? name,
    PortDirection? direction,
    String? connectedToNodeId,
  }) {
    return Port(
      id: id ?? this.id,
      name: name ?? this.name,
      direction: direction ?? this.direction,
      connectedToNodeId: connectedToNodeId ?? this.connectedToNodeId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'direction': direction.name,
    'connectedToNodeId': connectedToNodeId,
  };

  factory Port.fromJson(Map<String, dynamic> json) => Port(
    id: json['id'] as String,
    name: json['name'] as String,
    direction: PortDirection.values.firstWhere(
      (e) => e.name == json['direction'],
      orElse: () => PortDirection.input,
    ),
    connectedToNodeId: json['connectedToNodeId'] as String?,
  );
}

/// An internal node within a custom component
class InternalNode {
  final String id;
  final String label;
  final ComponentType type;
  final Offset relativePosition;
  final Size size;
  final ComponentConfig config;

  const InternalNode({
    required this.id,
    required this.label,
    required this.type,
    required this.relativePosition,
    this.size = const Size(120, 80), 
    required this.config,
  });

  InternalNode copyWith({
    String? id,
    String? label,
    ComponentType? type,
    Offset? relativePosition,
    Size? size,
    ComponentConfig? config,
  }) {
    return InternalNode(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      relativePosition: relativePosition ?? this.relativePosition,
      size: size ?? this.size,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'relativePosition': {
      'x': relativePosition.dx,
      'y': relativePosition.dy,
    },
    'size': {
      'width': size.width,
      'height': size.height,
    },
    'config': config.toJson(),
  };

  factory InternalNode.fromJson(Map<String, dynamic> json) {
    final posJson = json['relativePosition'] as Map<String, dynamic>;
    final sizeJson = json['size'] as Map<String, dynamic>?;
    return InternalNode(
      id: json['id'] as String,
      label: json['label'] as String,
      type: ComponentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ComponentType.customService,
      ),
      relativePosition: Offset(
        (posJson['x'] as num).toDouble(),
        (posJson['y'] as num).toDouble(),
      ),
      size: sizeJson != null 
          ? Size((sizeJson['width'] as num).toDouble(), (sizeJson['height'] as num).toDouble())
          : const Size(120, 80),
      config: ComponentConfig.fromJson(json['config'] as Map<String, dynamic>),
    );
  }
}

/// A connection between internal nodes
class InternalConnection {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final String? sourcePortId;
  final String? targetPortId;
  final ConnectionType type;
  final String? label;

  const InternalConnection({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.sourcePortId,
    this.targetPortId,
    this.type = ConnectionType.request,
    this.label,
  });

  InternalConnection copyWith({
    String? id,
    String? sourceNodeId,
    String? targetNodeId,
    String? sourcePortId,
    String? targetPortId,
    ConnectionType? type,
    String? label,
  }) {
    return InternalConnection(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      targetPortId: targetPortId ?? this.targetPortId,
      type: type ?? this.type,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceNodeId': sourceNodeId,
    'targetNodeId': targetNodeId,
    'sourcePortId': sourcePortId,
    'targetPortId': targetPortId,
    'type': type.name,
    'label': label,
  };

  factory InternalConnection.fromJson(Map<String, dynamic> json) => InternalConnection(
    id: json['id'] as String,
    sourceNodeId: json['sourceNodeId'] as String,
    targetNodeId: json['targetNodeId'] as String,
    sourcePortId: json['sourcePortId'] as String?,
    targetPortId: json['targetPortId'] as String?,
    type: ConnectionType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ConnectionType.request,
    ),
    label: json['label'] as String?,
  );
}

/// User-defined custom component with internal architecture
class CustomComponentDefinition {
  final String id;
  final String name;
  final String description;
  final int iconCodePoint;        // Material Icons code point
  final String colorHex;          // Accent color as hex string

  // Internal Architecture
  final List<InternalNode> internalNodes;
  final List<InternalConnection> internalConnections;

  // Exposed Ports
  final List<Port> inputPorts;
  final List<Port> outputPorts;

  // Aggregate Config
  final ComponentConfig defaultConfig;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPublished;

  const CustomComponentDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.iconCodePoint = 0xe574, // Icons.extension
    this.colorHex = '#4CAF50',
    this.internalNodes = const [],
    this.internalConnections = const [],
    this.inputPorts = const [],
    this.outputPorts = const [],
    required this.defaultConfig,
    required this.createdAt,
    required this.updatedAt,
    this.isPublished = false,
  });

  /// Get the icon from the code point
  IconData get icon => CustomComponentIcons.resolve(iconCodePoint);

  /// Get the color from hex string
  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  /// Create a new empty custom component
  factory CustomComponentDefinition.empty() {
    final now = DateTime.now();
    return CustomComponentDefinition(
      id: const Uuid().v4(),
      name: 'New Component',
      description: '',
      defaultConfig: ComponentConfig.defaultFor(ComponentType.customService),
      createdAt: now,
      updatedAt: now,
    );
  }

  CustomComponentDefinition copyWith({
    String? id,
    String? name,
    String? description,
    int? iconCodePoint,
    String? colorHex,
    List<InternalNode>? internalNodes,
    List<InternalConnection>? internalConnections,
    List<Port>? inputPorts,
    List<Port>? outputPorts,
    ComponentConfig? defaultConfig,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPublished,
  }) {
    return CustomComponentDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorHex: colorHex ?? this.colorHex,
      internalNodes: internalNodes ?? this.internalNodes,
      internalConnections: internalConnections ?? this.internalConnections,
      inputPorts: inputPorts ?? this.inputPorts,
      outputPorts: outputPorts ?? this.outputPorts,
      defaultConfig: defaultConfig ?? this.defaultConfig,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPublished: isPublished ?? this.isPublished,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'iconCodePoint': iconCodePoint,
    'colorHex': colorHex,
    'internalNodes': internalNodes.map((n) => n.toJson()).toList(),
    'internalConnections': internalConnections.map((c) => c.toJson()).toList(),
    'inputPorts': inputPorts.map((p) => p.toJson()).toList(),
    'outputPorts': outputPorts.map((p) => p.toJson()).toList(),
    'defaultConfig': defaultConfig.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isPublished': isPublished,
  };

  factory CustomComponentDefinition.fromJson(Map<String, dynamic> json) {
    return CustomComponentDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconCodePoint: json['iconCodePoint'] as int? ?? 0xe574,
      colorHex: json['colorHex'] as String? ?? '#4CAF50',
      internalNodes: (json['internalNodes'] as List<dynamic>?)
          ?.map((e) => InternalNode.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      internalConnections: (json['internalConnections'] as List<dynamic>?)
          ?.map((e) => InternalConnection.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      inputPorts: (json['inputPorts'] as List<dynamic>?)
          ?.map((e) => Port.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      outputPorts: (json['outputPorts'] as List<dynamic>?)
          ?.map((e) => Port.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      defaultConfig: json['defaultConfig'] != null
          ? ComponentConfig.fromJson(json['defaultConfig'] as Map<String, dynamic>)
          : ComponentConfig.defaultFor(ComponentType.customService),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
      isPublished: json['isPublished'] as bool? ?? false,
    );
  }

  /// Convert to a formatted JSON string
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parse from a JSON string
  static CustomComponentDefinition fromJsonString(String jsonString) {
    return CustomComponentDefinition.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }
}

/// Mapping for allowed custom component icons (const IconData only)
class CustomComponentIcons {
  static const IconData fallback = Icons.extension;

  static final Map<int, IconData> byCodePoint = {
    Icons.extension.codePoint: Icons.extension,
    Icons.data_object.codePoint: Icons.data_object,
    Icons.storage.codePoint: Icons.storage,
    Icons.settings.codePoint: Icons.settings,
    Icons.network_check.codePoint: Icons.network_check,
    Icons.cloud.codePoint: Icons.cloud,
    Icons.bolt.codePoint: Icons.bolt,
    Icons.security.codePoint: Icons.security,
    Icons.layers.codePoint: Icons.layers,
    Icons.cached.codePoint: Icons.cached,
    Icons.dns.codePoint: Icons.dns,
    Icons.hub_outlined.codePoint: Icons.hub_outlined,
    Icons.api.codePoint: Icons.api,
    Icons.memory.codePoint: Icons.memory,
  };

  static IconData resolve(int codePoint) {
    return byCodePoint[codePoint] ?? fallback;
  }
}
