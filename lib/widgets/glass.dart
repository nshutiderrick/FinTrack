import 'dart:ui';

import 'package:flutter/material.dart';

/// Height of the floating bottom bar and its margin, for things that must
/// sit above it (floating buttons) when a page runs on under it.
const kBottomBarClearance = 80.0;

/// Frosted glass: blurs what is behind it under a see-through tint with a
/// light edge. [tint] defaults to the page background.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.tint, this.radius = 16, this.opacity = 0.55, this.edge});

  final Widget child;
  final Color? tint;
  final double radius;
  final double opacity;

  /// Border colour; light by default.
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = tint ?? scheme.surface;
    final edge = this.edge ?? (scheme.brightness == Brightness.light ? Colors.white : Colors.white24);
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
    // Each shape fades out to nothing at its edge, so none looks cut out.
    Widget blob(double size, double alpha) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            green.withValues(alpha: alpha),
            green.withValues(alpha: 0),
          ],
        ),
      ),
    );
    return Stack(
      children: [
        Positioned(top: -110, right: -90, child: blob(320, 0.30)),
        Positioned(top: 140, left: -120, child: blob(280, 0.22)),
        Positioned(top: 380, right: -100, child: blob(260, 0.16)),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Paints the page colour and [GlassBackdrop] behind every page, so all of
/// them (login included) share the shapes. Scaffolds are see-through in the
/// app theme; each page still covers the one below it.
class BackdropPageTransitions extends PageTransitionsBuilder {
  const BackdropPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => const PageTransitionsTheme().buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: GlassBackdrop(child: child),
    ),
  );
}

/// The app's theme with see-through pages and bars over [BackdropPageTransitions].
ThemeData withBackdrop(ThemeData t) => t.copyWith(
  scaffoldBackgroundColor: Colors.transparent,
  appBarTheme: t.appBarTheme.copyWith(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
  ),
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {for (final p in TargetPlatform.values) p: const BackdropPageTransitions()},
  ),
);
