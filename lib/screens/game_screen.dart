import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../widgets/simulation/disaster_toolkit.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import '../utils/blueprint_exporter.dart';
import 'dart:math' as math;
import 'admin_screen.dart';

class GameScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialCommunityDesign;
  final String? sharedDesignId;
  final String? designOwnerId;
  final bool readOnly;

  const GameScreen({
    super.key,
    this.initialCommunityDesign,
    this.sharedDesignId,
    this.designOwnerId,
    this.readOnly = false,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _ReadOnlyBadge extends StatelessWidget {
  final VoidCallback onCopy;
  final String? ownerEmail;
  final double topOffset;
  const _ReadOnlyBadge({required this.onCopy, this.ownerEmail, this.topOffset = 76});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topOffset,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Text(
              ownerEmail != null ? 'Read-only (by $ownerEmail)' : 'Read-only',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copy to My Designs'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameScreenState extends ConsumerState<GameScreen> {
  bool _showHints = false;
  bool _showGuide = false;
  bool _showResultsOverlay = false;
  Map<String, dynamic>? _activeCommunityDesign = null;
  String? _sharedDesignId;
  bool _loadingShared = false;
  String? _privateDesignId;
  String? _privateDesignTitle;
  bool _authPromptShown = false;
  bool _trafficInitialized = false;
  String? _designOwnerId;
  String? _designOwnerEmail;
  final GlobalKey _toolbarKey = GlobalKey();
  bool _showDesktopHint = true;
  RealtimeChannel? _statusChannel;
  String? _statusListeningUserId;
  ProviderSubscription<User?>? _authListener;
  Timer? _statusPollTimer;
  final Map<String, String> _statusCache = {};
  final Set<String> _notifiedRejections = {};
  final List<_RejectionNotice> _rejectionNotices = [];
  final Set<String> _dismissedRejectionIds = {};

  @override
  void initState() {
    super.initState();
    debugPrint('GameScreen Initialized');
    _loadDismissedRejections();
    _authListener = ref.listenManual<User?>(currentUserProvider, (prev, next) {
      if (next != null && next.id != _statusListeningUserId) {
        _setupDesignStatusListener(next);
        _startStatusPolling(next);
      }
      if (next == null) {
        _disposeStatusListener();
        _stopStatusPolling();
      }
    });
    
    if (widget.initialCommunityDesign != null) {
      // If payload is wrapped under 'canvas_data', unwrap it
      if (widget.initialCommunityDesign!.containsKey('canvas_data') &&
          widget.initialCommunityDesign!['canvas_data'] is Map<String, dynamic>) {
        _activeCommunityDesign = Map<String, dynamic>.from(widget.initialCommunityDesign!['canvas_data']);
      } else {
        _activeCommunityDesign = widget.initialCommunityDesign;
      }
      _designOwnerId = widget.designOwnerId ?? widget.initialCommunityDesign!['__owner_id'] as String?;
      _designOwnerEmail = widget.initialCommunityDesign!['__owner_email'] as String?;
    }
    _sharedDesignId = widget.sharedDesignId;
    if (_designOwnerId == null) {
      _designOwnerId = widget.designOwnerId;
    }
    
    // Auto-load a complex design for testing simulation and click-to-fix
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activeCommunityDesign != null) {
        final imported = BlueprintImporter.importFromMap(_activeCommunityDesign!);
        ref.read(canvasProvider.notifier).loadState(imported);
        _setReadOnlyFlag();
        _fitContentToViewport();
        _autoLayoutCurrent();
      } else if (_sharedDesignId != null) {
        _loadSharedDesign(_sharedDesignId!);
      } else {
        ref.read(canvasProvider.notifier).initializeWithProblem(
          ref.read(currentProblemProvider).id,
          forceTestDesign: true,
        );
        ref.read(canvasReadOnlyProvider.notifier).state = false;
      }
      _maybePromptAuth();
      _maybeSetDefaultTraffic();
      final user = SupabaseService().currentUser;
      if (user != null) {
        _setupDesignStatusListener(user);
      }
      _maybeNotifyExistingRejections();
    });
  }

  Future<void> _maybeNotifyExistingRejections() async {
    final user = SupabaseService().currentUser;
    if (user == null) return;
    try {
      final designs = await SupabaseService().fetchMyDesigns();
      for (final d in designs) {
        final id = d['id'] as String?;
        final status = d['status'] as String?;
        if (id == null || status != 'rejected') continue;
        if (_notifiedRejections.contains(id)) continue;
        final reason = d['rejection_reason'] as String? ?? 'Rejected by moderator.';
        final title = d['title'] as String? ?? 'Design';
        _notifiedRejections.add(id);
        _addRejectionNotice(id: id, title: title, reason: reason);
      }
    } catch (_) {
      // ignore errors; polling already handles live updates
    }
  }

  void _addRejectionNotice({required String id, required String title, required String reason}) {
    if (_dismissedRejectionIds.contains(id)) return;
    if (_rejectionNotices.any((n) => n.id == id)) return;
    if (!mounted) return;
    setState(() {
      _rejectionNotices.add(_RejectionNotice(id: id, title: title, reason: reason));
    });
  }

  Future<void> _openNotifications() async {
    if (_rejectionNotices.isEmpty && _dismissedRejectionIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No notifications'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final notices = List<_RejectionNotice>.from(_rejectionNotices);

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (notices.isEmpty)
                  const Text('No new rejections', style: TextStyle(color: AppTheme.textSecondary))
                else
                  ...notices.map((n) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.block, color: AppTheme.error),
                        title: Text(n.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                        subtitle: Text(n.reason, style: const TextStyle(color: AppTheme.textSecondary)),
                      )),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    // Mark all viewed as dismissed
    setState(() {
      for (final n in notices) {
        _dismissedRejectionIds.add(n.id);
      }
      _rejectionNotices.clear();
    });
    await _persistDismissed();
  }

  Future<void> _loadSharedDesign(String designId) async {
    setState(() => _loadingShared = true);
    try {
      final data = await SupabaseService().fetchDesignById(designId);
      if (data != null && mounted) {
        final imported = BlueprintImporter.importFromMap(data);
        ref.read(canvasProvider.notifier).loadState(imported);
        _privateDesignId = designId;
        _privateDesignTitle = data['title'] as String?;
        _designOwnerId = data['__owner_id'] as String?;
        _designOwnerEmail = data['__owner_email'] as String?;
        _setReadOnlyFlag();
        _fitContentToViewport();
        _autoLayoutCurrent();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared design not found')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load shared design: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingShared = false);
    }
  }

  Future<void> _maybePromptAuth() async {
    if (_authPromptShown) return;
    final user = SupabaseService().currentUser;
    final guest = ref.read(guestModeProvider);
    if (user != null || guest) return;

    _authPromptShown = true;
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(24),
        child: LoginScreen(),
      ),
    );
  }

  void _maybeSetDefaultTraffic() {
    if (_trafficInitialized) return;
    ref.read(canvasProvider.notifier).setTrafficLevel(0.4);
    _trafficInitialized = true;
  }

  Future<void> _loadDismissedRejections() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('dismissed_rejections') ?? [];
    setState(() {
      _dismissedRejectionIds.addAll(ids);
    });
  }

  Future<void> _persistDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dismissed_rejections', _dismissedRejectionIds.toList());
  }

  Future<void> _exportCanvasJson() async {
    try {
      final canvasState = ref.read(canvasProvider);
      final problem = ref.read(currentProblemProvider);
      final jsonString = BlueprintExporter.exportToJson(canvasState, problem);

      // Show dialog with copy option
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Exported JSON', style: TextStyle(color: AppTheme.textPrimary)),
            content: SizedBox(
              width: 520,
              child: SelectableText(
                jsonString,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonString));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
                child: const Text('COPY'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _importCanvasJson() async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Import JSON', style: TextStyle(color: AppTheme.textPrimary)),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: controller,
              maxLines: 12,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Paste canvas JSON here',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('LOAD'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;
    try {
      final decoded = jsonDecode(result);
      final map = (decoded is Map<String, dynamic>) ? decoded : null;
      if (map == null) throw 'JSON must be an object';
      final payload = map['canvas_data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(map['canvas_data'])
          : map;
      final imported = BlueprintImporter.importFromMap(payload);
      ref.read(canvasProvider.notifier).loadState(imported);
      ref.read(canvasReadOnlyProvider.notifier).state = false;
      _fitContentToViewport();
      _autoLayoutCurrent();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas loaded from JSON')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  void _setReadOnlyFlag() {
    final user = SupabaseService().currentUser;
    final isOwner = user != null && _designOwnerId != null && user.id == _designOwnerId;
    ref.read(canvasReadOnlyProvider.notifier).state = widget.readOnly || !isOwner && _designOwnerId != null;
  }

  Future<void> _copyToMyDesigns() async {
    final user = SupabaseService().currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to copy this design')),
      );
      return;
    }
    try {
      final canvasState = ref.read(canvasProvider);
      final problem = ref.read(currentProblemProvider);
      final exported = BlueprintExporter.exportToJson(canvasState, problem);
      final newTitle = '${_privateDesignTitle ?? problem.title} (copy)';
      final id = await SupabaseService().savePrivateDesign(
        title: newTitle,
        description: problem.description,
        canvasData: jsonDecode(exported),
        designId: null,
      );
      _privateDesignId = id;
      _privateDesignTitle = newTitle;
      _designOwnerId = user.id;
      ref.read(canvasReadOnlyProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied. You can now edit this design.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copy failed: $e')),
      );
    }
  }

  void _startStatusPolling(User user) {
    _stopStatusPolling();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final designs = await SupabaseService().fetchMyDesigns();
        for (final d in designs) {
          final id = d['id'] as String?;
          final status = d['status'] as String?;
          if (id == null || status == null) continue;
          final prev = _statusCache[id];
          if (prev != null && prev != status) {
            _showStatusSnack(status, d['rejection_reason'] as String?);
          }
          _statusCache[id] = status;
        }
      } catch (_) {
        // ignore poll errors
      }
    });
  }

  void _stopStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
    _statusCache.clear();
  }

  void _setupDesignStatusListener(User user) {
    if (_statusChannel != null && _statusListeningUserId == user.id) return;
    _disposeStatusListener();
    _statusListeningUserId = user.id;

    _statusChannel = SupabaseService()
        .client
        .channel('design-status-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'designs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            final oldStatus = payload.oldRecord?['status'] as String?;
            if (newStatus == null || newStatus == oldStatus) return;
            final reason = payload.newRecord['rejection_reason'] as String?;
            _showStatusSnack(newStatus, reason);
          },
        )
        .subscribe();
  }

  void _showStatusSnack(String status, String? reason) {
    if (!mounted) return;
    Color bg;
    String text;
    switch (status) {
      case 'approved':
        bg = AppTheme.success;
        text = 'Your design was approved and published!';
        break;
      case 'rejected':
        bg = AppTheme.error;
        text = (reason != null && reason.isNotEmpty)
            ? 'Design rejected: $reason'
            : 'Design rejected by moderator.';
        final currentId = _privateDesignId ?? _sharedDesignId ?? 'unknown';
        _addRejectionNotice(
          id: currentId,
          title: _privateDesignTitle ?? 'Design',
          reason: reason ?? 'Design rejected by moderator.',
        );
        break;
      default:
        return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bg.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _disposeStatusListener() {
    _statusChannel?.unsubscribe();
    _statusChannel = null;
    _statusListeningUserId = null;
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

  Future<void> _handleSaveDesignRemote() async {
    try {
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

      final title = await _promptForTitle(initial: _privateDesignTitle ?? ref.read(currentProblemProvider).title);
      if (title == null || title.trim().isEmpty) return;

      final canvasState = ref.read(canvasProvider);
      final problem = ref.read(currentProblemProvider);
      final json = BlueprintExporter.exportToJson(canvasState, problem);
      final id = await SupabaseService().savePrivateDesign(
        title: title.trim(),
        description: problem.description,
        canvasData: jsonDecode(json),
        designId: _privateDesignId,
      );
      _privateDesignId = id;
      _privateDesignTitle = title.trim();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Design saved to your account'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.success.withValues(alpha: 0.8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().contains('row-level security')
          ? 'Save failed: permission denied. Please ensure you are logged in and have access to save designs.'
          : 'Save failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _fitContentToViewport() {
    final canvasState = ref.read(canvasProvider);
    if (canvasState.components.isEmpty) return;

    final size = MediaQuery.of(context).size;
    const padding = 200.0;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final c in canvasState.components) {
      minX = math.min(minX, c.position.dx);
      minY = math.min(minY, c.position.dy);
      maxX = math.max(maxX, c.position.dx + c.size.width);
      maxY = math.max(maxY, c.position.dy + c.size.height);
    }

    final contentWidth = (maxX - minX) + padding;
    final contentHeight = (maxY - minY) + padding;

    final scaleX = size.width / contentWidth;
    final scaleY = size.height / contentHeight;
    final fitScale = math.max(0.2, math.min(1.2, math.min(scaleX, scaleY)));

    final contentCenter = Offset(minX + (maxX - minX) / 2, minY + (maxY - minY) / 2);
    final viewportCenter = Offset(size.width / 2, size.height / 2);

    final newOffset = viewportCenter - (contentCenter * fitScale);

    ref.read(canvasProvider.notifier).updateTransform(
      panOffset: newOffset,
      scale: fitScale,
    );
  }

  void _autoLayoutCurrent() {
    final canvas = ref.read(canvasProvider);
    if (canvas.components.isEmpty) return;
    final size = MediaQuery.of(context).size;
    ref.read(canvasProvider.notifier).autoLayout(size);
  }

  Future<void> _handleLoadMyDesigns() async {
    try {
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

      final designs = await SupabaseService().fetchMyDesigns();
      if (!mounted) return;
      if (designs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved designs found')),
        );
        return;
      }

      await showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return ListView.separated(
            shrinkWrap: true,
            itemCount: designs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = designs[index];
              final title = item['title'] ?? 'Untitled';
              final updated = item['updated_at'] ?? item['created_at'] ?? '';
              final status = (item['status'] ?? 'pending').toString();
              final rejection = item['rejection_reason'];
              final statusLabel = rejection != null && status == 'rejected'
                  ? 'Status: $status • $rejection'
                  : 'Status: $status';
              return ListTile(
                title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text(
                  '$updated\n$statusLabel',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final data = item['canvas_data'] as Map<String, dynamic>?;
                  final blueprintPath = item['blueprint_path'] as String?;
                  Map<String, dynamic>? designData = data;
                  if (designData == null && blueprintPath != null) {
                    designData = await SupabaseService().downloadBlueprint(blueprintPath);
                  }
                  if (designData != null) {
                    final imported = BlueprintImporter.importFromMap(designData);
                    ref.read(canvasProvider.notifier).loadState(imported);
                    setState(() {
                      _privateDesignId = item['id'] as String?;
                      _privateDesignTitle = title;
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to load design data')),
                    );
                  }
                },
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load designs: $e')),
        );
      }
    }
  }

  Future<void> _handleShareLink() async {
    try {
      // Ensure logged in (reuse publish flow gating)
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
      final json = BlueprintExporter.exportToJson(canvasState, problem);
      final designId = await SupabaseService().publishDesign(
        title: problem.title,
        description: problem.description,
        canvasData: jsonDecode(json),
        designId: null,
      );

      final uri = Uri.base;
      final newUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'designId': designId,
        },
      );
      await Clipboard.setData(ClipboardData(text: newUri.toString()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permalink copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not generate link: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleExportJson() async {
    // Disabled (per request to avoid JSON export)
  }

  Future<void> _handleImportJson() async {
    // Disabled (per request to avoid JSON import)
  }

  void _handleSaveDesign() {
    _handleSaveDesignRemote();
  }
  
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

  Widget _buildMobileLayout(
    SimulationState simState,
    bool hasComponents,
    Problem problem,
    BoxConstraints constraints,
    {required bool canStart}
  ) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: _buildCanvasArea(simState, hasComponents, problem, constraints),
            ),
            const ComponentToolbox(mode: ToolboxMode.horizontal),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16 + bottomSafe,
          child: FloatingActionButton.extended(
            heroTag: 'fab-sim',
            backgroundColor: simState.isRunning
                ? AppTheme.error
                : (canStart ? AppTheme.primary : AppTheme.textMuted.withOpacity(0.3)),
            foregroundColor: Colors.white,
            onPressed: simState.isRunning
                ? () => ref.read(simulationEngineProvider).stop()
                : (canStart ? () {
                    setState(() => _showResultsOverlay = false);
                    ref.read(simulationEngineProvider).start();
                  } : null),
            icon: Icon(simState.isRunning ? Icons.stop : Icons.play_arrow),
            label: Text(simState.isRunning ? 'Stop Simulation' : 'Start Simulation'),
          ),
        ),
      ],
    );
  }

  Widget _buildCanvasArea(SimulationState simState, bool hasComponents, Problem problem, BoxConstraints constraints) {
    final isAdmin = ref.watch(isAdminProvider);
    return Stack(
      children: [
        const SystemCanvas(),
        
        // Drawing Toolbar
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: RepaintBoundary(
              child: SizedBox(
                key: _toolbarKey,
                child: const DrawingToolbar(),
              ),
            ),
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

        // Admin JSON import/export shortcuts
        if (isAdmin)
          Positioned(
            top: 16,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AdminActionChip(
                  icon: Icons.download_rounded,
                  label: 'Export JSON',
                  onTap: _exportCanvasJson,
                ),
                const SizedBox(height: 8),
                _AdminActionChip(
                  icon: Icons.upload_rounded,
                  label: 'Import JSON',
                  onTap: _importCanvasJson,
                ),
              ],
            ),
          ),

        // Disaster Toolkit (Chaos Mode)
        Positioned(
          bottom: 100,
          left: 20,
          child: const DisasterToolkit(),
        ),
      ],
    );
  }

  Future<String?> _promptForTitle({required String initial}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Name your design', style: TextStyle(color: AppTheme.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'e.g. Payments Service v2',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final simState = ref.watch(simulationProvider);
    // CRITICAL: Selection optimization to prevent infinite rebuild loop during panning
    final hasComponents = ref.watch(canvasProvider.select((s) => s.components.isNotEmpty));
    final problem = ref.watch(currentProblemProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final readOnly = ref.watch(canvasReadOnlyProvider);

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
              final isMobile = !useSidebar;
              return Column(
                children: [
                  _ProblemHeader(
                    onPublishTap: _handlePublishDesign,
                    onSaveTap: _handleSaveDesign,
                    onProfileTap: _handleProfileTap,
                    onShareTap: _handleShareLink,
                    onLoadMyDesignsTap: _handleLoadMyDesigns,
                    profile: profile,
                    isAdmin: isAdmin,
                    onAdminTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                    onNotificationsTap: _openNotifications,
                    notificationCount: _rejectionNotices.length,
                  ),
                  if (simState.isRunning) const MetricsBar(),
                  Expanded(
                    child: useSidebar 
                      ? _buildWebLayout(simState, hasComponents, problem, constraints)
                      : _buildMobileLayout(simState, hasComponents, problem, constraints, canStart: validation.isValid),
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
                      ref.read(canvasProvider.notifier).clearCanvas();
                    },
                    onViewResults: () => setState(() => _showResultsOverlay = true),
                  ),
                ],
              );
            },
          ),
          if (_showDesktopHint)
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;
                if (!isMobile) return const SizedBox.shrink();
                return Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 12,
                  right: 12,
                  child: Material(
                    color: AppTheme.surface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.desktop_mac, color: AppTheme.primary),
                      title: const Text(
                        'For the best experience, try on a laptop or desktop.',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textMuted),
                        onPressed: () => setState(() => _showDesktopHint = false),
                      ),
                    ),
                  ),
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
          if (readOnly)
            _ReadOnlyBadge(
              onCopy: _copyToMyDesigns,
              ownerEmail: _designOwnerEmail,
              topOffset: 110,
            ),
          if (readOnly) _ReadOnlyBadge(onCopy: _copyToMyDesigns, ownerEmail: _designOwnerEmail),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _disposeStatusListener();
    _authListener?.close();
    _stopStatusPolling();
    super.dispose();
  }
}

