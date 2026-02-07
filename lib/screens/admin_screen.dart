import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/community_provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/blueprint_importer.dart';
import 'game_screen.dart';
import '../models/community_design.dart';
import '../widgets/community/design_card.dart';

/// Admin-only providers
final adminDesignsProvider = FutureProvider<List<CommunityDesign>>((ref) async {
  final repo = ref.watch(communityRepositoryProvider);
  final isAdmin = ref.watch(isAdminProvider);
  final user = ref.watch(currentUserProvider);
  if (!isAdmin) return [];
  return repo.loadDesigns(includePendingForAdmin: true, includeMineUserId: user?.id);
});

final adminPendingProvider = FutureProvider<List<CommunityDesign>>((ref) async {
  final designs = await ref.watch(adminDesignsProvider.future);
  return designs.where((d) => (d.status != 'approved') && (d.status != 'draft')).toList();
});

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          title: const Text('Admin Panel', style: TextStyle(color: AppTheme.textPrimary)),
        ),
        body: const Center(
          child: Text('Admin access required', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    final pendingAsync = ref.watch(adminPendingProvider);
    final designsAsync = ref.watch(adminDesignsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Admin Panel', style: TextStyle(color: AppTheme.textPrimary)),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(pendingDesignsProvider);
              ref.invalidate(communityDesignsProvider);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pending Approvals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            pendingAsync.when(
              data: (list) => list.isEmpty
                  ? const Text('No pending designs', style: TextStyle(color: AppTheme.textMuted))
                  : Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: list
                          .map((d) => SizedBox(
                                width: 320,
                                child: _AdminCard(
                                  design: d,
                                  onApprove: () => _moderate(context, ref, d.id, true),
                                  onReject: () => _moderate(context, ref, d.id, false),
                                  onLoad: () => _loadOnCanvas(context, d),
                                ),
                              ))
                          .toList(),
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppTheme.error)),
            ),
            const SizedBox(height: 24),
            const Text('Approved/Public & Your Designs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            designsAsync.when(
              data: (list) => list.isEmpty
                  ? const Text('No designs found', style: TextStyle(color: AppTheme.textMuted))
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.2,
                      ),
                      itemBuilder: (context, i) {
                        final design = list[i];
                        return DesignCard(
                          design: design,
                          onTap: () {},
                          onUpvote: () {},
                          onSimulate: () => _loadOnCanvas(context, design),
                        );
                      },
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moderate(BuildContext context, WidgetRef ref, String id, bool approve) async {
    try {
      if (approve) {
        await SupabaseService().approveDesign(id);
      } else {
        await SupabaseService().rejectDesign(id, reason: 'Not approved');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Approved' : 'Rejected')),
      );
      ref.invalidate(pendingDesignsProvider);
      ref.invalidate(communityDesignsProvider);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _loadOnCanvas(BuildContext context, CommunityDesign design) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          initialCommunityDesign: design.canvasData,
          sharedDesignId: design.id,
          designOwnerId: design.userId,
          readOnly: false, // admin can edit
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final CommunityDesign design;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onLoad;
  const _AdminCard({required this.design, required this.onApprove, required this.onReject, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    final status = (design.status.isEmpty ? 'pending' : design.status).toUpperCase();
    Color statusColor;
    switch (design.status) {
      case 'approved':
        statusColor = AppTheme.success;
        break;
      case 'rejected':
        statusColor = AppTheme.error;
        break;
      case 'draft':
        statusColor = AppTheme.textMuted;
        break;
      default:
        statusColor = AppTheme.warning;
    }
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.border)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(design.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 11)),
            ),
            const SizedBox(height: 4),
            Text(design.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const Spacer(),
            Row(
              children: [
                TextButton(onPressed: onLoad, child: const Text('Load on Canvas')),
                const Spacer(),
                IconButton(onPressed: onApprove, icon: const Icon(Icons.check_circle, color: AppTheme.success)),
                IconButton(onPressed: onReject, icon: const Icon(Icons.cancel, color: AppTheme.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
