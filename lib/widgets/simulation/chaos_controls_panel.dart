import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chaos_event.dart';
import '../../models/component.dart';
import '../../providers/game_provider.dart';
import '../../simulation/simulation_engine.dart';
import '../../theme/app_theme.dart';
import 'package:uuid/uuid.dart';

/// Interactive chaos engineering controls for injecting real-world problems during simulation
class ChaosControlsPanel extends ConsumerStatefulWidget {
  const ChaosControlsPanel({super.key});

  @override
  ConsumerState<ChaosControlsPanel> createState() => _ChaosControlsPanelState();
}

class _ChaosControlsPanelState extends ConsumerState<ChaosControlsPanel> {
  bool _isExpanded = false;
  final _uuid = const Uuid();
  final _random = Random();

  void _setSpeed(double speed) {
    ref.read(simulationProvider.notifier).setSpeed(speed);
    ref.read(simulationEngineProvider).updateSpeed(speed);
  }

  void _triggerChaos(ChaosType type) {
    final canvasState = ref.read(canvasProvider);
    final selectedId = canvasState.selectedComponentId;
    final selectedComponent = selectedId != null
        ? canvasState.getComponent(selectedId)
        : null;
    final event = ChaosEvent(
      id: _uuid.v4(),
      type: type,
      startTime: DateTime.now(),
      duration: _getDuration(type),
      parameters: _getParameters(
        type,
        selectedComponent: selectedComponent,
        components: canvasState.components,
      ),
    );

    ref.read(simulationProvider.notifier).addChaosEvent(event);

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(type.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${type.label} activated for ${event.duration.inSeconds}s',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Duration _getDuration(ChaosType type) {
    switch (type) {
      case ChaosType.trafficSpike:
        return const Duration(seconds: 15);
      case ChaosType.networkLatency:
        return const Duration(seconds: 15);
      case ChaosType.networkPartition:
        return const Duration(seconds: 10);
      case ChaosType.databaseSlowdown:
        return const Duration(seconds: 15);
      case ChaosType.cacheMissStorm:
        return const Duration(seconds: 10);
      case ChaosType.componentCrash:
        return const Duration(seconds: 999); // Manual recovery
    }
  }

  Map<String, dynamic> _getParameters(
    ChaosType type, {
    SystemComponent? selectedComponent,
    List<SystemComponent> components = const [],
  }) {
    String? targetId;
    String? region;
    if (selectedComponent != null) {
      targetId = selectedComponent.id;
      region = selectedComponent.config.regions.isNotEmpty
          ? selectedComponent.config.regions.first
          : null;
    }

    if (targetId == null && components.isNotEmpty) {
      final fallback = components[_random.nextInt(components.length)];
      region = fallback.config.regions.isNotEmpty
          ? fallback.config.regions.first
          : region;
    }

    switch (type) {
      case ChaosType.trafficSpike:
        return {'multiplier': 4.0, 'severity': 1.0};
      case ChaosType.networkLatency:
        return {
          'latencyMs': 300,
          if (targetId != null) 'componentId': targetId,
          if (region != null && targetId == null) 'region': region,
          'severity': 1.0,
        };
      case ChaosType.networkPartition:
        return {
          if (targetId != null) 'componentId': targetId,
          if (region != null && targetId == null) 'region': region,
          'severity': 1.0,
        };
      case ChaosType.databaseSlowdown:
        return {
          'multiplier': 8.0,
          if (selectedComponent?.type == ComponentType.database &&
              targetId != null)
            'componentId': targetId,
          'severity': 1.0,
        };
      case ChaosType.cacheMissStorm:
        return {
          'hitRateDrop': 0.9,
          if (selectedComponent?.type == ComponentType.cache &&
              targetId != null)
            'componentId': targetId,
          'severity': 1.0,
        };
      case ChaosType.componentCrash:
        return {if (targetId != null) 'componentId': targetId, 'severity': 1.0};
    }
  }

  @override
  Widget build(BuildContext context) {
    final simState = ref.watch(simulationProvider);
    final activeEvents = simState.activeChaosEvents
        .where((e) => e.isActive)
        .toList();
    final isRunning = simState.isRunning;
    final isCompact = MediaQuery.sizeOf(context).width < 900;

    if (isCompact) {
      return _buildMobilePanel(context, simState, activeEvents, isRunning);
    }
    return _buildDesktopPanel(context, simState, activeEvents, isRunning);
  }

  Widget _buildDesktopPanel(
    BuildContext context,
    SimulationState simState,
    List<ChaosEvent> activeEvents,
    bool isRunning,
  ) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(24),
          color: AppTheme.surface.withOpacity(0.95),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isRunning
                    ? AppTheme.warning.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Active Events Indicators
                if (activeEvents.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: activeEvents
                          .map((event) => _ActiveEventChip(event: event))
                          .toList(),
                    ),
                  ),

