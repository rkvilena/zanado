import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/utils/checksum.dart';
import 'package:zanado/data/network/transfer_receiver.dart';
import 'package:zanado/data/network/transfer_server.dart';
import 'package:zanado/data/storage/local_storage_repository.dart';
import 'package:zanado/data/storage/storage_providers.dart';
import 'package:zanado/domain/models/selected_file.dart';
import 'package:zanado/domain/models/transfer_session.dart';
import 'package:zanado/features/transfer/transfer_controller.dart';

/// Controller-level integration proof for Phase 2D: real picker bypass
/// (metadata injected), real TransferServer, real TransferReceiver, real
/// LocalStorageRepository — the exact components the device flow will use.
void main() {
  test('sender controller serves; receiver controller downloads and verifies',
      () async {
    final srcDir = await Directory.systemTemp.createTemp('zanado_2d_src_');
    final dstDir = await Directory.systemTemp.createTemp('zanado_2d_dst_');
    addTearDown(() async {
      await srcDir.delete(recursive: true);
      await dstDir.delete(recursive: true);
    });

    final content = List<int>.generate(3 * 1024 * 1024, (i) => i % 251);
    final source = File('${srcDir.path}${Platform.pathSeparator}payload.bin');
    await source.writeAsBytes(content);

    final container = ProviderContainer(overrides: [
      storageRepositoryProvider
          .overrideWithValue(LocalStorageRepository(baseDirectory: dstDir)),
    ]);
    addTearDown(container.dispose);

    // Sender: bypass FilePicker (unavailable in tests) by injecting metadata
    // computed exactly like SenderController.pickFile does.
    final sender = container.read(senderControllerProvider.notifier);
    sender.injectFileForTest(SelectedFile(
      name: 'payload.bin',
      path: source.path,
      sizeBytes: content.length,
      sha256: _sha256Hex(content),
    ));
    await sender.startServing();
    final senderState = container.read(senderControllerProvider);
    expect(senderState.phase, SenderPhase.serving);
    expect(senderState.port, isNotNull);
    expect(senderState.token, isNotNull);
    expect(senderState.fileSizeBytes, content.length);
    expect(senderState.expiresAt, isNotNull);

    // Receiver: same path the UI uses.
    final receiver = container.read(receiverControllerProvider.notifier);
    await receiver.download(
      '127.0.0.1',
      '${senderState.port}',
      senderState.token!,
    );

    final receiverState = container.read(receiverControllerProvider);
    final outcome = receiverState.outcome;
    expect(outcome, isA<DownloadSuccess>());
    // 3B: live progress must have tracked the full transfer.
    expect(receiverState.bytesReceived, content.length);
    expect(receiverState.totalBytes, content.length);
    final stored = (outcome as DownloadSuccess).file;
    expect(stored.name, 'payload.bin');
    expect(await File(stored.path).readAsBytes(), content);

    // The one-shot sender must observe the terminal state shortly after,
    // including the connected flag the 3A UI status row uses.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final after = container.read(senderControllerProvider);
    expect(after.phase, SenderPhase.completed);
    expect(after.receiverConnected, isTrue);
  });

  test('receiver controller surfaces sender rejection', () async {
    final dstDir = await Directory.systemTemp.createTemp('zanado_2d_dst2_');
    addTearDown(() => dstDir.delete(recursive: true));

    final container = ProviderContainer(overrides: [
      storageRepositoryProvider
          .overrideWithValue(LocalStorageRepository(baseDirectory: dstDir)),
    ]);
    addTearDown(container.dispose);

    final srcDir = await Directory.systemTemp.createTemp('zanado_2d_src2_');
    addTearDown(() => srcDir.delete(recursive: true));
    final source = File('${srcDir.path}${Platform.pathSeparator}f.txt');
    await source.writeAsString('hello');

    final server = TransferServer(
      TransferSession.create(SelectedFile(
        name: 'f.txt',
        path: source.path,
        sizeBytes: 5,
        sha256: _sha256Hex('hello'.codeUnits),
      )),
    );
    await server.start();
    addTearDown(server.stop);

    final receiver = container.read(receiverControllerProvider.notifier);
    await receiver.download('127.0.0.1', '${server.port}', 'WRONGWRONGWRONG');

    final outcome = container.read(receiverControllerProvider).outcome;
    expect(outcome, isA<DownloadFailure>());
    expect((outcome as DownloadFailure).kind,
        DownloadFailureKind.rejectedBySender);
  });
}

String _sha256Hex(List<int> bytes) =>
    ChecksumUtils.bytesToHex(sha256.convert(bytes).bytes);