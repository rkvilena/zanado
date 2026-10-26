import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanado/shared/status_banner.dart';

void main() {
  testWidgets('StatusBanner renders icon, tinted card, and text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBanner(
            icon: Icons.check_circle,
            color: Colors.green,
            text: 'Transfer completed.',
          ),
        ),
      ),
    );

    expect(find.byType(StatusBanner), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Transfer completed.'), findsOneWidget);
  });
}