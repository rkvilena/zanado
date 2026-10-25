import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/features/transfer/home_screen.dart';
import 'package:zanado/features/transfer/receiver_screen.dart';
import 'package:zanado/features/transfer/sender_screen.dart';

/// App-shell navigation test for MVP 3 Phase 3A: home shows SEND/RECEIVE and
/// routes to the sender workflow / receiver placeholder.
void main() {
  testWidgets('home navigates to sender and receiver screens',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: HomeScreen())));

    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.byType(SenderScreen), findsOneWidget);
    expect(find.text('Pick a file to send'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiverScreen), findsOneWidget);
  });
}
