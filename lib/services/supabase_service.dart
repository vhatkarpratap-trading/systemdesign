import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static const String adminEmail = 'pratapvhatkar1989@gmail.com';

  SupabaseClient get client => Supabase.instance.client;

  bool get _isSafe => kDebugMode || !kReleaseMode; // Simple proxy for potential test environment if we can't check init

  /// Checks if Supabase is initialized before accessing it
  static bool get isInitialized {
    try {
      Supabase.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Google Sign-In configuration - lazily initialized only on non-web platforms
  /// Web OAuth is handled entirely through Supabase signInWithOAuth
  GoogleSignIn? _googleSignIn;
  GoogleSignIn get _getGoogleSignIn {
    _googleSignIn ??= GoogleSignIn(
      scopes: ['email', 'profile'],
    );
    return _googleSignIn!;
  }

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => isInitialized ? client.auth.onAuthStateChange : const Stream.empty();


  /// Current user
  User? get currentUser {
    if (!isInitialized) return null;
    return client.auth.currentUser;
  }

  bool get isAdmin {
    final email = currentUser?.email?.toLowerCase();
    return email == adminEmail;
  }

  /// Sign in with Google
  /// Returns null if successful, error message otherwise
  Future<String?> signInWithGoogle() async {
    try {
      // WEB: Supabase handles the flow with redirect or popup
      if (kIsWeb) {
        await client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: kDebugMode ? 'http://localhost:8083/' : null, // Callback URL
        );
        return null;
      }

      // MOBILE: Native Google Sign-In flow
      final googleUser = await _getGoogleSignIn.signIn();
      if (googleUser == null) return 'Login canceled';

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) return 'Missing access token';
      if (idToken == null) return 'Missing ID token';

      await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      
      return null;
    } catch (e) {
      return 'Login failed: $e';
    }
  }

  /// Sign in with Email and Password
  Future<String?> signInWithEmail(String email, String password) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Login failed: $e';
    }
  }

  /// Sign up with Email and Password
  Future<String?> signUpWithEmail(String email, String password) async {
    try {
      final response = await client.auth.signUp(email: email, password: password);
      if (response.session == null) {
        return 'Please check your email to confirm your account.';
      }
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Sign up failed: $e';
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await client.auth.signOut();
    if (!kIsWeb) {
      await _getGoogleSignIn.signOut();
    }
  }

  // --- Database Methods ---

  /// Get current user profile (display name, etc)
  Future<Map<String, dynamic>?> getCurrentProfile() async {
    if (!isInitialized) return null;
    final user = currentUser;
    if (user == null) return null;
    
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      return response;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  /// Upload blueprint JSON to Storage
  Future<String> _uploadBlueprint(String userId, String title, Map<String, dynamic> data) async {
    final jsonString = jsonEncode(data);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${title.replaceAll(RegExp(r'\s+'), '_')}.json';
    final path = '$userId/$fileName';
    
    await client.storage.from('blueprints').uploadBinary(
      path,
      Uint8List.fromList(utf8.encode(jsonString)),
      fileOptions: const FileOptions(upsert: true),
    );
    
    return path;
  }

  /// Download blueprint JSON from Storage
  Future<Map<String, dynamic>?> downloadBlueprint(String path) async {
    try {
      final bytes = await client.storage.from('blueprints').download(path);
      final jsonString = utf8.decode(bytes);
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint('Error downloading blueprint: $e');
      return null;
    }
  }

  /// Fetch recently published community designs
  Future<List<Map<String, dynamic>>> fetchCommunityDesigns({bool includePendingForAdmin = false}) async {
    try {
      final response = includePendingForAdmin && isAdmin
          ? await client
              .from('designs')
              .select('*, profiles(display_name, avatar_url)')
              .order('created_at', ascending: false)
              .limit(50)
          : await client
              .from('designs')
              .select('*, profiles(display_name, avatar_url)')
              .eq('status', 'approved')
              .eq('is_public', true)
              .order('created_at', ascending: false)
              .limit(50);
      
      final List<Map<String, dynamic>> results = [];
      
      // Hydrate with storage data if path exists
      for (final item in response) {
        final design = Map<String, dynamic>.from(item);
        
        // Handle missing profile data safely
        if (design['profiles'] == null) {
          design['profiles'] = {'display_name': 'Unknown Architect', 'avatar_url': null};
        }

        if (design['blueprint_path'] != null) {
          final blueprintData = await downloadBlueprint(design['blueprint_path']);
          if (blueprintData != null) {
            design['canvas_data'] = blueprintData;
          }
        }
        results.add(design);
      }

      return results;
    } catch (e) {
      debugPrint('Error fetching community designs: $e');
      if (e is PostgrestException) {
        debugPrint('Postgrest details: ${e.message} - ${e.details}');
      }
      return [];
    }
  }

  /// Comments
  Future<List<Map<String, dynamic>>> fetchComments(String designId) async {
    final resp = await client
        .from('comments')
        .select('id, content, parent_id, created_at, profiles(display_name)')
        .eq('design_id', designId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(resp.map((e) => {
          'id': e['id'],
          'content': e['content'],
          'parent_id': e['parent_id'],
          'createdAt': e['created_at'],
          'author': e['profiles']?['display_name'] ?? 'Anonymous',
        }));
  }

  Future<void> addComment({
    required String designId,
    required String content,
    String? parentId,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be logged in to comment');
    await client.from('comments').insert({
      'design_id': designId,
      'user_id': user.id,
      'content': content,
      'parent_id': parentId,
    });
  }

  /// Publish a design. Returns the design id.
  Future<String> publishDesign({
    required String title,
    required String description,
    String? blogMarkdown,
    required Map<String, dynamic> canvasData,
    required String? designId,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be logged in to publish');

    // Upload to Storage
    final blueprintPath = await _uploadBlueprint(user.id, title, canvasData);

    final data = {
      'user_id': user.id,
      'title': title,
      'description': description,
      'blog_markdown': blogMarkdown ?? description,
      'canvas_data': canvasData, // Keep for backup/search if needed
      'blueprint_path': blueprintPath,
      'is_public': false, // only goes public after approval
      'status': 'pending',
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      if (designId != null) {
        await client.from('designs').update(data).eq('id', designId);
        return designId;
      } else {
        final response = await client.from('designs').insert(data).select('id').single();
        return (response['id'] as String);
      }
    } catch (e) {
      debugPrint('Error publishing design: $e');
      rethrow;
    }
  }

  /// Save a private design under the current user; returns id
  Future<String> savePrivateDesign({
    required String title,
    required String description,
    required Map<String, dynamic> canvasData,
    required String? designId,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be logged in to save');

    // Upload blueprint to storage for durability
    final blueprintPath = await _uploadBlueprint(user.id, title, canvasData);

    final data = {
      'user_id': user.id,
      'title': title,
      'description': description,
      'canvas_data': canvasData,
      'blueprint_path': blueprintPath,
      'is_public': false,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      if (designId != null) {
        await client.from('designs').update(data).eq('id', designId).eq('user_id', user.id);
        return designId;
      } else {
        final response = await client.from('designs').insert(data).select('id').single();
        return (response['id'] as String);
      }
    } catch (e) {
      debugPrint('Error saving private design: $e');
      rethrow;
    }
  }

  /// Fetch private designs for the current user (lightweight)
  Future<List<Map<String, dynamic>>> fetchMyDesigns() async {
    final user = currentUser;
    if (user == null) throw Exception('Must be logged in');
    try {
      final resp = await client
          .from('designs')
          .select('id, title, description, blog_markdown, status, rejection_reason, updated_at, created_at, blueprint_path, canvas_data, is_public')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(resp);
    } catch (e) {
      debugPrint('fetchMyDesigns error: $e');
      return [];
    }
  }

  /// Fetch pending designs (admin only)
  Future<List<Map<String, dynamic>>> fetchPendingDesigns() async {
    if (!isAdmin) throw Exception('Admin only');
    try {
      final resp = await client
          .from('designs')
          .select('*, profiles(display_name, avatar_url)')
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(resp);
    } catch (e) {
      debugPrint('fetchPendingDesigns error: $e');
      return [];
    }
  }

  Future<void> approveDesign(String id) async {
    if (!isAdmin) throw Exception('Admin only');
    await client.from('designs').update({
      'status': 'approved',
      'is_public': true,
      'rejection_reason': null,
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> rejectDesign(String id, {String? reason}) async {
    if (!isAdmin) throw Exception('Admin only');
    await client.from('designs').update({
      'status': 'rejected',
      'is_public': false,
      'rejection_reason': reason ?? 'Not approved by moderator',
    }).eq('id', id);
  }

  Future<void> deleteDesign(String id) async {
    final user = currentUser;
    if (user == null) throw Exception('Must be logged in');
    // RLS will enforce ownership or admin privileges
    await client.from('designs').delete().eq('id', id);
  }

  /// Fetch a shared design by id; returns canvas data map or null.
  Future<Map<String, dynamic>?> fetchDesignById(String id) async {
    try {
      final resp = await client
          .from('designs')
          .select('canvas_data, blueprint_path')
          .eq('id', id)
          .single();

      if (resp['canvas_data'] != null) {
        return Map<String, dynamic>.from(resp['canvas_data'] as Map);
      }

      if (resp['blueprint_path'] != null) {
        final blueprint = await downloadBlueprint(resp['blueprint_path']);
        if (blueprint != null) return blueprint;
      }
    } catch (e) {
      debugPrint('fetchDesignById error: $e');
    }
    return null;
  }
}
