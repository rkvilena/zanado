import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:zanado/features/transfer/sender_screen.dart';
import 'package:zanado/features/transfer/transfer_controller.dart';

/// Serving-state controller stub: the QR card renders whenever the session
/// inputs (host/port/token/expiresAt) are present, so no server is needed.
class _ServingSenderController extends SenderController {
  @override
  SenderState build() => SenderState(
        phase: SenderPhase.serving,
        fileName: 'photo.jpg',
        fileSizeBytes: 1024,
        lanAddress: InternetAddress('192.168.1.10'),
        port: 54321,
        token: 'TOKEN1234',
        expiresAt: DateTime(2026),
      );
}

/// Idle-state controller stub: nothing is serving, so no QR may appear.
class _IdleSenderController extends SenderController {
  @override
  SenderState build() => const SenderState();
}

void main() {
  testWidgets('serving state renders the QR card with the transfer payload',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          senderControllerProvider.overrideWith(_ServingSenderController.new),
        ],
        child: const MaterialApp(home: SenderScreen()),
      ),
    );

    expect(find.text('Receiver scans this to connect:'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('idle state renders no QR card', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          senderControllerProvider.overrideWith(_IdleSenderController.new),
        ],
        child: const MaterialApp(home: SenderScreen()),
      ),
    );

    expect(find.text('Receiver scans this to connect:'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });
}
