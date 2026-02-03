import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/game_provider.dart';
import '../providers/auth_provider.dart';
import '../simulation/simulation_engine.dart';
import '../models/problem.dart';
import '../models/metrics.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import '../widgets/canvas/system_canvas.dart';
import '../widgets/toolbox/component_toolbox.dart';
import '../widgets/metrics/metrics_panel.dart';
import '../widgets/panels/hints_panel.dart';
// import '../widgets/simulation/failure_overlay.dart';
import '../simulation/design_validator.dart';
import 'results_screen.dart';
import '../widgets/panels/guide_overlay.dart';
import '../utils/blueprint_exporter.dart';
import '../utils/blueprint_importer.dart';
// import '../widgets/community/publish_dialog.dart';
import '../widgets/canvas/drawing_toolbar.dart';
import 'community_screen.dart';
import '../data/problems.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'publish_screen.dart';
import '../widgets/simulation/error_fix_dialog.dart';
import '../widgets/simulation/chaos_controls_panel.dart';
import 'dart:ui';

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
  bool _showResultsOverlay = false;
  Map<String, dynamic>? _activeCommunityDesign = null;

  @override
  void initState() {
    super.initState();
    debugPrint('GameScreen Initialized');
    
    if (widget.initialCommunityDesign != null) {
      _activeCommunityDesign = widget.initialCommunityDesign;
    }
    
    // Auto-load a complex design for testing simulation and click-to-fix
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ref.read(canvasProvider.notifier).loadSolution(ref.read(currentProblemProvider));
      // Initialize with empty or saved progress instead
      ref.read(canvasProvider.notifier).initializeWithProblem(ref.read(currentProblemProvider).id);
    });
  }

  Future<void> _handlePublishDesign() async {
     final user = SupabaseService().currentUser;
     final guestMode = ref.watch(guestModeProvider);

     if (user == null && !guestMode) {
       final loggedIn = await showDialog<bool>(
         context: context,
         barrierDismissible: true,
         builder: (context) => const Dialog(
           backgroundColor: Colors.transparent,
           insetPadding: EdgeInsets.zero,
           child: LoginScreen(),
         ),
       );
       if (loggedIn != true) return;
     }

     final canvasState = ref.read(canvasProvider);
     final problem = ref.read(currentProblemProvider);
     final jsonString = BlueprintExporter.exportToJson(canvasState, problem);
     
     if (!mounted) return;
     Navigator.push(context, MaterialPageRoute(builder: (c) => PublishScreen(
       initialTitle: problem.title,
       canvasData: jsonDecode(jsonString),
     )));
  }

  void _handleSaveDesign() {}
  
  Future<void> _handleProfileTap() async {
    final user = SupabaseService().currentUser;
    if (user == null) {
      await showDialog(
        context: context,
        builder: (context) => const Dialog(
          backgroundColor: Colors.transparent,
          child: LoginScreen(),
        ),
      );
      return;
    }

    if (!mounted) return;
    
    // Show profile info and logout button
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: AppTheme.primary),
            const SizedBox(width: 12),
            const Text('Architect Profile', style: TextStyle(color: AppTheme.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            Text(user.email ?? 'Unknown', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            Text('Role', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const Text('Senior System Architect', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error.withOpacity(0.1),
              foregroundColor: AppTheme.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              await SupabaseService().signOut();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout(SimulationState simState, bool hasComponents, Problem problem, BoxConstraints constraints) {
    return Row(
      children: [
        SizedBox(
          width: ResponsiveLayout.getSidebarWidth(context),
          child: const ComponentToolbox(mode: ToolboxMode.sidebar),
        ),
        Expanded(
          child: _buildCanvasArea(simState, hasComponents, problem, constraints),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(SimulationState simState, bool hasComponents, Problem problem, BoxConstraints constraints) {
    return Column(
      children: [
        Expanded(
          child: _buildCanvasArea(simState, hasComponents, problem, constraints),
        ),
        const ComponentToolbox(mode: ToolboxMode.horizontal),
      ],
    );
  }

  Widget _buildCanvasArea(SimulationState simState, bool hasComponents, Problem problem, BoxConstraints constraints) {
    return Stack(
      children: [
        const SystemCanvas(),
        
        // Drawing Toolbar
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
            child: const DrawingToolbar(),
          ),
        ),

        // Hints & Validation Panel
        if (_showHints && !simState.isRunning)
          Positioned(
            top: 20,
            right: 20,
            child: SizedBox(
               width: 300,
               child: const HintsPanel(),
            ),
          ),
        
        // Hints Toggle (if hidden)
        if (!_showHints && !simState.isRunning)
          Positioned(
            top: 20,
            right: 20,
            child: FloatingActionButton.small(
              backgroundColor: AppTheme.surface,
              onPressed: () => setState(() => _showHints = true),
              child: const Icon(Icons.lightbulb_outline, color: AppTheme.primary),
            ),
          ),

        if (_showGuide)
           GuideOverlay(onDismiss: () => setState(() => _showGuide = false)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final simState = ref.watch(simulationProvider);
    // CRITICAL: Selection optimization to prevent infinite rebuild loop during panning
    final hasComponents = ref.watch(canvasProvider.select((s) => s.components.isNotEmpty));
    final problem = ref.watch(currentProblemProvider);
    final profile = ref.watch(profileProvider);

    final canvasState = ref.watch(canvasProvider);
    final validation = DesignValidator.validate(
      components: canvasState.components,
      connections: canvasState.connections,
      problem: problem,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useSidebar = constraints.maxWidth >= 900;
              return Column(
                children: [
                  _ProblemHeader(
                    onPublishTap: _handlePublishDesign,
                    onSaveTap: _handleSaveDesign,
                    onProfileTap: _handleProfileTap,
                    profile: profile,
                  ),
                  if (simState.isRunning) const MetricsBar(),
                  Expanded(
                    child: useSidebar 
                      ? _buildWebLayout(simState, hasComponents, problem, constraints)
                      : _buildMobileLayout(simState, hasComponents, problem, constraints),
                  ),
                  _BottomControls(
                    canStart: validation.isValid,
                    isSimulating: simState.isRunning,
                    isPaused: simState.isPaused,
                    isCompleted: simState.isCompleted || simState.isFailed,
                    onStart: () {
                      setState(() => _showResultsOverlay = false);
                      ref.read(simulationEngineProvider).start();
                    },
                    onPause: () => ref.read(simulationEngineProvider).pause(),
                    onResume: () => ref.read(simulationEngineProvider).resume(),
                    onStop: () => ref.read(simulationEngineProvider).stop(),
                    onReset: () {
                      setState(() => _showResultsOverlay = false);
                      ref.read(simulationEngineProvider).reset();
                    },
                    onViewResults: () => setState(() => _showResultsOverlay = true),
                  ),
                ],
              );
            },
          ),
          
          // Simulation Overlays
          if (simState.isFailed && !_showResultsOverlay)
            _FailureAlerts(failures: simState.failures),
          
          // Chaos Engineering Controls
          const ChaosControlsPanel(),
            
          if (_showResultsOverlay)
             ResultsScreen(
               onClose: () {
                 setState(() => _showResultsOverlay = false);
                 ref.read(simulationEngineProvider).stop();
               },
             ),
        ],
      ),
    );
  }
}

class _ProblemHeader extends StatelessWidget {
  final VoidCallback onPublishTap;
  final VoidCallback onSaveTap;
  final VoidCallback onProfileTap;
  final AsyncValue<Map<String, dynamic>?> profile;

  const _ProblemHeader({
    required this.onPublishTap, 
    required this.onSaveTap, 
    required this.onProfileTap,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            'System Architect',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          
          // Auto Layout Button
          Consumer(builder: (context, ref, _) {
            return TextButton.icon(
              icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 18),
              label: const Text('AUTO LAYOUT'),
              onPressed: () => ref.read(canvasProvider.notifier).autoLayout(MediaQuery.of(context).size),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            );
          }),
          
          const SizedBox(width: 8),

          // Library Button
          TextButton.icon(
            icon: const Icon(Icons.local_library_rounded, size: 18),
            label: const Text('LIBRARY'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CommunityScreen()),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
          
          const SizedBox(width: 16),
          
          profile.maybeWhen(
            data: (p) {
              if (p == null) return const SizedBox.shrink();
              final name = p['display_name'] ?? 'Architect';
              return Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: AppTheme.primary,
                      child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    Text(name, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.rocket_launch_rounded, size: 18),
            label: const Text('PUBLISH', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            onPressed: onPublishTap,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: AppTheme.textSecondary),
            onPressed: onProfileTap,
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends ConsumerWidget {
  final bool canStart;
  final bool isSimulating;
  final bool isPaused;
  final bool isCompleted;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onViewResults;

  const _BottomControls({
    required this.canStart, 
    required this.isSimulating, 
    required this.isPaused, 
    required this.isCompleted,
    required this.onStart, 
    required this.onPause, 
    required this.onResume,
    required this.onStop, 
    required this.onReset,
    required this.onViewResults,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(canvasProvider.select((s) => s.scale ?? 1.0)) * 100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: AppTheme.surface,
      child: Row(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSimulating ? AppTheme.error : (canStart ? AppTheme.primary : AppTheme.textMuted.withOpacity(0.3)),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              elevation: canStart ? 4 : 0,
            ),
            onPressed: isSimulating ? onStop : (canStart ? onStart : null), 
            child: Text(isSimulating ? 'STOP SIMULATION' : 'START SIMULATION'),
          ),
          if (isCompleted && !isSimulating) ...[
            const SizedBox(width: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('VIEW RESULTS'),
              onPressed: onViewResults,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ).animate().fadeIn().scale(),
          ],
          const SizedBox(width: 16),
          if (isSimulating) 
             IconButton(
               icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 32), 
               onPressed: isPaused ? onResume : onPause
             ),
          
          const Spacer(),
          
          // Zoom Controls
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => ref.read(canvasProvider.notifier).zoomOut(),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
                Text('${scale.round()}%', style: Theme.of(context).textTheme.labelLarge),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => ref.read(canvasProvider.notifier).zoomIn(),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('RESET'),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _FailureAlerts extends ConsumerWidget {
  final List<dynamic> failures;
  const _FailureAlerts({required this.failures});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      bottom: 120,
      right: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: failures.asMap().entries.map((entry) {
          final index = entry.key;
          final failure = entry.value;
          return _ClickableErrorCard(failure: failure, index: index);
        }).toList(),
      ),
    );
  }
}

class _ClickableErrorCard extends StatefulWidget {
  final FailureEvent failure;
  final int index;

  const _ClickableErrorCard({
    required this.failure,
    required this.index,
  });

  @override
  State<_ClickableErrorCard> createState() => _ClickableErrorCardState();
}

class _ClickableErrorCardState extends State<_ClickableErrorCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => ErrorFixDialog(failure: widget.failure),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(_isHovered ? 1.0 : 0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovered ? 0.4 : 0.3),
                blurRadius: _isHovered ? 12 : 10,
                offset: Offset(0, _isHovered ? 6 : 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.failure.message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              if (widget.failure.fixType != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CLICK TO FIX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 100 * widget.index))
        .shake(hz: 2, offset: const Offset(2, 0)),
      ),
    );
  }
}
