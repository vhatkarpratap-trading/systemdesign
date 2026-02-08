import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';

class PublishScreen extends ConsumerStatefulWidget {
  final String initialTitle;
  final Map<String, dynamic> canvasData;

  const PublishScreen({
    super.key,
    required this.initialTitle,
    required this.canvasData,
  });

  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  late TextEditingController _titleController;
  final _descController = TextEditingController();
  bool _isPublishing = false;
  bool _submitForReview = true;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descController.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    final text = _descController.text.trim();
    if (text.isEmpty) {
      setState(() => _wordCount = 0);
      return;
    }
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    setState(() => _wordCount = words);
  }

  Future<void> _handlePublish() async {
    final title = _titleController.text.trim();
    final description = _descController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      if (_submitForReview) {
        await SupabaseService().publishDesign(
          title: title,
          description: description,
          blogMarkdown: description.isEmpty ? null : description,
          canvasData: widget.canvasData,
          designId: null, // Always new for now
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Submitted for review. We will publish once approved.'),
              backgroundColor: AppTheme.warning,
            ),
          );
          Navigator.pop(context); // Return to GameScreen
        }
      } else {
        await SupabaseService().savePrivateDesign(
          title: title,
          description: description,
          blogMarkdown: description.isEmpty ? null : description,
          canvasData: widget.canvasData,
          designId: null,
          status: 'draft',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved privately as draft. You can publish later.'),
              backgroundColor: AppTheme.surfaceLight,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Publish Design', style: GoogleFonts.outfit(color: AppTheme.textPrimary)),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header / Info
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Submit for Review',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'An admin will review and approve before it goes live in the library. Add a detailed blog to speed up approval.',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // Title Input
                Text('DESIGN TITLE', style: _labelStyle),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                  decoration: _inputDecoration('e.g., Scalable System Design'),
                ),

                const SizedBox(height: 24),

                // Review toggle
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Submit for community review'),
                  subtitle: const Text('Turn off to save as a private draft (not published)'),
                  value: _submitForReview,
                  onChanged: (v) => setState(() => _submitForReview = v),
                  activeColor: AppTheme.primary,
                ),

                const SizedBox(height: 12),

                // Description Input
                Text('WRITEUP / BLOG', style: _labelStyle),
                const SizedBox(height: 8),
                _BlogEditorCard(
                  controller: _descController,
                  wordCount: _wordCount,
                  onOpenFullScreen: _openFullScreenEditor,
                ),

                const SizedBox(height: 40),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      height: 48,
                      width: 160,
                      child: ElevatedButton(
                        onPressed: _isPublishing ? null : _handlePublish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isPublishing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('PUBLISH NOW', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _labelStyle => GoogleFonts.robotoMono(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: AppTheme.textMuted,
    letterSpacing: 1.0,
  );

  Future<void> _openFullScreenEditor() async {
    final updated = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _FullPageBlogEditor(initialText: _descController.text),
        fullscreenDialog: true,
      ),
    );
    if (updated != null) {
      _descController.text = updated;
      _updateWordCount();
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textMuted),
      filled: true,
      fillColor: AppTheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

class _BlogEditorCard extends StatelessWidget {
  final TextEditingController controller;
  final int wordCount;
  final VoidCallback onOpenFullScreen;

  const _BlogEditorCard({
    required this.controller,
    required this.wordCount,
    required this.onOpenFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.height * 0.55).clamp(320.0, 700.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: h,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'Optional: Describe your architecture, tradeoffs, and design decisions...',
              hintStyle: TextStyle(color: AppTheme.textMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('$wordCount words', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const Spacer(),
            TextButton.icon(
              onPressed: onOpenFullScreen,
              icon: const Icon(Icons.fullscreen, size: 18),
              label: const Text('Open full-page editor'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ),
      ],
    );
  }
}

class _FullPageBlogEditor extends StatefulWidget {
  final String initialText;
  const _FullPageBlogEditor({required this.initialText});

  @override
  State<_FullPageBlogEditor> createState() => _FullPageBlogEditorState();
}

class _FullPageBlogEditorState extends State<_FullPageBlogEditor> {
  late TextEditingController _controller;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_recount);
    _recount();
  }

  void _recount() {
    final text = _controller.text.trim();
    setState(() {
      _wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Full-page Blog Editor', style: TextStyle(color: AppTheme.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Save & Close'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, height: 1.55),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  hintText: 'Write your full blog here...',
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Text('$_wordCount words', style: const TextStyle(color: AppTheme.textSecondary)),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, _controller.text),
                  child: const Text('Save & Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
