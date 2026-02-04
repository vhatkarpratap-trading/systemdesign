import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

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
  Future<List<Map<String, dynamic>>> fetchCommunityDesigns() async {
    try {
      final response = await client
          .from('designs')
          .select('*, profiles(display_name, avatar_url)') // Standard left join
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

  /// Publish a design
  Future<void> publishDesign({
    required String title,
    required String description,
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
      'canvas_data': canvasData, // Keep for backup/search if needed
      'blueprint_path': blueprintPath,
      'is_public': true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      if (designId != null) {
        await client.from('designs').update(data).eq('id', designId);
      } else {
        await client.from('designs').insert(data);
      }
    } catch (e) {
      debugPrint('Error publishing design: $e');
      rethrow;
    }
  }
}
