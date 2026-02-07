import 'dart:convert';

class CommunityDesign {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String blogMarkdown;
  final String author;
  final Map<String, dynamic> canvasData; // Changed from String blueprintJson
  final String? blueprintPath; // Added for storage reference
  final String category;
  final int upvotes;
  final DateTime createdAt;
  final int complexity; // 1-5
  final double efficiency; // 0.0-1.0
  final List<DesignComment> comments;
  final String status;
  final String? rejectionReason;

  CommunityDesign({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.blogMarkdown,
    required this.author,
    required this.canvasData,
    this.blueprintPath,
    this.category = 'General',
    this.upvotes = 0,
    required this.createdAt,
    this.complexity = 3,
    this.efficiency = 0.8,
    this.comments = const [],
    this.status = 'approved',
    this.rejectionReason,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'description': description,
    'blog_markdown': blogMarkdown,
    'author': author,
    'canvas_data': canvasData,
    'blueprint_path': blueprintPath,
    'category': category,
    'upvotes': upvotes,
    'complexity': complexity,
    'efficiency': efficiency,
    'createdAt': createdAt.toIso8601String(),
    'comments': comments.map((c) => c.toJson()).toList(),
    'status': status,
    'rejection_reason': rejectionReason,
  };

  Map<String, dynamic> toMap() => toJson();

  factory CommunityDesign.fromJson(Map<String, dynamic> json) {
    // Handle both old 'blueprintJson' string and new 'canvas_data' Map
    Map<String, dynamic> data = {};
    if (json['canvas_data'] != null) {
      data = json['canvas_data'] is String 
          ? jsonDecode(json['canvas_data']) 
          : Map<String, dynamic>.from(json['canvas_data']);
    } else if (json['blueprintJson'] != null) {
      data = jsonDecode(json['blueprintJson']);
    }

    return CommunityDesign(
      id: json['id'],
      userId: json['user_id'] ?? '',
      title: json['title'],
      description: json['description'] ?? '',
      blogMarkdown: json['blog_markdown'] ?? json['description'] ?? '',
      author: json['profiles']?['display_name'] ?? 'Unknown Architect',
      canvasData: data,
      blueprintPath: json['blueprint_path'],
      category: json['category'] ?? 'General',
      upvotes: json['upvotes'] ?? 0,
      complexity: json['complexity'] ?? 3,
      efficiency: (json['efficiency'] as num?)?.toDouble() ?? 0.8,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      comments: (json['comments'] as List<dynamic>?)
          ?.map((e) => DesignComment.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      status: json['status'] ?? 'approved',
      rejectionReason: json['rejection_reason'],
    );
  }

  CommunityDesign copyWith({
    String? title,
    String? userId,
    String? description,
    String? blogMarkdown,
    int? upvotes,
    List<DesignComment>? comments,
    Map<String, dynamic>? canvasData,
    String? status,
    String? rejectionReason,
  }) {
    return CommunityDesign(
      id: id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      blogMarkdown: blogMarkdown ?? this.blogMarkdown,
      author: author,
      canvasData: canvasData ?? this.canvasData,
      blueprintPath: blueprintPath,
      category: category,
      upvotes: upvotes ?? this.upvotes,
      complexity: this.complexity,
      efficiency: this.efficiency,
      createdAt: createdAt,
      comments: comments ?? this.comments,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}

class DesignComment {
  final String id;
  final String author;
  final String content;
  final String? parentId;
  final DateTime createdAt;

  DesignComment({
    required this.id,
    required this.author,
    required this.content,
    this.parentId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author,
    'content': content,
    'parent_id': parentId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DesignComment.fromJson(Map<String, dynamic> json) => DesignComment(
    id: json['id'],
    author: json['author'],
    content: json['content'],
    parentId: json['parent_id'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}
