import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/data/network/transfer_receiver.dart';
import 'package:zanado/data/storage/local_storage_repository.dart';
import 'package:zanado/core/constants/transfer_protocol.dart';
import 'package:zanado/domain/models/stored_file.dart';
import 'package:zanado/domain/models/transfer_payload.dart';
import 'package:zanado/features/transfer/qr_scanner_sheet.dart';
import 'package:zanado/features/transfer/receiver_screen.dart';
import 'package:zanado/features/transfer/transfer_controller.dart';

/// Receiver workflow screen test (MVP 3 Phase 3B): form validation and busy
/// rendering. Byte-level progress itself is covered by the engine
/// integration tests against a live TransferServer.
class _StubReceiver extends TransferReceiver {
  // The stub never writes bytes; the repo only satisfies the constructor.
  _StubReceiver()
      : super(
          storage: LocalStorageRepository(
            baseDirectory: Directory.systemTemp.createTempSync('zanado_stub_'),
          ),
        );

  @override
  Future<DownloadOutcome> download({
    required String host,
    required int port,
    required String token,
    void Function(int bytesReceived, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    onProgress?.call(512, 1024);
    // Hang without a timer (pending fake timers fail widget tests).
    return Completer<DownloadOutcome>().future;
  }
}

/// MVP 5 Phase 5A stub: ends immediately with a checksum-mismatch failure so
/// the dedicated failure card can be checked.
class _ChecksumFailReceiver extends _StubReceiver {
  @override
  Future<DownloadOutcome> download({
    required String host,
    required int port,
    required String token,
    void Function(int bytesReceived, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    return const DownloadFailure(
      DownloadFailureKind.checksumMismatch,
      message: 'sha-256 mismatch: expected a*64, got b*64',
    );
  }
}

/// 3C: first attempt fails with an expired session, the retry succeeds with a
/// duplicate-renamed file, exercising the full recovery path.
class _ScriptedReceiver extends TransferReceiver {
  _ScriptedReceiver()
      : super(
          storage: LocalStorageRepository(
            baseDirectory: Directory.systemTemp.createTempSync('zanado_stub_'),
          ),
        );

  var calls = 0;

  @override
  Future<DownloadOutcome> download({
    required String host,
    required int port,
    required String token,
    void Function(int bytesReceived, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    calls++;
    if (calls == 1) {
      return const DownloadFailure(
        DownloadFailureKind.rejectedBySender,
        errorCode: TransferErrorCode.expiredToken,
        message: 'expired_token',
      );
    }
    return DownloadSuccess(
      file: StoredFile(
        name: 'photo (1).jpg',
        path: '/tmp/photo (1).jpg',
        sizeBytes: 2048,
        savedAt: DateTime(2026),
      ),
      expectedChecksum: 'a' * 64,
      actualChecksum: 'a' * 64,
      wireFileName: 'photo.jpg',
    );
  }
}

void main() {
  testWidgets('empty connection code shows a validation error',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ReceiverScreen())),
    );

    expect(find.text('Download'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.text('Enter the sender IP, port, and token.'), findsOneWidget);
  });

  testWidgets('busy state shows progress card, bytes, and cancel button',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transferReceiverProvider.overrideWithValue(_StubReceiver())],
        child: const MaterialApp(home: ReceiverScreen()),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Sender IP'),
        '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, 'Port'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Token'), 'TOKEN');
    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('512 B of 1.0 KB'), findsOneWidget);
    expect(find.text('Cancel download'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('expired session offers retry; retry surfaces duplicate rename',
      (tester) async {
    final receiver = _ScriptedReceiver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReceiverProvider.overrideWithValue(receiver),
        ],
        child: const MaterialApp(home: ReceiverScreen()),
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextField, 'Sender IP'), '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, 'Port'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Token'), 'TOKEN');
    await tester.tap(find.text('Download'));
    await tester.pump();

    // 3C: expired-token rejection gets recovery guidance, not a raw code.
    expect(find.textContaining('session expired'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.ensureVisible(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(receiver.calls, 2);
    expect(find.textContaining('renamed'), findsOneWidget);
    expect(find.textContaining('checksum verified'), findsOneWidget);
    expect(find.text('Receive another file'), findsOneWidget);

    // Return-to-start clears the result and shows the form again.
    await tester.ensureVisible(find.text('Receive another file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive another file'));
    await tester.pump();

    expect(find.text('Download'), findsOneWidget);
    expect(find.textContaining('Saved'), findsNothing);
  });

  group('QR scanning (MVP 4 Phase 4C)', () {
    // Fake camera surface: a button that "scans" the given code. Keeps every
    // QR test off the real camera plugin (no platform channels in tests).
    QrCameraBuilder fakeCamera(String raw) =>
        (context, onCodeScanned) => FilledButton(
              onPressed: () => onCodeScanned(raw),
              child: const Text('Simulate scan'),
            );

    Future<void> pumpWithCamera(WidgetTester tester, String raw) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            qrCameraBuilderProvider.overrideWithValue(fakeCamera(raw)),
          ],
          child: const MaterialApp(home: ReceiverScreen()),
        ),
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simulate scan'));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    String validUri() => TransferPayload.fromSession(
          host: '192.168.1.7',
          port: 54321,
          token: 'TOKEN1234',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ).toUriString();

