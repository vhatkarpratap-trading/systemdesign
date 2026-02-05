// Force update
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Types of system components available in the game
enum ComponentType {
  // Traffic & Edge
  // Traffic & Edge
  dns('DNS', 'Traffic routing & domain resolution', Icons.hub_outlined),
  cdn('CDN', 'Cache static content globally', Icons.language_outlined),
  loadBalancer('Load Balancer', 'Distribute traffic across servers', Icons.alt_route), // Updated Icon
  apiGateway('API Gateway', 'Auth, rate limiting, routing', Icons.security_outlined),

  // Compute
  appServer('App Server', 'Business logic processing', Icons.terminal_outlined),
  worker('Worker', 'Async background jobs', Icons.settings_suggest_outlined),
  serverless('Serverless', 'Event-based compute', Icons.bolt_outlined),
  
  // Clients
  client('Users', 'Client traffic source', Icons.devices_outlined),

  // Data Storage
  cache('Cache', 'Hot data caching (Redis)', Icons.speed_outlined),
  database('Database', 'Persistent data storage', Icons.dataset_outlined),
  objectStore('Object Store', 'Files, images, videos', Icons.inventory_2_outlined),

  // Messaging
  queue('Message Queue', 'Async job processing', Icons.layers_outlined),
  pubsub('Pub/Sub', 'Event fanout & notifications', Icons.sensors_outlined),
  stream('Stream', 'Real-time data streaming', Icons.waves_outlined),
  
  // Techniques (New)
  sharding('Sharding', 'Partition data across servers', Icons.grid_view),
  hashing('Hashing', 'Distribute keys uniformly', Icons.tag),
  
  // Infrastructure Primitives
  shardNode('Shard Node', 'Database Shard Unit', Icons.pie_chart_outline),
  partitionNode('Partition Node', 'Table Partition Unit', Icons.table_chart_outlined),
  replicaNode('Replica Node', 'Read Replica Unit', Icons.copy_rounded),
  inputNode('Input Source', 'Data Entry Point', Icons.login),
  outputNode('Output Sink', 'Data Exit Point', Icons.logout),

  // User Components
  customService('Service', 'Your custom microservice', Icons.extension_outlined),
  
  // Excalidraw Sketchy Components
  sketchyService('Sketchy Svc', 'Hand-drawn Service', Icons.draw_outlined),
  sketchyDatabase('Sketchy DB', 'Hand-drawn Database', Icons.draw_outlined),
  sketchyLogic('Sketchy Logic', 'Hand-drawn Logic', Icons.draw_outlined),
  sketchyQueue('Sketchy Queue', 'Hand-drawn Queue', Icons.draw_outlined),
  sketchyClient('Sketchy Client', 'Hand-drawn Client', Icons.draw_outlined),

  // Utilities
  text('Text Note', 'Free text label', Icons.text_fields),
  circle('Circle', 'Geometric circle', Icons.circle_outlined),
  rectangle('Rectangle', 'Geometric rectangle', Icons.crop_square),
  diamond('Diamond', 'Geometric diamond', Icons.change_history_rounded),
  arrow('Arrow', 'Directional arrow', Icons.trending_flat),
  line('Line', 'Straight line', Icons.horizontal_rule);

  final String displayName;
  final String description;
  final IconData icon;

  const ComponentType(this.displayName, this.description, this.icon);

  /// Check if this component has a custom Excalidraw-style renderer
  bool get isSketchy => this == sketchyService || 
                        this == sketchyDatabase || 
                        this == sketchyLogic ||
                        this == sketchyQueue ||
                        this == sketchyClient ||
                        this == rectangle ||
                        this == circle ||
                        this == diamond ||
                        this == arrow ||
                        this == line;

