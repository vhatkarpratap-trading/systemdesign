import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class DesignDetailsPanel extends StatelessWidget {
  final Map<String, dynamic> design;
  final VoidCallback onDismiss;

  const DesignDetailsPanel({
    super.key,
    required this.design,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final title = design['title'] ?? 'Untitled Design';
    final description = design['description'] ?? 'No description provided.';
    final author = design['profiles']?['display_name'] ?? design['profiles']?['email'] ?? 'Architect';
    final date = DateTime.tryParse(design['created_at'].toString()) ?? DateTime.now();
    
    // Formatting date (Simple)
    final dateStr = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';

    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(5, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
              color: AppTheme.surfaceLight.withOpacity(0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'COMMUNITY DESIGN',
                        style: GoogleFonts.robotoMono(
                          fontSize: 10,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppTheme.textSecondary),
                      onPressed: onDismiss,
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppTheme.border,
                      child: Icon(Icons.person, size: 14, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      author,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: AppTheme.textMuted)),
                    const SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content (Scrollable Blog/Writeup)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DESIGN WRITEUP',
                     style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  // Placeholder for interactions
                  Row(
                    children: [
                      _InteractionBadge(icon: Icons.favorite_border, label: 'Like'),
                      const SizedBox(width: 12),
                      _InteractionBadge(icon: Icons.chat_bubble_outline, label: 'Comment'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractionBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InteractionBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
