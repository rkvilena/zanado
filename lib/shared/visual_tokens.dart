import 'package:flutter/material.dart';

/// Shared visual tokens (MVP 5 Phase 5B-1). Single source of truth for
/// spacing, shape, and status colors so home/sender/receiver stay coherent
/// across Android and Windows. Values mirror the pre-token rendering; tune
/// in 5B-2/5B-3 with review, not assumption.

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

/// Maximum width of the centered content column. Defined in 5B-1 as a token;
/// applied to the Windows layout in 5B-3.
abstract final class ZanadoLayout {
  static const double maxContentWidth = 640;
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