  /// Check if this component can validly connect to [other]
  /// Returns null if valid, or an error message if invalid.
  String? validateConnection(ComponentType other) {
    // 0. Seamless Connections for Sketchy/Geometric Components
    if (this.isSketchy || other.isSketchy) {
      return null; // Always allow
    }

    // 1. Load Balancer Rules
    if (this == ComponentType.loadBalancer) {
      if (other == ComponentType.database || 
          other == ComponentType.cache || 
          other == ComponentType.objectStore ||
          other == ComponentType.queue) {
        return "Load Balancers typically sit before Compute (Servers), not directly connected to Storage or Queues.";
      }
    }

    // 2. Client/Edge to Storage Rules (Security)
    if (this == ComponentType.dns || this == ComponentType.cdn) {
      if (other == ComponentType.database) {
        return "Direct access from Edge/Client to Database is a major security risk. Use an API Gateway or App Server.";
      }
    }

    // 4. API Gateway Rules
    if (this == ComponentType.apiGateway) {
      if (other == ComponentType.database || other == ComponentType.cache) {
        return "API Gateways should route to Services (App Servers, Serverless), not directly to Data Stores.";
      }
    }

    // 5. CDN Rules
    if (this == ComponentType.cdn) {
      if (other == ComponentType.database || other == ComponentType.queue) {
        return "CDNs cache static content from Object Stores or Servers. They don't connect to Databases or Queues directly.";
      }
    }

    // 6. Messaging Rules (Producer -> Queue -> Consumer)
    if (this == ComponentType.queue || this == ComponentType.pubsub || this == ComponentType.stream) {
      if (other == ComponentType.database || other == ComponentType.objectStore || other == ComponentType.cache) {
        return "Queues typically deliver messages to Consumers (Workers/App Servers) which then write to storage.";
      }
      if (other == ComponentType.apiGateway || other == ComponentType.loadBalancer) {
        return "Traffic usually flows *into* Queues from these components,/n or Consumers pull from Queues. Pushing from Queue to LB is unusual.";
      }
    }

    return null; // Valid
  }

  Color get color => switch (this) {
        ComponentType.dns => AppTheme.dnsColor,
        ComponentType.cdn => AppTheme.cdnColor,
        ComponentType.loadBalancer => AppTheme.loadBalancerColor,
        ComponentType.apiGateway => AppTheme.apiGatewayColor,
        ComponentType.appServer => AppTheme.appServerColor,
        ComponentType.worker => AppTheme.workerColor,
        ComponentType.serverless => AppTheme.serverlessColor,
        ComponentType.customService => AppTheme.primary,
        ComponentType.cache => AppTheme.cacheColor,
        ComponentType.database => AppTheme.databaseColor,
        ComponentType.objectStore => AppTheme.objectStoreColor,
        ComponentType.queue => AppTheme.queueColor,
        ComponentType.pubsub => AppTheme.pubsubColor,
        ComponentType.stream => AppTheme.streamColor,
        // Techniques colors
        ComponentType.sharding => Colors.orange,
        ComponentType.hashing => Colors.purpleAccent,
        ComponentType.shardNode => Colors.orangeAccent,
        ComponentType.partitionNode => Colors.deepPurpleAccent,
        ComponentType.replicaNode => Colors.greenAccent,
        ComponentType.inputNode => Colors.cyanAccent,
        ComponentType.outputNode => Colors.pinkAccent,
        ComponentType.client => AppTheme.textPrimary,
        ComponentType.sketchyService => const Color(0xFF881FA3),
        ComponentType.sketchyDatabase => const Color(0xFF0A11D3),
        ComponentType.sketchyLogic => const Color(0xFFC92A2A),
        ComponentType.sketchyQueue => const Color(0xFF087F5B),
        ComponentType.sketchyClient => Colors.black,
        ComponentType.text => Colors.transparent,
        ComponentType.rectangle || 
        ComponentType.circle || 
        ComponentType.diamond ||
        ComponentType.arrow || 
        ComponentType.line => Colors.white,
      };

  /// Category for toolbox organization
  ComponentCategory get category => switch (this) {
        ComponentType.dns ||
        ComponentType.cdn ||
        ComponentType.loadBalancer ||
        ComponentType.apiGateway =>
          ComponentCategory.traffic,
        ComponentType.client ||
        ComponentType.customService => 
          ComponentCategory.user,
        ComponentType.appServer ||
        ComponentType.worker ||
        ComponentType.serverless => 
          ComponentCategory.compute,
        ComponentType.cache ||
        ComponentType.database ||
        ComponentType.objectStore =>
          ComponentCategory.storage,
        ComponentType.queue ||
        ComponentType.pubsub ||
        ComponentType.stream =>
          ComponentCategory.messaging,
        ComponentType.sharding ||
        ComponentType.hashing ||
        ComponentType.shardNode ||
        ComponentType.partitionNode ||
        ComponentType.replicaNode ||
        ComponentType.inputNode ||
        ComponentType.outputNode =>
          ComponentCategory.techniques,
        ComponentType.sketchyService ||
        ComponentType.sketchyDatabase ||
        ComponentType.sketchyLogic ||
        ComponentType.sketchyQueue ||
        ComponentType.sketchyClient => 
          ComponentCategory.sketchy,
        ComponentType.text ||
        ComponentType.rectangle ||
        ComponentType.circle ||
        ComponentType.diamond ||
        ComponentType.arrow ||
        ComponentType.line =>
          ComponentCategory.sketchy,
      };

