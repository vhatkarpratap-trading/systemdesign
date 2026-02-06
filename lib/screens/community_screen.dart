import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/community_provider.dart';
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import '../models/community_design.dart';
import '../models/problem.dart';
import '../theme/app_theme.dart';
import '../widgets/community/design_card.dart';
import '../widgets/community/community_sidebar.dart';
import '../utils/blueprint_importer.dart';
import '../utils/responsive_layout.dart';
import '../data/problems.dart';
import 'game_screen.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(filteredCommunityDesignsProvider);
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
                
                // Design Feed
                Expanded(
                  child: designsAsync.when(
                    data: (designs) => designs.isEmpty 
                      ? _buildEmptyState()
                      : _buildDesignGrid(context, ref, designs),
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

  Widget _buildDesignGrid(BuildContext context, WidgetRef ref, List<CommunityDesign> designs) {
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
                onTap: () => _showDesignDetails(context, design),
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

  void _showDesignDetails(BuildContext context, CommunityDesign design) {
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
            ],
          ),
        ),
      ),
    );
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
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            initialCommunityDesign: design.canvasData,
            sharedDesignId: design.id,
          ),
        ),
      );
    } catch (e) {
       debugPrint('Error loading design: $e');
    }
  }
}

// _CommentArea is a stateful widget to manage comment input
class _CommentArea extends ConsumerStatefulWidget {
  final String designId;
  const _CommentArea({super.key, required this.designId});

  @override
  ConsumerState<_CommentArea> createState() => _CommentAreaState();
}

class _CommentAreaState extends ConsumerState<_CommentArea> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(communityDesignsProvider.notifier).addComment(
        widget.designId,
        text,
        'You', // Default author for now
      );
      _controller.clear();
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Add to the discussion...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _submitComment(),
            ),
          ),
          Material(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _isSubmitting ? null : _submitComment,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: _isSubmitting 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
