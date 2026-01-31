import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';
import '../providers/auth_provider.dart';
import '../simulation/simulation_engine.dart';
import '../models/problem.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import '../widgets/canvas/system_canvas.dart';
import '../widgets/toolbox/component_toolbox.dart';
import '../widgets/metrics/metrics_panel.dart';
import '../widgets/panels/hints_panel.dart';
import '../widgets/simulation/failure_overlay.dart'; // Import FailureOverlay
import '../simulation/design_validator.dart';
import 'results_screen.dart';
import '../widgets/panels/guide_overlay.dart';
import '../utils/blueprint_exporter.dart';
import '../utils/blueprint_importer.dart';
import '../utils/file_utils.dart';
import '../widgets/community/publish_dialog.dart';
import '../widgets/canvas/drawing_toolbar.dart';
import 'community_screen.dart';
import '../data/problems.dart';
import '../services/ai_assist_service.dart'; // Import service
import 'package:shared_preferences/shared_preferences.dart'; // For API key persistence

import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'publish_screen.dart';
import 'dart:ui'; // For BackdropFilter

/// Main gameplay screen
class GameScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialCommunityDesign;

  const GameScreen({
    super.key,
    this.initialCommunityDesign,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  bool _showHints = false;
  bool _showGuide = false;
  Offset? _toolbarPosition;

  Map<String, dynamic>? _activeCommunityDesign;

  @override
  void initState() {
    super.initState();
    
    // Initialize with community design if passed
    if (widget.initialCommunityDesign != null) {
      _activeCommunityDesign = widget.initialCommunityDesign;
    }

    // Initialize canvas with the current problem and handle auto-guide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activeCommunityDesign != null && _activeCommunityDesign!['canvas_data'] != null) {
        // Load passed design
        try {
          final data = _activeCommunityDesign!['canvas_data'];
          final mapData = data is String ? jsonDecode(data) : data as Map<String, dynamic>;
          final state = BlueprintImporter.importFromMap(mapData);
          
           // Match problem if possible
          if (state.activeProblemId != null) {
            final problem = Problems.all.firstWhere(
              (p) => p.id == state.activeProblemId,
              orElse: () => Problems.all.first,
            );
            ref.read(currentProblemProvider.notifier).state = problem;
          }
          
          ref.read(canvasProvider.notifier).loadState(state);
        } catch (e) {
          debugPrint('Error initializing from community design: $e');
          // Fallback
          final problem = ref.read(currentProblemProvider);
          ref.read(canvasProvider.notifier).initializeWithProblem(problem.id);
        }
      } else {
        // Default initialization
        final problem = ref.read(currentProblemProvider);
        ref.read(canvasProvider.notifier).initializeWithProblem(problem.id);
      }
      
      if (ref.read(canvasProvider).components.isEmpty) {
        setState(() => _showGuide = true);
      }
    });
  }

  void _showSaveDesignDialog() {
    final controller = TextEditingController(
      text: ref.read(canvasProvider.notifier).currentDesignName ?? '',
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Save Design', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Design Name',
            labelStyle: TextStyle(color: AppTheme.textSecondary),
            hintText: 'e.g., My System Design v1',
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.textMuted)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final problem = ref.read(currentProblemProvider);
                await ref.read(canvasProvider.notifier).saveAs(name, problem.id);
                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showDesignsGallery() async {
    final designs = await ref.read(canvasProvider.notifier).listDesigns();
    
    if (!mounted) return;

    if (designs.isEmpty) {
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                'My Designs',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: designs.length,
                itemBuilder: (context, index) {
                  final design = designs[index];
                  return ListTile(
                    leading: const Icon(Icons.architecture, color: AppTheme.primary),
                    title: Text(design.name, style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: Text(
                      '${design.problemId} • ${design.timestamp.toString().split('.')[0]}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                      onPressed: () async {
                        await ref.read(canvasProvider.notifier).deleteDesign(design.id);
                        Navigator.pop(context);
                        _showDesignsGallery(); // Refresh
                      },
                    ),
                    onTap: () async {
                      await ref.read(canvasProvider.notifier).loadSavedDesign(design);
                      // Update problem context so header shows correct title/constraints
                      final problem = Problems.all.firstWhere(
                        (p) => p.id == design.problemId,
                        orElse: () => Problems.all.first,
                      );
                      ref.read(currentProblemProvider.notifier).state = problem;
                      
                      if (mounted) Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePublishDesign() async {
    // 1. Check Auth (Placeholder logic for now)
    final user = SupabaseService().currentUser;
    if (user == null) {
      // Show Login Screen
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      
      if (loggedIn != true) return; // User canceled
      
      // Wait a tick for auth state to propagate if needed (though usually immediate)
      if (SupabaseService().currentUser == null) {
        debugPrint('Login reported success but currentUser is null');
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Authentication failed. Please try again.')),
           );
        }
        return;
      }
    }

    // 2. Prepare for Publish
    try {
      final currentTitle = ref.read(canvasProvider.notifier).currentDesignName ?? '';
      
      // Serialize real canvas data
      final canvasState = ref.read(canvasProvider);
      final problem = ref.read(currentProblemProvider);
      final jsonString = BlueprintExporter.exportToJson(canvasState, problem);
      
      if (jsonString.isEmpty) throw Exception('Exported JSON is empty');
      final canvasData = jsonDecode(jsonString);

      if (!mounted) return;

      // 3. Navigate to Publish Screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PublishScreen(
            initialTitle: currentTitle,
            canvasData: canvasData,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error handling publish: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error resolving design: $e')),
        );
      }
    }
  }

  Future<void> _handleAiAnalysis(BuildContext context, WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    String? apiKey = prefs.getString('gemini_api_key');

    // 1. Prompt for API Key if missing (and no demo key)
    if ((apiKey == null || apiKey.isEmpty) && !AiAssistService.hasDemoKey) {
        if (!mounted) return;
        apiKey = await _showApiKeyDialog(context);
        if (apiKey == null || apiKey.isEmpty) return; // User cancelled
        await prefs.setString('gemini_api_key', apiKey);
    }

    if (!mounted) return;

    // 2. Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: AppTheme.surface,
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing Design with AI...', style: TextStyle(color: AppTheme.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 3. Serialize Design
      final canvasState = ref.read(canvasProvider);
      final problem = ref.read(currentProblemProvider);
      final jsonString = BlueprintExporter.exportToJson(canvasState, problem);
      final designData = jsonDecode(jsonString);

      // 4. Call Service
      final service = AiAssistService(apiKey: apiKey);
      final result = await service.analyzeDesign(designData: designData, problem: problem);

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      // 5. Show Result
      _showAnalysisResults(context, result);

    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<String?> _showApiKeyDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Enter Gemini API Key', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To analyze your design, we need a standard Gemini API Key. It is stored locally on your device.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Paste API Key here',
                filled: true,
                fillColor: AppTheme.surfaceLight,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ANALYZE'),
          ),
        ],
      ),
    );
  }

  void _showAnalysisResults(BuildContext context, AiAnalysisResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
             Icon(
               result.score > 70 ? Icons.check_circle : Icons.warning_amber,
               color: result.score > 70 ? AppTheme.success : AppTheme.warning,
             ),
             const SizedBox(width: 8),
             Text('Design Score: ${result.score}/100', style: const TextStyle(color: AppTheme.textPrimary)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Summary
                Text(result.summary, style: const TextStyle(color: AppTheme.textSecondary, height: 1.5)),
                const SizedBox(height: 16),
                
                // Issues
                if (result.issues.isNotEmpty) ...[
                  const Text('CRITICAL ISSUES', 
                    style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  ...result.issues.map((issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppTheme.error)),
                        Expanded(child: Text(issue, style: const TextStyle(color: AppTheme.textPrimary))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],

                // Suggestions
                if (result.suggestions.isNotEmpty) ...[
                  const Text('SUGGESTED IMPROVEMENTS', 
                    style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                   const SizedBox(height: 4),
                  ...result.suggestions.map((suggestion) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppTheme.success)),
                        Expanded(child: Text(suggestion, style: const TextStyle(color: AppTheme.textPrimary))),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final problem = ref.watch(currentProblemProvider);
    final simState = ref.watch(simulationProvider);
    final canvasState = ref.watch(canvasProvider);
    final user = ref.watch(currentUserProvider);

    // Listen for simulation events (failures/bottlenecks)
    ref.listen(simulationProvider, (previous, next) {
      // Simulation failed listener - removed snackbar
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
          builder: (context, constraints) {
            final useSidebar = constraints.maxWidth >= 900;
            
            return Column(
              children: [
                // Header with problem info
                _ProblemHeader(
                  problem: problem,
                  onHintsTap: () => setState(() => _showHints = !_showHints),
                  showHints: _showHints,
                  onSaveTap: _showSaveDesignDialog,
                  onGalleryTap: _showDesignsGallery,
                  onPublishTap: _handlePublishDesign,
                ),

                // Metrics bar (when simulating)
                if (simState.isRunning || simState.isCompleted)
                  const MetricsBar(),

                // Main content area (responsive)
                Expanded(
                  child: useSidebar
                      ? _buildWebLayout(simState, canvasState, problem, constraints)
                      : _buildMobileLayout(simState, canvasState, problem, constraints),
                ),

                // Bottom controls
                _BottomControls(
                  canStart: ref.watch(validationProvider).maybeWhen(
                    data: (v) => v.isValid,
                    orElse: () => false,
                  ),
                  isSimulating: simState.isRunning,
                  isPaused: simState.isPaused,
                  onStart: () => ref.read(simulationEngineProvider).start(),
                  onPause: () => ref.read(simulationEngineProvider).pause(),
                  onResume: () => ref.read(simulationEngineProvider).resume(),
                  onStop: () => ref.read(simulationEngineProvider).stop(),
                  onReset: () {
                    ref.read(simulationEngineProvider).stop();
                    ref.read(canvasProvider.notifier).clear();
                    ref.read(simulationProvider.notifier).reset();
                  },
                ),
              ],
            );
          },
        ),
      ),
          
      // Login Overlay
      if (user == null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: const Center(
                    child: LoginScreen(),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  /// Web layout with sidebar toolbox
  Widget _buildWebLayout(SimulationState simState, CanvasState canvasState, Problem problem, BoxConstraints constraints) {
    return SizedBox.expand(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Sidebar toolbox
        SizedBox(
          width: ResponsiveLayout.getSidebarWidth(context),
          child: const ComponentToolbox(mode: ToolboxMode.sidebar),
        ),
        
        // Canvas area
        Expanded(
          child: _buildCanvasArea(simState, canvasState, problem, constraints, showBottomToolbox: false),
        ),
      ],
      ),
    );
  }

  /// Mobile layout with bottom toolbox
  Widget _buildMobileLayout(SimulationState simState, CanvasState canvasState, Problem problem, BoxConstraints constraints) {
    return _buildCanvasArea(simState, canvasState, problem, constraints, showBottomToolbox: true);
  }

  /// Canvas area with overlays
  Widget _buildCanvasArea(SimulationState simState, CanvasState canvasState, Problem problem, BoxConstraints constraints, {required bool showBottomToolbox}) {
    return Stack(
      children: [
        // System canvas
        const Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SystemCanvas(),
          ),
        ),

        // Drawing Toolbar (Draggable)
        if (!simState.isRunning)
          Positioned(
            left: _toolbarPosition?.dx ?? (constraints.maxWidth / 2 - 200), // Default center
            top: _toolbarPosition?.dy ?? 20,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _toolbarPosition = (_toolbarPosition ?? Offset(constraints.maxWidth / 2 - 200, 20)) + details.delta;
                  
                  // Keep within bounds
                  final x = _toolbarPosition!.dx.clamp(0.0, (constraints.maxWidth - 400).toDouble());
                  final y = _toolbarPosition!.dy.clamp(0.0, (constraints.maxHeight - 80).toDouble());
                  _toolbarPosition = Offset(x, y);
                });
              },
              child: const DrawingToolbar()
                  .animate()
                  .fadeIn()
                  .slideY(begin: -0.2),
            ),
          ),

        // Component toolbox (bottom - mobile only)
        if (showBottomToolbox)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: const ComponentToolbox(mode: ToolboxMode.horizontal)
                .animate()
                .fadeIn()
                .slideY(begin: 0.3),
          ),

        // Metrics panel (top right, when simulating)
        if (simState.isRunning)
          Positioned(
            top: 8,
            right: 8,
            child: const MetricsPanel()
                .animate()
                .fadeIn()
                .slideX(begin: 0.2),
          ),

        // Hints panel (left)
        if (_showHints)
          Positioned(
            top: 8,
            left: 8,
            child: Animate(
              effects: const [SlideEffect(begin: Offset(-0.2, 0))],
              child: const HintsPanel(),
            ),
          ),

        // Hints panel (left) - duplicate removed in refactor
        
        // Failure alerts (optional, kept for context but not blocking)
         if (simState.failures.isNotEmpty)
          Positioned(
            top: 8,
            left: 8,
            child: _FailureAlerts(failures: simState.failures),
          ),

        // Canvas Controls (Format, Zoom, Help)
        if (!simState.isRunning)
          Positioned(
            top: 16,
            left: showBottomToolbox ? 16 : 8,
            child: Column(
              children: [
                 FloatingActionButton.small(
                  heroTag: 'help_fab',
                  onPressed: () => setState(() => _showGuide = true),
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.primary,
                  tooltip: 'Canvas Guide',
                  child: const Icon(Icons.question_mark, size: 20),
                ).animate().scale(delay: 100.ms),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'export_fab',
                  onPressed: () async {
                    final json = await BlueprintExporter.exportToJsonAsync(canvasState, problem);
                    final fileName = '${problem.title.toLowerCase().replaceAll(' ', '_')}_blueprint.json';
                    FileSaver.saveJson(json, fileName);
                    
                    if (mounted) {
                      // Exported - removed snackbar
                    }
                  },
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  tooltip: 'Export Blueprint (JSON)',
                  child: const Icon(Icons.file_download, size: 20),
                ).animate().scale(delay: 150.ms),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'import_fab',
                  onPressed: () async {
                    try {
                      final json = await FileSaver.pickJson();
                      if (json != null) {
                        final newState = await BlueprintImporter.importFromJsonAsync(json);
                        ref.read(canvasProvider.notifier).loadState(newState);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Blueprint imported successfully!'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      }
                    } catch (e) {
                      // Import failed - removed snackbar
                    }
                  },
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.primary,
                  tooltip: 'Import Blueprint (JSON)',
                  child: const Icon(Icons.file_upload, size: 20),
                ).animate().scale(delay: 180.ms),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'publish_fab',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => PublishDesignDialog(problem: problem),
                    );
                  },
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  tooltip: 'Publish to Community',
                  child: const Icon(Icons.public, size: 20),
                ).animate().scale(delay: 200.ms),
                const SizedBox(height: 8),

                FloatingActionButton.small(
                  heroTag: 'analyze_fab',
                  onPressed: () => _handleAiAnalysis(context, ref),
                  backgroundColor: AppTheme.primary, // Distinct color
                  foregroundColor: Colors.white,
                  tooltip: 'Analyze with AI',
                  child: const Icon(Icons.auto_awesome, size: 20),
                ).animate().scale(delay: 220.ms)
                    .shimmer(delay: 2000.ms, duration: 1500.ms), // Subtle shimmer to attract attention
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'format_fab',
                  onPressed: () {
                    ref.read(canvasProvider.notifier).autoLayout(MediaQuery.of(context).size);
                  },
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.textSecondary,
                  tooltip: 'Format Layout',
                  child: const Icon(Icons.grid_view, size: 20),
                ).animate().scale(delay: 200.ms),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'clear_canvas_fab',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        title: const Text('Clear Canvas?', style: TextStyle(color: AppTheme.textPrimary)),
                        content: const Text('This will remove all components and connections. This action cannot be undone.', 
                          style: TextStyle(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () {
                              ref.read(canvasProvider.notifier).clear();
                              Navigator.pop(context);
                            },
                            child: const Text('CLEAR', style: TextStyle(color: AppTheme.error)),
                          ),
                        ],
                      ),
                    );
                  },
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.error.withValues(alpha: 0.7),
                  tooltip: 'Clear Canvas',
                  child: const Icon(Icons.delete_sweep, size: 20),
                ).animate().scale(delay: 240.ms),
              ],
            ),
          ),

          // Guide Overlay
          if (_showGuide)
            Positioned.fill(
              child: GuideOverlay(
                onDismiss: () => setState(() => _showGuide = false),
              ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
            ),

          // Toggle for toolbox if hidden (mobile only)
          if (showBottomToolbox)
            const Positioned(
              bottom: 16,
              left: 16,
              child: ToolboxToggle(),
            ),
      ],
    );
  }
}