  /// Common industry technologies for this component type
  List<String> get presets => switch (this) {
        ComponentType.loadBalancer => const ['Nginx', 'HAProxy', 'AWS ELB', 'F5'],
        ComponentType.database => const [
          'PostgreSQL', 'MySQL', 'Oracle', 
          'MongoDB', 'Cassandra', 'DynamoDB', 
          'CockroachDB', 'TiDB'
        ],
        ComponentType.cache => const ['Redis', 'Memcached', 'Hazelcast', 'Varnish'],
        ComponentType.pubsub => const ['Apache Kafka', 'Google Pub/Sub', 'Azure Event Hubs', 'Pulsar'],
        ComponentType.queue => const ['RabbitMQ', 'Amazon SQS', 'ActiveMQ', 'ZeroMQ'],
        ComponentType.objectStore => const ['AWS S3', 'Google Cloud Storage', 'MinIO', 'Azure Blob'],
        ComponentType.cdn => const ['Cloudflare', 'CloudFront', 'Akamai', 'Fastly'],
        ComponentType.apiGateway => const ['Kong', 'Apigee', 'AWS API Gateway', 'Zuul'],
        ComponentType.appServer => const ['Node.js', 'Go (Gin)', 'Java (Spring)', 'Python (FastAPI)'],
        ComponentType.worker => const ['Celery', 'Sidekiq', 'BullMQ', 'Temporal'],
        ComponentType.serverless => const ['AWS Lambda', 'Cloud Functions', 'Azure Functions', 'OpenFaaS'],
        ComponentType.dns => const ['Route53', 'Cloudflare', 'Google Cloud DNS', 'NS1'],
        ComponentType.stream => const ['Apache Flink', 'Spark Streaming', 'Kinesis', 'Storm'],
        ComponentType.sharding => const ['Consistent Hashing', 'Range Based', 'Directory Based'],
        ComponentType.hashing => const ['MD5', 'SHA-256', 'MurmurHash', 'CityHash'],
        ComponentType.client => const ['Mobile App', 'Web Browser', 'IoT Device', 'External Service'],
        _ => const [],
      };
}

/// Categories for organizing components in the toolbox
enum ComponentCategory {
  traffic('Traffic & Edge', Icons.language),
  compute('Compute', Icons.memory),
  storage('Storage', Icons.storage),
  messaging('Messaging', Icons.message),
  user('My Services', Icons.person),
  techniques('Techniques', Icons.lightbulb_outlined), // New Category
  sketchy('Sketchy Library', Icons.brush); 

  final String displayName;
  final IconData icon;

  const ComponentCategory(this.displayName, this.icon);
}

/// Display mode for component visualization depth
enum ComponentDisplayMode {
  collapsed,  // Simple icon view
  expanded,   // Show basic internal structure
  detailed,   // Full PostgreSQL-style detailed view
}

/// Replication type for detailed visualization
enum ReplicationType {
  none,
  synchronous,
  asynchronous,
  streaming,
}

/// Configuration for a single shard in sharded architecture
class ShardConfig {
  final String id;
  final String name;       // "Shard 1"
  final String keyRange;   // "User ID 1-1M"
  final String? shardKey;  // "user_id"
  final bool isPrimary;

  const ShardConfig({
    required this.id,
    required this.name,
    required this.keyRange,
    this.shardKey,
    this.isPrimary = true,
  });

  ShardConfig copyWith({
    String? id,
    String? name,
    String? keyRange,
    String? shardKey,
    bool? isPrimary,
  }) {
    return ShardConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      keyRange: keyRange ?? this.keyRange,
      shardKey: shardKey ?? this.shardKey,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'keyRange': keyRange,
    'shardKey': shardKey,
    'isPrimary': isPrimary,
  };

  factory ShardConfig.fromJson(Map<String, dynamic> json) => ShardConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    keyRange: json['keyRange'] as String,
    shardKey: json['shardKey'] as String?,
    isPrimary: json['isPrimary'] as bool? ?? true,
  );
}

/// Configuration for table partitions
class PartitionConfig {
  final String tableName;     // "orders"
  final String partitionKey;  // "date" or "id"
  final String partitionType; // "range", "list", "hash"
  final List<String> partitions; // ["orders_2024_q1", "orders_2024_q2", ...]

