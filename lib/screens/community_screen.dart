import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/community_provider.dart';
import '../providers/game_provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../models/community_design.dart';
import '../models/problem.dart';
import '../theme/app_theme.dart';
import '../widgets/community/design_card.dart';
import '../widgets/community/community_sidebar.dart';
import '../utils/blueprint_importer.dart';
import '../utils/blueprint_exporter.dart';
import '../utils/responsive_layout.dart';
import '../data/problems.dart';
import 'game_screen.dart';
import 'dart:convert';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(filteredCommunityDesignsProvider);
    final pendingAsync = ref.watch(pendingDesignsProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isDesktop = ResponsiveLayout.isExpanded(context) || ResponsiveLayout.isMedium(context);
    final designCount = designsAsync.maybeWhen(data: (d) => d.length, orElse: () => 0);
    final avgComplexity = designsAsync.maybeWhen(
      data: (d) => d.isEmpty ? 0.0 : d.map((e) => e.complexity).reduce((a, b) => a + b) / d.length,
      orElse: () => 0.0,
    );
    final avgUpvotes = designsAsync.maybeWhen(
      data: (d) => d.isEmpty ? 0.0 : d.map((e) => e.upvotes).reduce((a, b) => a + b) / d.length,
      orElse: () => 0.0,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SizedBox.expand(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Sidebar (Desktop only)
          if (isDesktop) const CommunitySidebar(),
          
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildDynamicHeader(context, ref, isDesktop, designCount, avgComplexity, avgUpvotes),
                
                // Mobile Category Chips
                if (!isDesktop)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _buildCategoryChip('All', true),
                        _buildCategoryChip('Social Media', false),
                        _buildCategoryChip('E-Commerce', false),
                        _buildCategoryChip('FinTech', false),
                        _buildCategoryChip('Real-time', false),
                      ],
                  ),
                ),
                if (isAdmin)
                  _PendingStrip(pendingAsync: pendingAsync, onTapDesign: (design) => _showDesignDetails(context, ref, design), onApprove: (id) => _moderateDesign(context, ref, id, approve: true), onReject: (id) => _promptReject(context, ref, id)),

                // Design Feed
                Expanded(
                  child: designsAsync.when(
                    data: (designs) => designs.isEmpty 
                      ? _buildEmptyState()
                      : _buildDesignGrid(context, ref, designs, isAdmin),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error loading community: $err')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildDynamicHeader(BuildContext context, WidgetRef ref, bool isDesktop, int designCount, double avgComplexity, double avgUpvotes) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 16, 
        MediaQuery.of(context).padding.top + 24, 
        isDesktop ? 32 : 16, 
        32
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface,
            AppTheme.primary.withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!isDesktop || Navigator.canPop(context)) ...[
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_library_rounded, color: AppTheme.primary, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'Design Library',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Explore innovative system architectures shared by the community.',
                      style: GoogleFonts.inter(
                        fontSize: 16, 
                        color: AppTheme.textSecondary
                      ),
                    ),
                  ],
                ),
              ),
              if (isDesktop) ...[
                SizedBox(
                  width: 320,
                  height: 48,
                  child: _buildSearchField(ref),
                ),
                const SizedBox(width: 24),
                _buildIconButton(Icons.refresh, () => ref.invalidate(communityDesignsProvider)),
              ],
            ],
          ),
          if (!isDesktop) ...[
            const SizedBox(height: 24),
            SizedBox(height: 48, child: _buildSearchField(ref)),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _pillStat(Icons.grid_view_rounded, '$designCount designs'),
              _pillStat(Icons.trending_up_rounded, 'Avg upvotes: ${avgUpvotes.toStringAsFixed(1)}'),
              _pillStat(Icons.layers_rounded, 'Avg complexity: ${avgComplexity.toStringAsFixed(1)}/5'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillStat(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSearchField(WidgetRef ref) {
    return TextField(
      onChanged: (val) => ref.read(communitySearchQueryProvider.notifier).state = val,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search designs, categories...',
        hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        prefixIcon: const Icon(Icons.search, size: 18),
        filled: true,
        fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildDesignGrid(BuildContext context, WidgetRef ref, List<CommunityDesign> designs, bool isAdmin) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = ResponsiveLayout.isExpanded(context);
    final isTablet = ResponsiveLayout.isMedium(context);
    
    int crossAxisCount = 1;
    if (isDesktop) {
      crossAxisCount = 3;
    } else if (isTablet) {
      crossAxisCount = 2;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              _chipFilter(ref, CommunitySort.newest, 'Newest', Icons.fiber_new),
              const SizedBox(width: 8),
              _chipFilter(ref, CommunitySort.upvotes, 'Top Rated', Icons.favorite),
              const SizedBox(width: 8),
              _chipFilter(ref, CommunitySort.complexity, 'Complexity', Icons.layers),
              const Spacer(),
              IconButton(
                onPressed: () => ref.invalidate(communityDesignsProvider),
                icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              childAspectRatio: isDesktop ? 0.85 : (isTablet ? 0.95 : 1.1),
            ),
            itemCount: designs.length,
            itemBuilder: (context, index) {
              final design = designs[index];
              return DesignCard(
                design: design,
                onTap: () => _showDesignDetails(context, ref, design),
                onUpvote: () => ref.read(communityDesignsProvider.notifier).upvote(design.id),
                onSimulate: () => _simulateDesign(context, ref, design),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chipFilter(WidgetRef ref, CommunitySort sort, String label, IconData icon) {
    final current = ref.watch(communitySortProvider);
    final selected = current == sort;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => ref.read(communitySortProvider.notifier).state = sort,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: selected ? Colors.white : AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppTheme.primary : AppTheme.border),
      ),
    );
  }

  Widget _buildCategoryChip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {},
        backgroundColor: AppTheme.surface,
        selectedColor: AppTheme.primary.withValues(alpha: 0.1),
        checkmarkColor: AppTheme.primary,
        side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border),
            ),
            child: Icon(Icons.architecture_rounded, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          const Text(
            'No blueprints found',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or search query',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _showDesignDetails(BuildContext context, WidgetRef ref, CommunityDesign design) {
    final isAdmin = ref.read(isAdminProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCategoryBadge(design.category),
                        const SizedBox(height: 12),
                        Text(
                          design.title,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -1.0),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Conceptualized by ${design.author}',
                          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        _StatusBadge(status: design.status, rejectionReason: design.rejectionReason),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  _buildUpvoteButton(design.upvotes),
                ],
              ),
              
              const SizedBox(height: 40),
              
              _buildSectionTitle('Technical Overview'),
              const SizedBox(height: 12),
              Text(
                design.description,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, height: 1.6),
              ),

              const SizedBox(height: 28),
              _buildSectionTitle('Blog / Deep Dive'),
              const SizedBox(height: 12),
              Text(
                design.blogMarkdown,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.6),
              ),
              
              const SizedBox(height: 40),
              
              _buildSectionTitle('Metrics & Analysis'),
              const SizedBox(height: 16),
              Row(
                children: [
            _buildDetailedMetric('Complexity', '${design.complexity}/5', Icons.psychology),
            const SizedBox(width: 48),
            _buildDetailedMetric('Efficiency', '${(design.efficiency * 100).toInt()}%', Icons.bolt),
          ],
        ),

        const SizedBox(height: 16),
        _ReadOnlyNotice(design: design),
              
              const SizedBox(height: 48),
              
              Row(
                children: [
                  _buildSectionTitle('Discussion'),
                  const Spacer(),
                  Text(
                    '${design.comments.length} comments',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (design.comments.isEmpty)
                _buildEmptyComments()
              else
                ...design.comments.map((c) => _buildCommentItem(c)),
              
              const SizedBox(height: 32),
              _CommentArea(designId: design.id),
              const SizedBox(height: 40),
              if (isAdmin)
                _AdminActions(
                  design: design,
                  onApprove: () => _moderateDesign(context, ref, design.id, approve: true),
                  onReject: () => _promptReject(context, ref, design.id),
                  onDelete: () => _deleteDesign(context, ref, design.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _moderateDesign(BuildContext context, WidgetRef ref, String id, {required bool approve, String? reason}) async {
    final service = SupabaseService();
    try {
      if (approve) {
        await service.approveDesign(id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Design approved and published')));
      } else {
        await service.rejectDesign(id, reason: reason);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Design rejected and author notified')));
      }
      ref.invalidate(communityDesignsProvider);
      ref.invalidate(pendingDesignsProvider);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  void _promptReject(BuildContext context, WidgetRef ref, String id) async {
    final controller = TextEditingController(text: 'Needs more detail on scaling and failure modes.');
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject design'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Why is this rejected?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) {
      _moderateDesign(context, ref, id, approve: false, reason: reason);
    }
  }

  void _deleteDesign(BuildContext context, WidgetRef ref, String id) async {
    try {
      await SupabaseService().deleteDesign(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Design deleted')));
      ref.invalidate(communityDesignsProvider);
      ref.invalidate(pendingDesignsProvider);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Widget _buildCategoryBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildUpvoteButton(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.arrow_upward_rounded, color: AppTheme.primary),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppTheme.textMuted,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildDetailedMetric(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppTheme.textPrimary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyComments() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, style: BorderStyle.none),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('No thoughts shared yet', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildCommentItem(DesignComment comment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.surfaceLight,
            child: Text(comment.author[0].toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 8),
                    Text(
                      _getTimeAgo(comment.createdAt),
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content, 
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'just now';
  }

  void _simulateDesign(BuildContext context, WidgetRef ref, CommunityDesign design) async {
    if (design.canvasData.isEmpty) {
      if (design.blueprintPath == null) return;
      
      // Fetch data on demand
      try {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator()),
        );

        final service = SupabaseService();
        final data = await service.downloadBlueprint(design.blueprintPath!);
        
        Navigator.pop(context); // Dismiss loading

        if (data != null) {
          // Recursively call with hydrated design
          _simulateDesign(
            context, 
            ref, 
            design.copyWith(canvasData: data),
          );
        } else {
          if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Failed to download blueprint')),
             );
          }
        }
      } catch (e) {
        if (context.mounted) Navigator.pop(context); // Dismiss loading on error
        debugPrint('Error fetching blueprint on demand: $e');
      }
      return;
    }

    try {
      final newState = BlueprintImporter.importFromMap(design.canvasData);
      
      // Try to match problem context if stored in design
      // Note: We might want to store problemId in design later
      final problem = Problems.all.firstWhere(
        (p) => p.id == (newState.activeProblemId ?? ''),
        orElse: () => Problems.all.first,
      ); 
      
      ref.read(currentProblemProvider.notifier).state = problem;
      ref.read(canvasProvider.notifier).loadState(newState);
      final user = ref.read(currentUserProvider);
      final isOwner = user != null && design.userId == user.id;
      ref.read(canvasReadOnlyProvider.notifier).state = !isOwner;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            initialCommunityDesign: design.canvasData,
            sharedDesignId: design.id,
            designOwnerId: design.userId,
            readOnly: !isOwner,
          ),
        ),
      );
    } catch (e) {
       debugPrint('Error loading design: $e');
    }
  }
}

class _ReadOnlyNotice extends ConsumerWidget {
  final CommunityDesign design;
  const _ReadOnlyNotice({required this.design});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isOwner = user != null && design.userId == user.id;
    if (isOwner) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This design is read-only. Copy it to your workspace to edit.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            label: const Text('Copy to My Designs'),
            onPressed: () => _copyDesign(context, ref, design),
          ),
        ],
      ),
    );
  }

  Future<void> _copyDesign(BuildContext context, WidgetRef ref, CommunityDesign design) async {
    try {
      final user = SupabaseService().currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to copy designs')));
        return;
      }
      final problem = ref.read(currentProblemProvider);
      final canvasState = BlueprintImporter.importFromMap(design.canvasData);
      final exported = BlueprintExporter.exportToJson(canvasState, problem);
      final id = await SupabaseService().savePrivateDesign(
        title: '${design.title} (copy)',
        description: design.description,
        canvasData: jsonDecode(exported),
        designId: null,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to your designs. Open “My Designs” to edit.')),
      );
      // Optionally auto-open copied design in edit mode
      final imported = BlueprintImporter.importFromMap(design.canvasData);
      ref.read(canvasProvider.notifier).loadState(imported);
      ref.read(canvasReadOnlyProvider.notifier).state = false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copy failed: $e')),
      );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final String? rejectionReason;
  const _StatusBadge({required this.status, this.rejectionReason});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = AppTheme.warning;
        label = 'Pending review';
        break;
      case 'rejected':
        color = AppTheme.error;
        label = 'Rejected';
        break;
      default:
        color = AppTheme.success;
        label = 'Approved';
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        if (status == 'rejected' && rejectionReason != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              rejectionReason!,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminActions extends StatelessWidget {
  final CommunityDesign design;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _AdminActions({
    required this.design,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            const Icon(Icons.admin_panel_settings, color: AppTheme.textMuted, size: 18),
            const SizedBox(width: 8),
            const Text('Admin moderation', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(design.status.toUpperCase(), style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: design.status == 'approved' ? null : onApprove,
              icon: const Icon(Icons.check),
              label: const Text('Approve & Publish'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.close, color: AppTheme.error),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
            ),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.error),
              label: const Text('Delete', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
      ],
    );
  }
}

class _PendingStrip extends StatelessWidget {
  final AsyncValue<List<CommunityDesign>> pendingAsync;
  final void Function(CommunityDesign) onTapDesign;
  final void Function(String) onApprove;
  final void Function(String) onReject;

  const _PendingStrip({
    required this.pendingAsync,
    required this.onTapDesign,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return pendingAsync.when(
      data: (designs) {
        if (designs.isEmpty) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.08),
            border: Border(
              bottom: BorderSide(color: AppTheme.warning.withValues(alpha: 0.3)),
              top: BorderSide(color: AppTheme.warning.withValues(alpha: 0.3)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.pending_actions, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Text('Pending approvals (${designs.length})', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: designs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final d = designs[index];
                    return Container(
                      width: 260,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(d.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(onPressed: () => onTapDesign(d), child: const Text('View')),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: AppTheme.success),
                                tooltip: 'Approve',
                                onPressed: () => onApprove(d.id),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: AppTheme.error),
                                tooltip: 'Reject',
                                onPressed: () => onReject(d.id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// Threaded comment area
class _CommentArea extends ConsumerStatefulWidget {
  final String designId;
  const _CommentArea({super.key, required this.designId});

  @override
  ConsumerState<_CommentArea> createState() => _CommentAreaState();
}

class _CommentAreaState extends ConsumerState<_CommentArea> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  bool _loading = true;
  List<DesignComment> _comments = [];
  String? _replyTo;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final repo = ref.read(communityRepositoryProvider);
    final data = await repo.fetchComments(widget.designId);
    setState(() {
      _comments = data;
      _loading = false;
    });
  }

  List<_ThreadNode> _buildTree() {
    final byParent = <String?, List<DesignComment>>{};
    for (final c in _comments) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    List<_ThreadNode> build(String? pid) {
      final kids = byParent[pid] ?? [];
      return kids.map((c) => _ThreadNode(comment: c, replies: build(c.id))).toList();
    }
    return build(null);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to comment')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.addComment(
        widget.designId,
        DesignComment(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          author: user.email ?? 'You',
          content: text,
          parentId: _replyTo,
          createdAt: DateTime.now(),
        ),
      );
      _controller.clear();
      _replyTo = null;
      await _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tree = _buildTree();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
    if (_loading)
      const LinearProgressIndicator(minHeight: 2)
    else if (tree.isEmpty)
      const _EmptyComments()
    else
      ...tree.map((n) => _ThreadComment(
            node: n,
            depth: 0,
            onReply: (id) => setState(() => _replyTo = id),
              )),
        const SizedBox(height: 12),
        if (_replyTo != null)
          Row(
            children: [
              const Icon(Icons.reply, color: AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text('Replying', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: () => setState(() => _replyTo = null), child: const Text('Cancel')),
            ],
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _replyTo == null ? 'Add to the discussion...' : 'Write a reply...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 16),
                  label: const Text('Post'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyComments extends StatelessWidget {
  const _EmptyComments();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, style: BorderStyle.none),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('No thoughts shared yet', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

class _ThreadNode {
  final DesignComment comment;
  final List<_ThreadNode> replies;
  _ThreadNode({required this.comment, this.replies = const []});
}

class _ThreadComment extends StatelessWidget {
  final _ThreadNode node;
  final int depth;
  final void Function(String) onReply;

  const _ThreadComment({
    required this.node,
    required this.depth,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final c = node.comment;
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.surfaceLight,
                child: Text(
                  c.author.isNotEmpty ? c.author[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.author, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(_timeAgo(c.createdAt), style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              TextButton(onPressed: () => onReply(c.id), child: const Text('Reply', style: TextStyle(fontSize: 12))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            c.content,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.45),
          ),
          if (node.replies.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...node.replies.map((r) => _ThreadComment(node: r, depth: depth + 1, onReply: onReply)),
          ],
        ],
      ),
    );
  }

  static String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
