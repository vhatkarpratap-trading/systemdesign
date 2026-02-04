import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chaos_event.dart';
import '../../theme/app_theme.dart';

class DisasterToolkit extends ConsumerWidget {
  const DisasterToolkit({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 4,
      color: AppTheme.surface.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Icon(Icons.warning_amber_rounded, size: 20, color: AppTheme.textSecondary),
            ),
            _DisasterDraggable(
              type: ChaosType.trafficSpike,
              color: AppTheme.secondary,
              tooltip: 'Traffic Spike',
            ),
            const SizedBox(height: 8),
            _DisasterDraggable(
              type: ChaosType.componentCrash,
              color: AppTheme.error,
              tooltip: 'Crash Component',
            ),
            const SizedBox(height: 8),
            _DisasterDraggable(
              type: ChaosType.networkLatency,
              color: Colors.orange,
              tooltip: 'Inject Latency',
            ),
            // const SizedBox(height: 8),
            // _DisasterDraggable(
            //   type: ChaosType.networkPartition,
            //   color: Colors.grey,
            //   tooltip: 'Sever Connection',
            // ),
          ],
        ),
      ),
    );
  }
}

class _DisasterDraggable extends StatelessWidget {
  final ChaosType type;
  final Color color;
  final String tooltip;

  const _DisasterDraggable({
    required this.type,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<ChaosType>(
      data: type,
      feedback: Transform.scale(
        scale: 1.2,
        child: _buildIcon(context, true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildIcon(context, false),
      ),
      child: Tooltip(
        message: tooltip,
        child: _buildIcon(context, false),
      ),
    );
  }

  Widget _buildIcon(BuildContext context, bool isDragging) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isDragging ? color : AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.6), width: 2),
        boxShadow: isDragging 
            ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]
            : [],
      ),
      child: Center(
        child: Text(
          type.emoji,
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
