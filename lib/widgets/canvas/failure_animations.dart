import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Animation wrappers for visual failure feedback

/// Pulsing border animation for errors
class PulsingWrapper extends StatefulWidget {
  final Widget child;
  final Color color;

  const PulsingWrapper({super.key, required this.child, required this.color});

  @override
  State<PulsingWrapper> createState() => _PulsingWrapperState();
}

class _PulsingWrapperState extends State<PulsingWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3 * _controller.value),
                blurRadius: 20 + (10 * _controller.value),
                spreadRadius: 3 + (3 * _controller.value),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Shaking animation for overloaded components
class ShakingWrapper extends StatefulWidget {
  final Widget child;

  const ShakingWrapper({super.key, required this.child});

  @override
  State<ShakingWrapper> createState() => _ShakingWrapperState();
}

class _ShakingWrapperState extends State<ShakingWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = math.sin(_controller.value * 2 * math.pi) * 2;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Scaling pulse for autoscaling components
class ScalingPulseWrapper extends StatefulWidget {
  final Widget child;

  const ScalingPulseWrapper({super.key, required this.child});

  @override
  State<ScalingPulseWrapper> createState() => _ScalingPulseWrapperState();
}

class _ScalingPulseWrapperState extends State<ScalingPulseWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (0.05 * _controller.value);
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