  const PartitionConfig({
    required this.tableName,
    required this.partitionKey,
    this.partitionType = 'range',
    this.partitions = const [],
  });

  PartitionConfig copyWith({
    String? tableName,
    String? partitionKey,
    String? partitionType,
    List<String>? partitions,
  }) {
    return PartitionConfig(
      tableName: tableName ?? this.tableName,
      partitionKey: partitionKey ?? this.partitionKey,
      partitionType: partitionType ?? this.partitionType,
      partitions: partitions ?? this.partitions,
    );
  }

  Map<String, dynamic> toJson() => {
    'tableName': tableName,
    'partitionKey': partitionKey,
    'partitionType': partitionType,
    'partitions': partitions,
  };

  factory PartitionConfig.fromJson(Map<String, dynamic> json) => PartitionConfig(
    tableName: json['tableName'] as String,
    partitionKey: json['partitionKey'] as String,
    partitionType: json['partitionType'] as String? ?? 'range',
    partitions: (json['partitions'] as List<dynamic>?)
        ?.map((e) => e as String).toList() ?? [],
  );
}

/// Configuration for a specific component instance
class ComponentConfig {
  final int capacity; // Max RPS or throughput
  final int instances; // Number of replicas
  final bool autoScale;
  final int minInstances;
  final int maxInstances;
  final String? algorithm; // Load balancing algorithm
  final int cacheTtlSeconds;
  final bool replication;
  final int replicationFactor;
  final String? replicationStrategy; // New: Leader-Follower, Multi-Leader
  final bool sharding; // New: Toggle sharded state
  final String? shardingStrategy;
  final int partitionCount; // New: Number of partitions/shards
  final bool consistentHashing; // New: Toggle consistent hashing
  final List<String> regions;
  final double costPerHour;
  final String? dbSchema;
  final bool showSchema;
  
  // New resilience & traffic properties
  final bool rateLimiting;
  final int? rateLimitRps;
  final bool circuitBreaker;
  final bool retries;
  final bool dlq;
  final int? quorumRead;
  final int? quorumWrite;
  
  // Enhanced architecture visualization
  final ComponentDisplayMode displayMode;
  final List<ShardConfig> shardConfigs;
  final List<PartitionConfig> partitionConfigs;
  final ReplicationType replicationType;

  const ComponentConfig({
    this.capacity = 10000,
    this.instances = 1,
    this.autoScale = false,
    this.minInstances = 1,
    this.maxInstances = 10,
    this.algorithm,
    this.cacheTtlSeconds = 300,
    this.replication = false,
    this.replicationFactor = 1,
    this.replicationStrategy,
    this.sharding = false,
    this.shardingStrategy,
    this.partitionCount = 1,
    this.consistentHashing = false,
    this.regions = const ['us-east-1'],
    this.costPerHour = 0.10,
    this.dbSchema,
    this.showSchema = false,
    this.rateLimiting = false,
    this.rateLimitRps,
    this.circuitBreaker = false,
    this.retries = false,
    this.dlq = false,
    this.quorumRead,
    this.quorumWrite,
    this.displayMode = ComponentDisplayMode.collapsed,
    this.shardConfigs = const [],
    this.partitionConfigs = const [],
    this.replicationType = ReplicationType.none,
  });

