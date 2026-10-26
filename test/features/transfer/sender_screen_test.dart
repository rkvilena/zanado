import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('serving state copies the full connection code to the clipboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          senderControllerProvider.overrideWith(_ServingSenderController.new),
        ],
        child: const MaterialApp(home: SenderScreen()),
      ),
    );

    await tester.ensureVisible(find.text('Copy full connection code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy full connection code'));
    await tester.pump();

    expect(
      copied,
      startsWith(
        'zanado://transfer?host=192.168.1.10&port=54321&token=TOKEN1234&expires=',
      ),
    );
    expect(find.textContaining('Full connection code copied'), findsOneWidget);
  });

  testWidgets('idle state offers no full-code copy', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          senderControllerProvider.overrideWith(_IdleSenderController.new),
        ],
        child: const MaterialApp(home: SenderScreen()),
      ),
    );

    expect(find.text('Copy full connection code'), findsNothing);
  });
}
