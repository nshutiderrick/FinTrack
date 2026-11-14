import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted glass: blurs what is behind it under a see-through tint with a
/// light edge. [tint] defaults to the page background.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.tint, this.radius = 16, this.opacity = 0.55});

  final Widget child;
  final Color? tint;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = tint ?? scheme.surface;
    final edge = scheme.brightness == Brightness.light ? Colors.white : Colors.white24;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base.withValues(alpha: opacity + 0.15),
                base.withValues(alpha: opacity),
              ],
            ),
            border: Border.all(color: edge.withValues(alpha: 0.45)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Soft green shapes behind a page, so the glass on top has something to blur.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.secondary;
    Widget blob(double size, double alpha) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: green.withValues(alpha: alpha),
      ),
    );
    return Stack(
      children: [
        Positioned(top: -60, right: -40, child: blob(220, 0.35)),
        Positioned(top: 180, left: -70, child: blob(180, 0.25)),
        Positioned(top: 420, right: -50, child: blob(160, 0.18)),
        Positioned.fill(child: child),
      ],
    );
  }
}
