import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared visual tokens. Single source of truth for
/// spacing, shape, and status colors so home/sender/receiver stay coherent
/// across Android and Windows. Values mirror the pre-token rendering; tune
/// with review, not assumption.

abstract final class ZanadoSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;

  /// Standard outer padding for workflow screens and cards.
  static const EdgeInsets screen = EdgeInsets.all(l);
  static const EdgeInsets card = EdgeInsets.all(l);
  static const EdgeInsets banner = EdgeInsets.all(m);
}

abstract final class ZanadoRadius {
  static const double card = 12;
}

/// Maximum width of the centered content column.
abstract final class ZanadoLayout {
  // 720 px keeps the receiver's side-by-side Scan/Paste buttons on one row
  // with room to spare; below the planned ~600–760 review range top end.
  static const double maxContentWidth = 720;

  /// Desktop width above which the receiver puts Sender IP and Port on one
  /// row; below it the fields stack like the Android layout (narrow window).
  static const double wideFormBreakpoint = 480;

  /// Platform decides the composition (Windows = desktop layout, Android =
  /// single-column touch layout); width only tunes details within it. Width
  /// alone would let a wide tablet and a narrow desktop window swap designs.
  static bool isWindowsDesktop(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.windows;
}

/// Page-level action placement: a centered compact button on Windows desktop
/// (no oversized mobile-style bars), full-width on Android for touch targets.
class ZanadoPageAction extends StatelessWidget {
  const ZanadoPageAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ZanadoLayout.isWindowsDesktop(context)) {
      return Center(child: child);
    }
    return SizedBox(width: double.infinity, child: child);
  }
}

/// Semantic status colors. Centralized in 5B-1 (values identical to the
/// previously hardcoded Material colors) so a later palette change is a
/// one-file edit.
abstract final class ZanadoStatusColors {
  static const Color success = Colors.green;
  static const Color warning = Colors.orange;
  static const Color danger = Colors.red;
}

/// App theme. Kept seed-based so existing rendering is preserved; widget-level
/// refinements (density, typography emphasis) land in 5B-2 after review.
ThemeData buildZanadoTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    cardTheme: const CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ZanadoRadius.card)),
      ),
    ),
  );
}