  ComponentConfig copyWith({
    int? capacity,
    int? instances,
    bool? autoScale,
    int? minInstances,
    int? maxInstances,
    String? algorithm,
    int? cacheTtlSeconds,
    bool? replication,
    int? replicationFactor,
    String? replicationStrategy,
    bool? sharding,
    String? shardingStrategy,
    int? partitionCount,
    bool? consistentHashing,
    List<String>? regions,
    double? costPerHour,
    String? dbSchema,
    bool? showSchema,
    bool? rateLimiting,
    int? rateLimitRps,
    bool? circuitBreaker,
    bool? retries,
    bool? dlq,
    int? quorumRead,
    int? quorumWrite,
    ComponentDisplayMode? displayMode,
    List<ShardConfig>? shardConfigs,
    List<PartitionConfig>? partitionConfigs,
    ReplicationType? replicationType,
  }) {
    return ComponentConfig(
      capacity: capacity ?? this.capacity,
      instances: instances ?? this.instances,
      autoScale: autoScale ?? this.autoScale,
      minInstances: minInstances ?? this.minInstances,
      maxInstances: maxInstances ?? this.maxInstances,
      algorithm: algorithm ?? this.algorithm,
      cacheTtlSeconds: cacheTtlSeconds ?? this.cacheTtlSeconds,
      replication: replication ?? this.replication,
      replicationFactor: replicationFactor ?? this.replicationFactor,
      replicationStrategy: replicationStrategy ?? this.replicationStrategy,
      sharding: sharding ?? this.sharding,
      shardingStrategy: shardingStrategy ?? this.shardingStrategy,
      partitionCount: partitionCount ?? this.partitionCount,
      consistentHashing: consistentHashing ?? this.consistentHashing,
      regions: regions ?? this.regions,
      costPerHour: costPerHour ?? this.costPerHour,
      dbSchema: dbSchema ?? this.dbSchema,
      showSchema: showSchema ?? this.showSchema,
      rateLimiting: rateLimiting ?? this.rateLimiting,
      rateLimitRps: rateLimitRps ?? this.rateLimitRps,
      circuitBreaker: circuitBreaker ?? this.circuitBreaker,
      retries: retries ?? this.retries,
      dlq: dlq ?? this.dlq,
      quorumRead: quorumRead ?? this.quorumRead,
      quorumWrite: quorumWrite ?? this.quorumWrite,
      displayMode: displayMode ?? this.displayMode,
      shardConfigs: shardConfigs ?? this.shardConfigs,
      partitionConfigs: partitionConfigs ?? this.partitionConfigs,
      replicationType: replicationType ?? this.replicationType,
    );
  }

  /// Get default config for a component type
  static ComponentConfig defaultFor(ComponentType type) {
    return switch (type) {
      ComponentType.dns => const ComponentConfig(
          capacity: 1000000,
          costPerHour: 0.01,
        ),
      ComponentType.cdn => const ComponentConfig(
          capacity: 500000,
          regions: ['us-east-1', 'eu-west-1', 'ap-south-1'],
          costPerHour: 0.05,
        ),
      ComponentType.loadBalancer => const ComponentConfig(
          capacity: 100000,
          algorithm: 'round_robin',
          costPerHour: 0.10,
        ),
      ComponentType.apiGateway => const ComponentConfig(
          capacity: 50000,
          cacheTtlSeconds: 60,
          costPerHour: 0.15,
        ),
      ComponentType.appServer => const ComponentConfig(
          capacity: 1000,
          instances: 2,
          autoScale: true,
          minInstances: 2,
          maxInstances: 20,
          costPerHour: 0.20,
        ),
      ComponentType.worker => const ComponentConfig(
          capacity: 500,
          instances: 2,
          costPerHour: 0.15,
        ),
      ComponentType.serverless => const ComponentConfig(
          capacity: 10000,
          costPerHour: 0.0001,
        ),
      ComponentType.cache => const ComponentConfig(
          capacity: 100000,
          cacheTtlSeconds: 3600,
          costPerHour: 0.08,
        ),
      ComponentType.database => const ComponentConfig(
          capacity: 5000,
          replication: false,
          replicationFactor: 1,
          costPerHour: 0.25,
        ),
      ComponentType.objectStore => const ComponentConfig(
          capacity: 1000000,
          regions: ['us-east-1'],
          costPerHour: 0.02,
        ),
      ComponentType.queue => const ComponentConfig(
          capacity: 100000,
          costPerHour: 0.04,
        ),
      ComponentType.pubsub => const ComponentConfig(
          capacity: 500000,
          costPerHour: 0.05,
        ),
      ComponentType.stream => const ComponentConfig(
          capacity: 100000,
          costPerHour: 0.08,
        ),
      ComponentType.client => const ComponentConfig(
          capacity: 1000,
          costPerHour: 0.0,
        ),
      ComponentType.customService => const ComponentConfig(
          capacity: 5000,
          instances: 1,
          costPerHour: 0.10,
          displayMode: ComponentDisplayMode.detailed,
        ),
      // Configs for sketchy components
      ComponentType.sketchyService || ComponentType.sketchyLogic => const ComponentConfig(
          capacity: 1000,
          instances: 1,
          costPerHour: 0.10,
        ),
      ComponentType.sketchyDatabase => const ComponentConfig(
          capacity: 5000,
          replication: false,
          costPerHour: 0.25,
        ),
      ComponentType.sketchyQueue => const ComponentConfig(
          capacity: 100000,
          costPerHour: 0.04,
        ),
      ComponentType.sketchyClient => const ComponentConfig(
          capacity: 1000,
          costPerHour: 0.0,
        ),
      ComponentType.sharding => const ComponentConfig(
          capacity: 1000000,
          shardingStrategy: 'Consistent Hashing',
          costPerHour: 0.05,
        ),
      ComponentType.hashing => const ComponentConfig(
          capacity: 1000000,
          costPerHour: 0.0,
        ),
      ComponentType.text => const ComponentConfig(
          capacity: 1000,
          costPerHour: 0.0,
        ),
      ComponentType.rectangle || 
      ComponentType.circle || 
      ComponentType.diamond ||
      ComponentType.arrow || 
      ComponentType.line ||
      ComponentType.shardNode ||
      ComponentType.partitionNode ||
      ComponentType.replicaNode ||
      ComponentType.inputNode ||
      ComponentType.outputNode => const ComponentConfig(
          capacity: 1000,
          costPerHour: 0.0,
        ),
    };
  }

