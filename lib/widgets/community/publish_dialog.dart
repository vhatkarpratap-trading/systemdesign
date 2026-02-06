import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/community_design.dart';
import '../../providers/community_provider.dart';
import '../../providers/game_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/blueprint_exporter.dart';
import '../../models/problem.dart';

class PublishDesignDialog extends ConsumerStatefulWidget {
  final Problem problem;
  
  const PublishDesignDialog({super.key, required this.problem});

  @override
  ConsumerState<PublishDesignDialog> createState() => _PublishDesignDialogState();
}

class _PublishDesignDialogState extends ConsumerState<PublishDesignDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'General';
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.problem.title;
    _descriptionController.text = widget.problem.description;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Publish to Community'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Share your system design with other architects. Others will be able to view, simulate, and review your architecture.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Design Title',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: ['General', 'Social Media', 'E-Commerce', 'FinTech', 'Real-time']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) => setState(() => _category = val!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description / Documentation',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (val) => val == null || val.isEmpty ? 'Please enter a description' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPublishing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isPublishing ? null : _handlePublish,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: _isPublishing 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Publish Design'),
        ),
      ],
    );
  }

  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isPublishing = true);

    try {
      final canvasState = ref.read(canvasProvider);
      final blueprintJson = BlueprintExporter.exportToJson(canvasState, widget.problem);
      final canvasData = jsonDecode(blueprintJson);
      
      final design = CommunityDesign(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text,
        description: _descriptionController.text,
        blogMarkdown: _descriptionController.text,
        author: 'You', // In a real app, this would be the logged-in user's name
        canvasData: canvasData,
        category: _category,
        createdAt: DateTime.now(),
      );

      await ref.read(communityDesignsProvider.notifier).publish(design);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        // Failed to publish - removed snackbar
      }
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }
}
