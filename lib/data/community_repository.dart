import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/community_design.dart';
import '../services/supabase_service.dart';

class CommunityRepository {
  final SupabaseService _supabase = SupabaseService();
  
  Future<List<CommunityDesign>> loadDesigns() async {
    try {
      final data = await _supabase.fetchCommunityDesigns();
      
      return data.map((json) {
        // Map Supabase JSON to CommunityDesign
        return CommunityDesign(
          id: json['id'],
          title: json['title'],
          description: json['description'] ?? '',
          blogMarkdown: json['blog_markdown'] ?? json['description'] ?? '',
          status: json['status'] ?? 'approved',
          rejectionReason: json['rejection_reason'],
          author: json['profiles']?['display_name'] ?? 'Anonymous',
          canvasData: json['canvas_data'] is String ? jsonDecode(json['canvas_data']) : json['canvas_data'],
          category: 'General', // TODO: Add category to DB
          upvotes: json['upvotes'] ?? 0,
          createdAt: DateTime.parse(json['created_at']),
        );
      }).toList();
    } catch (e) {
      // Fallback to featured on error or empty
      return _getFeaturedDesigns();
    }
  }

  Future<List<CommunityDesign>> loadPendingDesigns() async {
    try {
      final data = await _supabase.fetchPendingDesigns();
      return data.map((json) => CommunityDesign.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  // Publish is now handled directly by the UI calling SupabaseService
  // But we can keep this for compatibility if needed, or remove it.
  Future<void> publishDesign(CommunityDesign design) async {
    await _supabase.publishDesign(
      title: design.title,
      description: design.description,
      blogMarkdown: design.blogMarkdown,
      canvasData: design.canvasData,
      designId: null, // Always new for now, or handle updates if design.id exists in DB
    );
  }

  Future<void> upvoteDesign(String id) async {
    // TODO: Implement upvoting in SupabaseService
  }

  Future<void> addComment(String designId, DesignComment comment) async {
    // TODO: Implement comments in SupabaseService
  }

  List<CommunityDesign> _getFeaturedDesigns() {
    return [
      CommunityDesign(
        id: 'feat_1',
        title: 'Scalable Social Feed',
        description: 'A fan-out on write architecture for real-time social updates with Redis caching.',
        blogMarkdown: 'A fan-out on write architecture for real-time social updates with Redis caching.',
        author: 'SystemMaster',
        category: 'Social Media',
        upvotes: 156,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        complexity: 4,
        efficiency: 0.92,
        canvasData: {
  "components": {
    "users": {"id": "users", "type": "client", "position": {"x": 5000, "y": 4800}, "capacity": {"instances": 1, "maxRPSPerInstance": 1000}},
    "lb": {"id": "lb", "type": "load_balancer", "position": {"x": 5250, "y": 4800}, "properties": {"algorithm": "round_robin"}},
    "api_server": {"id": "api_server", "type": "appServer", "position": {"x": 5500, "y": 4800}, "capacity": {"instances": 2, "maxRPSPerInstance": 500}},
    "feed_cache": {"id": "feed_cache", "type": "cache", "position": {"x": 5750, "y": 4700}, "properties": {"engine": "Redis"}},
    "main_db": {"id": "main_db", "type": "database", "position": {"x": 5750, "y": 4900}, "properties": {"engine": "PostgreSQL"}}
  },
  "connections": [
    {"from": "users", "to": "lb", "protocol": "HTTPS"},
    {"from": "lb", "to": "api_server", "protocol": "HTTPS"},
    {"from": "api_server", "to": "feed_cache", "protocol": "TCP"},
    {"from": "api_server", "to": "main_db", "protocol": "TCP"}
  ],
  "viewState": {"panOffset": {"x": -5100, "y": -4850}, "scale": 0.9}
},
      ),
      CommunityDesign(
        id: 'feat_2',
        title: 'High-Availability E-Commerce',
        description: 'Multi-region deployment with SQL read replicas and global CDN.',
        blogMarkdown: 'Multi-region deployment with SQL read replicas and global CDN.',
        author: 'CloudArchitect',
        category: 'E-Commerce',
        upvotes: 89,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        complexity: 3,
        efficiency: 0.95,
        canvasData: {
  "components": {
    "customers": {"id": "customers", "type": "client", "position": {"x": 5000, "y": 5000}},
    "cdn": {"id": "cdn", "type": "cdn", "position": {"x": 5250, "y": 5000}},
    "gateway": {"id": "gateway", "type": "apiGateway", "position": {"x": 5500, "y": 5000}},
    "orders_db": {"id": "orders_db", "type": "database", "position": {"x": 5750, "y": 5000}, "properties": {"replication": "primary-replica"}}
  },
  "connections": [
    {"from": "customers", "to": "cdn", "protocol": "HTTPS"},
    {"from": "cdn", "to": "gateway", "protocol": "HTTPS"},
    {"from": "gateway", "to": "orders_db", "protocol": "TCP"}
  ],
  "viewState": {"panOffset": {"x": -5200, "y": -5000}, "scale": 0.8}
},
      ),
      CommunityDesign(
        id: 'feat_3',
        title: 'Global Microservices',
        description: 'Complex architecture with multiple services, API gateway, and cross-service communication.',
        blogMarkdown: 'Complex architecture with multiple services, API gateway, and cross-service communication.',
        author: 'UberEngineer',
        category: 'Backend',
        upvotes: 212,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        complexity: 5,
        efficiency: 0.88,
        canvasData: {
  "components": {
    "users": {"id": "users", "type": "client", "position": {"x": 5000, "y": 4800}},
    "dns": {"id": "dns", "type": "dns", "position": {"x": 5200, "y": 4800}},
    "lb": {"id": "lb", "type": "load_balancer", "position": {"x": 5400, "y": 4800}},
    "gateway": {"id": "gateway", "type": "apiGateway", "position": {"x": 5600, "y": 4800}},
    
    "auth_svc": {"id": "auth_svc", "type": "appServer", "position": {"x": 5800, "y": 4650}, "name": "Auth Service"},
    "user_svc": {"id": "user_svc", "type": "appServer", "position": {"x": 5800, "y": 4800}, "name": "User Service"},
    "order_svc": {"id": "order_svc", "type": "appServer", "position": {"x": 5800, "y": 4950}, "name": "Order Service"},
    
    "auth_db": {"id": "auth_db", "type": "database", "position": {"x": 6000, "y": 4650}},
    "user_db": {"id": "user_db", "type": "database", "position": {"x": 6000, "y": 4800}},
    "order_db": {"id": "order_db", "type": "database", "position": {"x": 6000, "y": 4950}}
  },
  "connections": [
    {"from": "users", "to": "dns", "protocol": "UDP"},
    {"from": "users", "to": "lb", "protocol": "HTTPS"},
    {"from": "lb", "to": "gateway", "protocol": "HTTPS"},
    {"from": "gateway", "to": "auth_svc", "protocol": "gRPC"},
    {"from": "gateway", "to": "user_svc", "protocol": "gRPC"},
    {"from": "gateway", "to": "order_svc", "protocol": "gRPC"},
    {"from": "auth_svc", "to": "auth_db", "protocol": "TCP"},
    {"from": "user_svc", "to": "user_db", "protocol": "TCP"},
    {"from": "order_svc", "to": "order_db", "protocol": "TCP"}
  ],
  "viewState": {"panOffset": {"x": -5300, "y": -4800}, "scale": 0.8}
},
      ),
      CommunityDesign(
        id: 'feat_4',
        title: 'Real-time Analytics Pipeline',
        description: 'Streaming architecture for processing millions of events per second with persistent storage.',
        blogMarkdown: 'Streaming architecture for processing millions of events per second with persistent storage.',
        author: 'DataWizard',
        category: 'Data Engineering',
        upvotes: 145,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        complexity: 4,
        efficiency: 0.94,
        canvasData: {
  "components": {
    "iot_devices": {"id": "iot_devices", "type": "client", "position": {"x": 5000, "y": 4800}, "name": "IoT Devices"},
    "ingest": {"id": "ingest", "type": "apiGateway", "position": {"x": 5200, "y": 4800}, "name": "Ingestion Layer"},
    "stream": {"id": "stream", "type": "stream", "position": {"x": 5400, "y": 4800}, "name": "Kafka Stream"},
    "worker": {"id": "worker", "type": "worker", "position": {"x": 5600, "y": 4800}, "name": "Flink Processor"},
    "store": {"id": "store", "type": "objectStore", "position": {"x": 5800, "y": 4720}, "name": "Data Lake"},
    "analytics_db": {"id": "analytics_db", "type": "database", "position": {"x": 5800, "y": 4880}, "name": "ClickHouse"}
  },
  "connections": [
    {"from": "iot_devices", "to": "ingest", "protocol": "MQTT"},
    {"from": "ingest", "to": "stream", "protocol": "TCP"},
    {"from": "stream", "to": "worker", "protocol": "TCP"},
    {"from": "worker", "to": "store", "protocol": "HTTPS"},
    {"from": "worker", "to": "analytics_db", "protocol": "TCP"}
  ],
  "viewState": {"panOffset": {"x": -5300, "y": -4800}, "scale": 0.85}
},
      ),
    ];
  }
}