  factory ComponentConfig.fromJson(Map<String, dynamic> json) {
    return ComponentConfig(
      capacity: json['capacity'] as int? ?? 10000,
      instances: json['instances'] as int? ?? 1,
      autoScale: json['autoScale'] as bool? ?? false,
      minInstances: json['minInstances'] as int? ?? 1,
      maxInstances: json['maxInstances'] as int? ?? 10,
      algorithm: json['algorithm'] as String?,
      cacheTtlSeconds: json['cacheTtlSeconds'] as int? ?? 300,
      replication: json['replication'] as bool? ?? false,
      replicationFactor: json['replicationFactor'] as int? ?? 1,
      replicationStrategy: json['replicationStrategy'] as String?,
      sharding: json['sharding'] as bool? ?? false,
      shardingStrategy: json['shardingStrategy'] as String?,
      partitionCount: json['partitionCount'] as int? ?? 1,
      consistentHashing: json['consistentHashing'] as bool? ?? false,
      regions: (json['regions'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const ['us-east-1'],
      costPerHour: (json['costPerHour'] as num?)?.toDouble() ?? 0.10,
      dbSchema: json['dbSchema'] as String?,
      showSchema: json['showSchema'] as bool? ?? false,
      rateLimiting: json['rateLimiting'] as bool? ?? false,
      rateLimitRps: json['rateLimitRps'] as int?,
      circuitBreaker: json['circuitBreaker'] as bool? ?? false,
      retries: json['retries'] as bool? ?? false,
      dlq: json['dlq'] as bool? ?? false,
      quorumRead: json['quorumRead'] as int?,
      quorumWrite: json['quorumWrite'] as int?,
      displayMode: ComponentDisplayMode.values.firstWhere(
        (e) => e.name == json['displayMode'],
        orElse: () => ComponentDisplayMode.collapsed,
      ),
      shardConfigs: (json['shardConfigs'] as List<dynamic>?)
          ?.map((e) => ShardConfig.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      partitionConfigs: (json['partitionConfigs'] as List<dynamic>?)
          ?.map((e) => PartitionConfig.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      replicationType: ReplicationType.values.firstWhere(
        (e) => e.name == json['replicationType'],
        orElse: () => ReplicationType.none,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'capacity': capacity,
        'instances': instances,
        'autoScale': autoScale,
        'minInstances': minInstances,
        'maxInstances': maxInstances,
        'algorithm': algorithm,
        'cacheTtlSeconds': cacheTtlSeconds,
        'replication': replication,
        'replicationFactor': replicationFactor,
        'replicationStrategy': replicationStrategy,
        'sharding': sharding,
        'shardingStrategy': shardingStrategy,
        'partitionCount': partitionCount,
        'consistentHashing': consistentHashing,
        'regions': regions,
        'costPerHour': costPerHour,
        'dbSchema': dbSchema,
        'showSchema': showSchema,
        'rateLimiting': rateLimiting,
        'rateLimitRps': rateLimitRps,
        'circuitBreaker': circuitBreaker,
        'retries': retries,
        'dlq': dlq,
        'quorumRead': quorumRead,
        'quorumWrite': quorumWrite,
        'displayMode': displayMode.name,
        'shardConfigs': shardConfigs.map((e) => e.toJson()).toList(),
        'partitionConfigs': partitionConfigs.map((e) => e.toJson()).toList(),
        'replicationType': replicationType.name,
      };
}

/// Runtime metrics for a component
class ComponentMetrics {
  final int currentRps; // Requests per second at this tick
  final double latencyMs; // Average latency
  final double p95LatencyMs; // 95th percentile latency
  final double cpuUsage; // 0.0 to 1.0
  final double memoryUsage; // 0.0 to 1.0
  final double errorRate; // 0.0 to 1.0
  final double cacheHitRate; // For Cache components (0.0 to 1.0)
  final double queueDepth; // For Queue components (number of messages)
  final double jitter; // Latency jitter/variance
  
  // NEW: Resilience metrics
  final double evictionRate; // Evictions/sec
  final bool isThrottled;
  final bool isCircuitOpen;
  
  // NEW: Connection pool metrics
  final double connectionPoolUtilization; // 0.0 to 1.0
  final int activeConnections;
  final int maxConnections;
  
  // NEW: Autoscaling state
  final bool isScaling;
  final int targetInstances;
  final int readyInstances; // Instances fully warmed up
  final int coldStartingInstances; // Instances still warming up
  
  // NEW: Performance indicators
  final bool isSlow; // Is this node performing significantly slower?
  final double slownessFactor; // 1.0 = normal, 10.0 = 10x slower
  
  // NEW: Chaos state
  final bool isCrashed;
  
  // NEW: Glow/Blast tracking
  final int consecutiveGlowTicks;
  final double highLoadSeconds;

  const ComponentMetrics({
    this.currentRps = 0,
    this.latencyMs = 0,
    this.p95LatencyMs = 0,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.errorRate = 0,
    this.cacheHitRate = 0,
    this.queueDepth = 0,
    this.jitter = 0,
    this.evictionRate = 0,
    this.isThrottled = false,
    this.isCircuitOpen = false,
    this.connectionPoolUtilization = 0,
    this.activeConnections = 0,
    this.maxConnections = 100,
    this.isScaling = false,
    this.targetInstances = 1,
    this.readyInstances = 1,
    this.coldStartingInstances = 0,
    this.isSlow = false,
    this.slownessFactor = 1.0,
    this.isCrashed = false,
    this.consecutiveGlowTicks = 0,
    this.highLoadSeconds = 0.0,
  });

  ComponentMetrics copyWith({
    int? currentRps,
    double? latencyMs,
    double? p95LatencyMs,
    double? cpuUsage,
    double? memoryUsage,
    double? errorRate,
    double? cacheHitRate,
    double? queueDepth,
    double? jitter,
    double? evictionRate,
    bool? isThrottled,
    bool? isCircuitOpen,
    double? connectionPoolUtilization,
    int? activeConnections,
    int? maxConnections,
    bool? isScaling,
    int? targetInstances,
    int? readyInstances,
    int? coldStartingInstances,
    bool? isSlow,
    double? slownessFactor,
    bool? isCrashed,
    int? consecutiveGlowTicks,
    double? highLoadSeconds,
  }) {
    return ComponentMetrics(
      currentRps: currentRps ?? this.currentRps,
      latencyMs: latencyMs ?? this.latencyMs,
      p95LatencyMs: p95LatencyMs ?? this.p95LatencyMs,
      cpuUsage: cpuUsage ?? this.cpuUsage,
      memoryUsage: memoryUsage ?? this.memoryUsage,
      errorRate: errorRate ?? this.errorRate,
      cacheHitRate: cacheHitRate ?? this.cacheHitRate,
      queueDepth: queueDepth ?? this.queueDepth,
      jitter: jitter ?? this.jitter,
      evictionRate: evictionRate ?? this.evictionRate,
      isThrottled: isThrottled ?? this.isThrottled,
      isCircuitOpen: isCircuitOpen ?? this.isCircuitOpen,
      connectionPoolUtilization: connectionPoolUtilization ?? this.connectionPoolUtilization,
      activeConnections: activeConnections ?? this.activeConnections,
      maxConnections: maxConnections ?? this.maxConnections,
      isScaling: isScaling ?? this.isScaling,
      targetInstances: targetInstances ?? this.targetInstances,
      readyInstances: readyInstances ?? this.readyInstances,
      coldStartingInstances: coldStartingInstances ?? this.coldStartingInstances,
      isSlow: isSlow ?? this.isSlow,
      slownessFactor: slownessFactor ?? this.slownessFactor,
      isCrashed: isCrashed ?? this.isCrashed,
      consecutiveGlowTicks: consecutiveGlowTicks ?? this.consecutiveGlowTicks,
      highLoadSeconds: highLoadSeconds ?? this.highLoadSeconds,
    );
  }

  /// Calculate component status based on metrics
  ComponentStatus get status {
    if (cpuUsage > 0.95 || errorRate > 0.1) {
      return ComponentStatus.overloaded;
    }
    if (cpuUsage > 0.85 || errorRate > 0.05) {
      return ComponentStatus.critical;
    }
    if (cpuUsage > 0.7 || errorRate > 0.01) {
      return ComponentStatus.warning;
    }
    return ComponentStatus.healthy;
  }

  Map<String, dynamic> toJson() => {
        'currentRps': currentRps,
        'latencyMs': latencyMs,
        'p95LatencyMs': p95LatencyMs,
        'cpuUsage': cpuUsage,
        'memoryUsage': memoryUsage,
        'errorRate': errorRate,
        'cacheHitRate': cacheHitRate,
        'queueDepth': queueDepth,
        'jitter': jitter,
        'evictionRate': evictionRate,
        'isThrottled': isThrottled,
        'isCircuitOpen': isCircuitOpen,
        'connectionPoolUtilization': connectionPoolUtilization,
        'activeConnections': activeConnections,
        'maxConnections': maxConnections,
        'isScaling': isScaling,
        'targetInstances': targetInstances,
        'readyInstances': readyInstances,
        'coldStartingInstances': coldStartingInstances,
        'isSlow': isSlow,
        'slownessFactor': slownessFactor,
        'isCrashed': isCrashed,
        'consecutiveGlowTicks': consecutiveGlowTicks,
      };
}

/// A system component placed on the canvas
class SystemComponent {
  final String id;
  final ComponentType type;
  final Offset position;
  final Size size;
  final ComponentConfig config;
  final ComponentMetrics metrics;

  Offset get center => Offset(position.dx + size.width / 2, position.dy + size.height / 2);

  final bool isSelected;
  final String? customName;
  final String? customComponentId; // Reference to parent custom component definition
  final bool flipX;
  final bool flipY;

  const SystemComponent({
    required this.id,
    required this.type,
    required this.position,
    this.size = const Size(80, 64),
    required this.config,
    this.metrics = const ComponentMetrics(),
    this.isSelected = false,
    this.customName,
    this.customComponentId,
    this.flipX = false,
    this.flipY = false,
  });

  factory SystemComponent.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as Map<String, dynamic>?;
    return SystemComponent(
      id: json['id'] as String,
      type: ComponentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ComponentType.appServer,
      ),
      position: position != null
          ? Offset(
              (position['x'] as num?)?.toDouble() ?? 0.0,
              (position['y'] as num?)?.toDouble() ?? 0.0,
            )
          : Offset.zero,
      size: json['size'] != null 
          ? Size(
              (json['size']['w'] as num?)?.toDouble() ?? 80.0,
              (json['size']['h'] as num?)?.toDouble() ?? 64.0,
            )
          : const Size(80, 64),
      config: ComponentConfig.fromJson(json['config'] as Map<String, dynamic>),
      customName: json['customName'] as String?,
      customComponentId: json['customComponentId'] as String?,
      flipX: json['flipX'] as bool? ?? false,
      flipY: json['flipY'] as bool? ?? false,
    );
  }

  ComponentStatus get status => metrics.status;

  SystemComponent copyWith({
    String? id,
    ComponentType? type,
    Offset? position,
    Size? size,
    ComponentConfig? config,
    ComponentMetrics? metrics,
    bool? isSelected,
    String? customName,
    String? customComponentId,
    bool? flipX,
    bool? flipY,
  }) {
    return SystemComponent(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      size: size ?? this.size,
      config: config ?? this.config,
      metrics: metrics ?? this.metrics,
      isSelected: isSelected ?? this.isSelected,
      customName: customName ?? this.customName,
      customComponentId: customComponentId ?? this.customComponentId,
      flipX: flipX ?? this.flipX,
      flipY: flipY ?? this.flipY,
    );
  }

  /// Calculate total capacity based on instances
  int get totalCapacity => config.capacity * config.instances;

  /// Calculate load percentage
  double get loadPercentage {
    if (totalCapacity == 0) return 0;
    return (metrics.currentRps / totalCapacity).clamp(0.0, 2.0);
  }

  /// Calculate hourly cost
  double get hourlyCost => config.costPerHour * config.instances;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'position': {'x': position.dx, 'y': position.dy},
        'size': {'w': size.width, 'h': size.height},
        'config': config.toJson(),
        'customName': customName,
        'customComponentId': customComponentId,
        'flipX': flipX,
        'flipY': flipY,
      };
}