                // Controls Row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRunning) ...[
                      // Speed Slider (0-100 scale, mapped to 0x-5x)
                      // 20 = 1x speed
                      SizedBox(
                        width: 160,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                'Speed: ${simState.simulationSpeed.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 24,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppTheme.primary,
                                  inactiveTrackColor: AppTheme.primary
                                      .withOpacity(0.2),
                                  thumbColor: AppTheme.primary,
                                  overlayColor: AppTheme.primary.withOpacity(
                                    0.1,
                                  ),
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  value: (simState.simulationSpeed * 20).clamp(
                                    0,
                                    100,
                                  ),
                                  min: 0,
                                  max: 100,
                                  divisions: 100,
                                  label:
                                      '${simState.simulationSpeed.toStringAsFixed(1)}x',
                                  onChanged: (value) {
                                    final newSpeed = value / 20.0;
                                    _setSpeed(newSpeed);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Show/Hide Errors Toggle
                      Consumer(
                        builder: (context, ref, _) {
                          final canvasState = ref.watch(canvasProvider);
                          final showErrors = canvasState.showErrors;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                showErrors
                                    ? Icons.error_outline
                                    : Icons.visibility_off,
                                size: 16,
                                color: showErrors
                                    ? AppTheme.error
                                    : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                showErrors ? 'Errors' : 'Hidden',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              SizedBox(
                                height: 20,
                                child: FittedBox(
                                  fit: BoxFit.fill,
                                  child: Switch(
                                    value: showErrors,
                                    activeColor: AppTheme.error,
                                    onChanged: (value) {
                                      ref
                                          .read(canvasProvider.notifier)
                                          .setShowErrors(value);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      // Traffic Control Slider (0-500)
                      SizedBox(
                        width: 180,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final canvasState = ref.watch(canvasProvider);
                            final trafficUnits =
                                (canvasState.trafficLevel * 100)
                                    .clamp(0, 500)
                                    .toInt();
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    "Traffic: $trafficUnits",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 24,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: AppTheme.success,
                                      inactiveTrackColor: AppTheme.success
                                          .withOpacity(0.2),
                                      thumbColor: AppTheme.success,
                                      overlayColor: AppTheme.success
                                          .withOpacity(0.1),
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                    ),
                                    child: Slider(
                                      value: trafficUnits.toDouble(),
                                      min: 0,
                                      max: 500,
                                      divisions: 500,
                                      label: "$trafficUnits",
                                      onChanged: (value) {
                                        ref
                                            .read(canvasProvider.notifier)
                                            .setTrafficLevel(value / 100.0);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(width: 12),
                      Container(height: 24, width: 1, color: AppTheme.border),
                      const SizedBox(width: 8),

                      IconButton(
                        onPressed: () =>
                            ref.read(simulationEngineProvider).stop(),
                        icon: const Icon(Icons.stop_circle_outlined),
                        color: AppTheme.error,
                        tooltip: 'Stop Simulation',
                      ),
                      const SizedBox(width: 8),
                      Container(height: 24, width: 1, color: AppTheme.border),
                      const SizedBox(width: 12),
                    ],

                    Text(
                      'CHAOS:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isRunning
                            ? AppTheme.textMuted
                            : AppTheme.textMuted.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ...ChaosType.values.map((type) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IgnorePointer(
                          ignoring: !isRunning,
                          child: Opacity(
                            opacity: isRunning ? 1.0 : 0.4,
                            child: _ChaosIconButton(
                              type: type,
                              onPressed: () => _triggerChaos(type),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobilePanel(
    BuildContext context,
    SimulationState simState,
    List<ChaosEvent> activeEvents,
    bool isRunning,
  ) {
    final bottomOffset = MediaQuery.viewPaddingOf(context).bottom + 92;
    if (!_isExpanded) {
      return Positioned(
        right: 12,
        bottom: bottomOffset,
        child: FloatingActionButton.small(
          heroTag: 'chaos-mobile-toggle',
          tooltip: 'Chaos controls',
          backgroundColor: AppTheme.surface.withValues(alpha: 0.95),
          foregroundColor: isRunning ? AppTheme.warning : AppTheme.textMuted,
          onPressed: () => setState(() => _isExpanded = true),
          child: const Icon(Icons.bolt_outlined),
        ),
      );
    }

    final canvasState = ref.watch(canvasProvider);
    final showErrors = canvasState.showErrors;
    final trafficUnits = (canvasState.trafficLevel * 100)
        .clamp(0, 500)
        .toDouble();

    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomOffset,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(18),
        color: AppTheme.surface.withValues(alpha: 0.97),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRunning
                  ? AppTheme.warning.withValues(alpha: 0.35)
                  : AppTheme.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Chaos Controls',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _isExpanded = false),
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                  ),
                ],
              ),
              if (activeEvents.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: activeEvents
                          .map(
                            (event) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _ActiveEventChip(event: event),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ChaosType.values.map((type) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IgnorePointer(
                        ignoring: !isRunning,
                        child: Opacity(
                          opacity: isRunning ? 1.0 : 0.4,
                          child: _ChaosIconButton(
                            type: type,
                            onPressed: () => _triggerChaos(type),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              if (!isRunning)
                const Text(
                  'Start simulation to activate chaos events.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else ...[
                Row(
                  children: [
                    Text(
                      'Speed ${simState.simulationSpeed.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: (simState.simulationSpeed * 20).clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (value) => _setSpeed(value / 20.0),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'Traffic ${trafficUnits.round()}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: trafficUnits,
                        min: 0,
                        max: 500,
                        divisions: 500,
                        onChanged: (value) {
                          ref
                              .read(canvasProvider.notifier)
                              .setTrafficLevel(value / 100.0);
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(
                      showErrors ? Icons.error_outline : Icons.visibility_off,
                      size: 16,
                      color: showErrors ? AppTheme.error : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Show errors',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: showErrors,
                      activeColor: AppTheme.error,
                      onChanged: (value) {
                        ref.read(canvasProvider.notifier).setShowErrors(value);
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveEventChip extends StatelessWidget {
  final ChaosEvent event;

  const _ActiveEventChip({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(event.type.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            '${event.timeRemaining.inSeconds}s',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.error,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              value: event.progress,
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation(AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChaosIconButton extends StatelessWidget {
  final ChaosType type;
  final VoidCallback onPressed;

  const _ChaosIconButton({required this.type, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: type.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Center(
              child: Text(type.emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveEventCard extends StatelessWidget {
  final ChaosEvent event;

  const _ActiveEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(event.type.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.type.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.timeRemaining.inSeconds}s remaining',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              value: event.progress,
              strokeWidth: 3,
              backgroundColor: AppTheme.error.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChaosButton extends StatefulWidget {
  final ChaosType type;
  final VoidCallback onPressed;

  const _ChaosButton({required this.type, required this.onPressed});

  @override
  State<_ChaosButton> createState() => _ChaosButtonState();
}

class _ChaosButtonState extends State<_ChaosButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppTheme.warning.withValues(alpha: 0.15)
                : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? AppTheme.warning.withValues(alpha: 0.4)
                  : AppTheme.border,
              width: _isHovered ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(widget.type.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.type.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _isHovered ? FontWeight.bold : FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.play_arrow,
                size: 18,
                color: _isHovered ? AppTheme.warning : AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedControlButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _SpeedControlButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.primary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