/// Problem header with title and constraints
class _ProblemHeader extends ConsumerWidget {
  final dynamic problem;
  final VoidCallback onHintsTap;
  final bool showHints;
  final VoidCallback onSaveTap;
  final VoidCallback onGalleryTap;
  final VoidCallback onPublishTap;

  const _ProblemHeader({
    required this.problem,
    required this.onHintsTap,
    required this.showHints,
    required this.onSaveTap,
    required this.onGalleryTap,
    required this.onPublishTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  problem.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                // Removed SLA/Constraints as requested
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Actions Toolbar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Library (Major Feature)
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityScreen())),
                  icon: const Icon(Icons.local_library_rounded, size: 20),
                  label: const Text('Library', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                
                const SizedBox(width: 12),

                // User Profile / Auth Status
                FutureBuilder<Map<String, dynamic>?>(
                  future: SupabaseService().getCurrentProfile(),
                  builder: (context, snapshot) {
                    final profile = snapshot.data;
                    final currentUser = SupabaseService().currentUser;
                    final name = profile?['display_name'] ?? currentUser?.email?.split('@')[0] ?? '';
                    
                    if (name.isEmpty) return const SizedBox.shrink();

                    return Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: AppTheme.primary,
                            child: Text(
                              name[0].toUpperCase(),
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                // My Designs
                
                // My Designs
                _HeaderActionButton(
                  icon: Icons.folder_open_outlined,
                  tooltip: 'My Designs',
                  onTap: onGalleryTap,
                ),

                const SizedBox(width: 4),

                // Publish
                _HeaderActionButton(
                  icon: Icons.cloud_upload_outlined,
                  tooltip: 'Publish',
                  onTap: onPublishTap,
                  color: AppTheme.success,
                ),

                const SizedBox(width: 4),

                // Save
                _HeaderActionButton(
                  icon: Icons.save_outlined,
                  tooltip: 'Save',
                  onTap: onSaveTap,
                ),
                
                const _VerticalDivider(),

                // Hints
                _HeaderActionButton(
                  icon: showHints ? Icons.lightbulb : Icons.lightbulb_outline,
                  tooltip: 'Hints',
                  onTap: onHintsTap,
                  isActive: showHints,
                  color: showHints ? Colors.amber : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppTheme.border,
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final bool isActive;

  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? AppTheme.textSecondary;
    
    return Material(
      color: isActive ? themeColor.withOpacity(0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            icon, 
            size: 20, 
            color: isActive ? themeColor : themeColor.withOpacity(0.8)
          ),
        ),
      ),
    );
  }
}

class _ConstraintChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ConstraintChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ],
      ),
    );
  }
}

