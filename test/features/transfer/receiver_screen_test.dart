import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/data/network/transfer_receiver.dart';
import 'package:zanado/data/storage/local_storage_repository.dart';
import 'package:zanado/core/constants/transfer_protocol.dart';
import 'package:zanado/domain/models/stored_file.dart';
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

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(receiver.calls, 2);
    expect(find.textContaining('renamed'), findsOneWidget);
    expect(find.textContaining('checksum verified'), findsOneWidget);
    expect(find.text('Receive another file'), findsOneWidget);

    // Return-to-start clears the result and shows the form again.
    await tester.tap(find.text('Receive another file'));
    await tester.pump();

    expect(find.text('Download'), findsOneWidget);
    expect(find.textContaining('Saved'), findsNothing);
  });
}