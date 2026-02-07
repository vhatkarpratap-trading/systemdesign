/// A connection between two components
class Connection {
  final String id;
  final String sourceId;
  final String targetId;
  final ConnectionType type;
  final ConnectionDirection direction;
  final ConnectionProtocol protocol;
  final double trafficFlow; // Current traffic through connection (0.0-1.0)
  final String? label; // Optional user-defined pill label
  final bool isActive;

  const Connection({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.type = ConnectionType.request,
    this.direction = ConnectionDirection.unidirectional,
    this.protocol = ConnectionProtocol.http,
    this.trafficFlow = 0.0,
    this.label,
    this.isActive = true,
  });

  Connection copyWith({
    String? id,
    String? sourceId,
    String? targetId,
    ConnectionType? type,
    ConnectionDirection? direction,
    ConnectionProtocol? protocol,
    double? trafficFlow,
    String? label,
    bool? isActive,
  }) {
    return Connection(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      targetId: targetId ?? this.targetId,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      protocol: protocol ?? this.protocol,
      trafficFlow: trafficFlow ?? this.trafficFlow,
      label: label ?? this.label,
      isActive: isActive ?? this.isActive,
    );
  }

  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String,
      targetId: json['targetId'] as String,
      type: ConnectionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ConnectionType.request,
      ),
      direction: ConnectionDirection.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => ConnectionDirection.unidirectional,
      ),
      protocol: ConnectionProtocol.values.firstWhere(
        (e) => e.name == (json['protocol'] as String?),
        orElse: () => ConnectionProtocol.http,
      ),
      trafficFlow: (json['trafficFlow'] as num?)?.toDouble() ?? 0.0,
      label: json['label'] as String?,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'targetId': targetId,
        'type': type.name,
        'direction': direction.name,
        'protocol': protocol.name,
        'trafficFlow': trafficFlow,
        'label': label,
        'isActive': isActive,
      };
}

/// Types of connections between components
enum ConnectionType {
  request('Request', 'Synchronous request flow'),
  response('Response', 'Response data flow'),
  replication('Replication', 'Data replication'),
  async('Async', 'Asynchronous message');

  final String displayName;
  final String description;

  const ConnectionType(this.displayName, this.description);
}

/// Direction of data flow
enum ConnectionDirection {
  unidirectional('One-way', '→'),
  bidirectional('Two-way', '⟷');

  final String displayName;
  final String symbol;

  const ConnectionDirection(this.displayName, this.symbol);
}

/// Transport / protocol for the connection
enum ConnectionProtocol {
  http('HTTP'),
  grpc('gRPC'),
  websocket('WebSocket'),
  tcp('TCP'),
  udp('UDP'),
  custom('Custom');

  final String label;
  const ConnectionProtocol(this.label);
}
