import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService().authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session?.user,
    loading: () => SupabaseService().currentUser,
    error: (_, __) => null,
  );
});

final guestModeProvider = StateProvider<bool>((ref) => false);

final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return null;
  
  // Only fetch if we have an initialized Supabase instance
  if (!SupabaseService.isInitialized) return null;
  
  return SupabaseService().getCurrentProfile();
});