class _AdminActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AdminActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceLight,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProblemHeader extends StatelessWidget {
  final VoidCallback onPublishTap;
  final VoidCallback onSaveTap;
  final VoidCallback onProfileTap;
  final VoidCallback onShareTap;
  final VoidCallback onLoadMyDesignsTap;
  final VoidCallback onNotificationsTap;
  final int notificationCount;
  final AsyncValue<Map<String, dynamic>?> profile;
  final bool isAdmin;
  final VoidCallback? onAdminTap;

  const _ProblemHeader({
    required this.onPublishTap, 
    required this.onSaveTap, 
    required this.onProfileTap,
    required this.onShareTap,
    required this.onLoadMyDesignsTap,
    required this.onNotificationsTap,
    required this.notificationCount,
    required this.profile,
    this.isAdmin = false,
    this.onAdminTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 900;
    final spacing = SizedBox(width: isCompact ? 6 : 12);
    final actionStyle = TextButton.styleFrom(foregroundColor: AppTheme.primary);
    final adminStyle = TextButton.styleFrom(foregroundColor: AppTheme.warning);

    Widget btn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool admin = false,
    }) {
      if (isCompact) {
        return IconButton(
          tooltip: label,
          icon: Icon(icon, size: 20, color: admin ? AppTheme.warning : AppTheme.primary),
          onPressed: onTap,
        );
      }
      return TextButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
        style: admin ? adminStyle : actionStyle,
      );
    }

    final profileChip = profile.maybeWhen(
      data: (p) {
        if (p == null) return const SizedBox.shrink();
        final name = p['display_name'] ?? 'Architect';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: AppTheme.primary,
                child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
              ],
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          // Back button removed per request
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(builder: (context, ref, _) {
                return btn(
                  icon: Icons.auto_awesome_mosaic_outlined,
                  label: 'AUTO LAYOUT',
                  onTap: () => ref.read(canvasProvider.notifier).autoLayout(MediaQuery.of(context).size),
                );
              }),
              spacing,
              btn(
                icon: Icons.local_library_rounded,
                label: 'LIBRARY',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommunityScreen())),
              ),
              if (isAdmin && onAdminTap != null) ...[
                spacing,
                btn(
                  icon: Icons.admin_panel_settings,
                  label: 'ADMIN',
                  onTap: onAdminTap!,
                  admin: true,
                ),
              ],
              spacing,
              btn(
                icon: Icons.folder_shared_outlined,
                label: 'MY DESIGNS',
                onTap: onLoadMyDesignsTap,
              ),
              spacing,
              btn(
                icon: Icons.link_rounded,
                label: 'SHARE',
                onTap: onShareTap,
              ),
              spacing,
              btn(
                icon: Icons.save_outlined,
                label: 'SAVE',
                onTap: onSaveTap,
              ),
              spacing,
              if (!isCompact) profileChip,
              spacing,
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(Icons.rocket_launch_rounded, size: isCompact ? 16 : 18),
              label: Text('PUBLISH', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: isCompact ? 12 : 14)),
              onPressed: onPublishTap,
            ),
            spacing,
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: AppTheme.textSecondary),
                  tooltip: 'Notifications',
                  onPressed: onNotificationsTap,
                ),
                if (notificationCount > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        notificationCount > 9 ? '9+' : '$notificationCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            spacing,
            IconButton(
              icon: const Icon(Icons.person_outline_rounded, color: AppTheme.textSecondary),
              tooltip: 'Account',
              onPressed: onProfileTap,
            ),
            ],
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

class _RejectionNotice {
  final String id;
  final String title;
  final String reason;
  const _RejectionNotice({required this.id, required this.title, required this.reason});
}