    testWidgets('a valid code prefills the connection form', (tester) async {
      await pumpWithCamera(tester, validUri());

      expect(find.widgetWithText(TextField, 'Sender IP'), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, 'Sender IP'),
        ).controller!.text,
        '192.168.1.7',
      );
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, 'Port'),
        ).controller!.text,
        '54321',
      );
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, 'Token'),
        ).controller!.text,
        'TOKEN1234',
      );
      expect(find.textContaining('Connection code filled'), findsOneWidget);
      expect(find.byType(QrScannerSheet), findsNothing);
    });

    testWidgets('an expired code shows recovery guidance', (tester) async {
      final expired = TransferPayload.fromSession(
        host: '192.168.1.7',
        port: 54321,
        token: 'TOKEN1234',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      ).toUriString();
      await pumpWithCamera(tester, expired);

      expect(find.textContaining('session has expired'), findsOneWidget);
      // Nothing was filled — the dead code must not look usable.
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, 'Sender IP'),
        ).controller!.text,
        isEmpty,
      );
    });

    testWidgets('a non-Zanado code is rejected with an explanation',
        (tester) async {
      await pumpWithCamera(tester, 'https://example.com/transfer');

      expect(find.textContaining('not a valid Zanado'), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, 'Sender IP'),
        ).controller!.text,
        isEmpty,
      );
    });

    testWidgets('Enter manually closes the sheet without touching the form',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            qrCameraBuilderProvider.overrideWithValue(fakeCamera(validUri())),
          ],
          child: const MaterialApp(home: ReceiverScreen()),
        ),
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();

      expect(find.byType(QrScannerSheet), findsNothing);
      expect(find.textContaining('Connection code filled'), findsNothing);
    });
  });

  testWidgets('checksum failure shows the dedicated verification-failed card',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReceiverProvider.overrideWithValue(_ChecksumFailReceiver()),
        ],
        child: const MaterialApp(home: ReceiverScreen()),
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextField, 'Sender IP'), '192.168.1.5');
    await tester.enterText(find.widgetWithText(TextField, 'Port'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Token'), 'TOKEN');
    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.text('File verification failed'), findsOneWidget);
    expect(find.textContaining('has been discarded'), findsOneWidget);
    expect(find.textContaining('sha-256 mismatch'), findsOneWidget);
    // The retry button sits below the fold in the scroll view.
    expect(find.text('Try again', skipOffstage: false), findsOneWidget);
  });

  group('paste connection code (Phase 4D)', () {
    String validUri() => TransferPayload.fromSession(
          host: '192.168.1.7',
          port: 54321,
          token: 'TOKEN1234',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ).toUriString();

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ReceiverScreen())),
      );
    }

    void setClipboard(WidgetTester tester, String? text) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return text == null ? null : <String, Object?>{'text': text};
          }
          return null;
        },
      );
    }

    String formHost(WidgetTester tester) => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Sender IP'))
        .controller!
        .text;

    testWidgets('a valid pasted code prefills the connection form',
        (tester) async {
      await pumpScreen(tester);
      setClipboard(tester, validUri());

      await tester.tap(find.text('Paste connection code'));
      await tester.pump();

      expect(formHost(tester), '192.168.1.7');
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Port'))
            .controller!
            .text,
        '54321',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Token'))
            .controller!
            .text,
        'TOKEN1234',
      );
      expect(find.textContaining('Connection code filled'), findsOneWidget);
    });

    testWidgets('a pasted non-Zanado string is rejected with an explanation',
        (tester) async {
      await pumpScreen(tester);
      setClipboard(tester, 'https://example.com/transfer');

      await tester.tap(find.text('Paste connection code'));
      await tester.pump();

      expect(find.textContaining('not a valid Zanado'), findsOneWidget);
      expect(formHost(tester), isEmpty);
    });

    testWidgets('an empty clipboard explains what to do instead',
        (tester) async {
      await pumpScreen(tester);
      setClipboard(tester, null);

      await tester.tap(find.text('Paste connection code'));
      await tester.pump();

      expect(find.textContaining('clipboard is empty'), findsOneWidget);
      expect(formHost(tester), isEmpty);
    });
  });
}