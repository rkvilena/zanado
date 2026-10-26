import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanado/shared/visual_tokens.dart';

void main() {
  // Page-level actions are centered compact buttons on Windows desktop and
  // full-width touch bars on Android — decided by platform, not window width.
  testWidgets('Windows centers the action compactly', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZanadoPageAction(
            child: FilledButton(onPressed: null, child: Text('Go')),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byType(FilledButton)).dx, greaterThan(0));
    expect(tester.getSize(find.byType(FilledButton)).width, lessThan(600));
    // Reset before the test body ends: the binding's invariant check runs
    // before tearDowns and rejects leftover foundation debug variables.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android stretches the action full-width', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZanadoPageAction(
            child: FilledButton(onPressed: null, child: Text('Go')),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(FilledButton)).width,
      closeTo(800, 0.01),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}