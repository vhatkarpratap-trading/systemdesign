import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/community_design.dart';
import '../data/community_repository.dart';

final communityRepositoryProvider = Provider((ref) => CommunityRepository());

final communityDesignsProvider = AsyncNotifierProvider<CommunityDesignsNotifier, List<CommunityDesign>>(() {
  return CommunityDesignsNotifier();
});

class CommunityDesignsNotifier extends AsyncNotifier<List<CommunityDesign>> {
  @override
  Future<List<CommunityDesign>> build() async {
    final repo = ref.watch(communityRepositoryProvider);
    return repo.loadDesigns();
  }

  Future<void> publish(CommunityDesign design) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.publishDesign(design);
      state = AsyncValue.data(await repo.loadDesigns());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upvote(String id) async {
    final repo = ref.read(communityRepositoryProvider);
    await repo.upvoteDesign(id);
    
    // Optimistic UI or just reload? Let's reload for now
    final designs = await repo.loadDesigns();
    state = AsyncValue.data(designs);
  }

  Future<void> addComment(String designId, String content, String author) async {
    final repo = ref.read(communityRepositoryProvider);
    final comment = DesignComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: author,
      content: content,
      createdAt: DateTime.now(),
    );
    await repo.addComment(designId, comment);
    
    final designs = await repo.loadDesigns();
    state = AsyncValue.data(designs);
  }
}

// Search provider
final communitySearchQueryProvider = StateProvider<String>((ref) => '');

// Filtered designs
final filteredCommunityDesignsProvider = Provider<AsyncValue<List<CommunityDesign>>>((ref) {
  final designsAsync = ref.watch(communityDesignsProvider);
  final query = ref.watch(communitySearchQueryProvider).toLowerCase();

  return designsAsync.whenData((designs) {
    if (query.isEmpty) return designs;
    return designs.where((d) => 
      d.title.toLowerCase().contains(query) || 
      d.description.toLowerCase().contains(query) ||
      d.category.toLowerCase().contains(query)
    ).toList();
  });
});
