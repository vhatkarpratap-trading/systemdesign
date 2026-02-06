import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/community_design.dart';
import '../data/community_repository.dart';

enum CommunitySort { newest, upvotes, complexity }

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

// Sort provider
final communitySortProvider = StateProvider<CommunitySort>((ref) => CommunitySort.newest);

// Filtered designs
final filteredCommunityDesignsProvider = Provider<AsyncValue<List<CommunityDesign>>>((ref) {
  final designsAsync = ref.watch(communityDesignsProvider);
  final query = ref.watch(communitySearchQueryProvider).toLowerCase();
  final sort = ref.watch(communitySortProvider);

  return designsAsync.whenData((designs) {
    var result = designs;

    if (query.isNotEmpty) {
      result = result.where((d) => 
      d.title.toLowerCase().contains(query) || 
      d.description.toLowerCase().contains(query) ||
      d.category.toLowerCase().contains(query)
      ).toList();
    }

    result = [...result]; // copy before sort
    switch (sort) {
      case CommunitySort.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case CommunitySort.upvotes:
        result.sort((a, b) => b.upvotes.compareTo(a.upvotes));
        break;
      case CommunitySort.complexity:
        result.sort((a, b) => b.complexity.compareTo(a.complexity));
        break;
    }

    return result;
  });
});