/// Bottom control buttons
class _BottomControls extends StatelessWidget {
  final bool canStart;
  final bool isSimulating;
  final bool isPaused;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onReset;

  const _BottomControls({
    required this.canStart,
    required this.isSimulating,
    required this.isPaused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Reset button
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.textMuted.withValues(alpha: 0.3)),
            ),
          ),

          const Spacer(),

          // Main action button
          if (isSimulating) ...[
            // Pause/Resume
            IconButton(
              onPressed: isPaused ? onResume : onPause,
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.surfaceLight,
                foregroundColor: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            // Stop
            ElevatedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
              ),
            ),
          ] else ...[
            // Run simulation
            ElevatedButton.icon(
              onPressed: canStart ? onStart : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Simulation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                disabledBackgroundColor: AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Failure alerts overlay
class _FailureAlerts extends StatelessWidget {
  final List<dynamic> failures;

  const _FailureAlerts({required this.failures});

  @override
  Widget build(BuildContext context) {
    // Get unique failures
    final uniqueFailures = failures.toSet().take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: uniqueFailures.asMap().entries.map((entry) {
        final index = entry.key;
        final failure = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppTheme.error.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  failure.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(delay: Duration(milliseconds: 100 * index))
            .shake(hz: 2, offset: const Offset(2, 0));
      }).toList(),
    );
  }
}
