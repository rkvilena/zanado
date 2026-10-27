import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/constants/transfer_protocol.dart';
import 'package:zanado/core/utils/checksum.dart';
import 'package:zanado/data/network/transfer_receiver.dart';
import 'package:zanado/data/network/transfer_server.dart';
import 'package:zanado/data/storage/local_storage_repository.dart';
import 'package:zanado/domain/models/selected_file.dart';
import 'package:zanado/domain/models/transfer_session.dart';

final _shaA = 'a' * 64;

Future<TransferServer> _serve(
  String content, {
  String name = 'photo.jpg',
  String? shaHex,
  int? sizeBytes,
  DateTime? now,
  Duration? duration,
}) async {
  final srcDir = await Directory.systemTemp.createTemp('zanado_2c_src_');
  final f = File('${srcDir.path}${Platform.pathSeparator}src.bin');
  await f.writeAsString(content);
  final bytes = await f.readAsBytes();
  final server = TransferServer(
    TransferSession.create(
      SelectedFile(
        name: name,
        path: f.path,
        sizeBytes: sizeBytes ?? bytes.length,
        sha256:
            shaHex ?? ChecksumUtils.bytesToHex(sha256.convert(bytes).bytes),
      ),
      now: now,
      duration: duration ?? const Duration(minutes: 5),
    ),
  );
  await server.start();
  return server;
}

void main() {
  final dirs = <Directory>[];
  late Directory storageDir;
  late LocalStorageRepository storage;
  late TransferReceiver receiver;

  setUp(() async {
    storageDir = await Directory.systemTemp.createTemp('zanado_2c_dst_');
    dirs.addAll([storageDir]);
    storage = LocalStorageRepository(baseDirectory: storageDir);
    receiver = TransferReceiver(storage: storage);
  });

  tearDownAll(() async {
    for (final d in dirs) {
      await d.delete(recursive: true).catchError((Object _) => d);
    }
  });

  Future<List<FileSystemEntity>> storedFiles() => storageDir.list().toList();

  group('TransferReceiver progress & cancel (MVP 3 Phase 3B)', () {
    test('reports monotonic byte progress with declared total', () async {
      final content = 'x' * (1024 * 1024);
      final server = await _serve(content, name: 'big.bin');
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final events = <int, int>{};
      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
        onProgress: (received, total) => events[received] = total,
      );

      expect(outcome, isA<DownloadSuccess>());
      expect(events, isNotEmpty);
      expect(events.length, greaterThan(1), reason: '1 MB yields many chunks');
      final totals = events.values.toSet();
      expect(totals, everyElement(content.length));
      final received = events.keys.toList();
      expect(received.first, greaterThan(0));
      expect(received.last, content.length);
      final sorted = [...received]..sort();
      expect(received, sorted, reason: 'progress must be monotonic');
    });

    test('cancel before download yields cancelled outcome', () async {
      final content = 'tiny';
      final server = await _serve(content);
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final token = TransferCancelToken()..cancel();
      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
        cancelToken: token,
      );

      expect(outcome, isA<DownloadFailure>());
      expect(
        (outcome as DownloadFailure).kind,
        DownloadFailureKind.cancelled,
      );
    });

    test('cancel mid-transfer aborts and leaves no stored file', () async {
      final content = 'x' * (1024 * 1024);
      final server = await _serve(content, name: 'mid.bin');
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final token = TransferCancelToken();
      var progressCalls = 0;
      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
        cancelToken: token,
        onProgress: (received, total) {
          progressCalls++;
          // Cancel as soon as the first chunk has arrived.
          if (progressCalls == 1) token.cancel();
        },
      );

      expect(progressCalls, greaterThanOrEqualTo(1));
      expect(outcome, isA<DownloadFailure>());
      expect(
        (outcome as DownloadFailure).kind,
        DownloadFailureKind.cancelled,
      );
      expect(await storedFiles(), isEmpty,
          reason: 'cancelled download must not leave a stored file');
    });
  });

  group('TransferReceiver happy path', () {
    test('downloads, verifies, and commits the file', () async {
      final content = 'Zanado payload © ünïcode 123';
      final server = await _serve(content, name: 'résumé vol 2.txt');
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
      );

      expect(outcome, isA<DownloadSuccess>());
      final success = outcome as DownloadSuccess;
      expect(success.file.name, 'résumé vol 2.txt');
      expect(success.actualChecksum, success.expectedChecksum);
      expect(await File(success.file.path).readAsBytes(),
          utf8.encode(content));
      expect(success.file.sizeBytes, utf8.encode(content).length);
      // No leftover .part temp file.
      expect(await storedFiles(), hasLength(1));
      expect(server.session.status, TransferSessionStatus.completed);
    });

    test('handles duplicate names without overwriting', () async {
      final server1 = await _serve('first', name: 'doc.pdf');
      final server2 = await _serve('second', name: 'doc.pdf');
      addTearDown(() async {
        await server1.stop();
        await server2.stop();
        await File(server1.session.selectedFile.path).parent
            .delete(recursive: true);
        await File(server2.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final r1 = await receiver.download(
          host: '127.0.0.1', port: server1.port!, token: server1.session.token);
      final r2 = await receiver.download(
          host: '127.0.0.1', port: server2.port!, token: server2.session.token);

      expect(r1, isA<DownloadSuccess>());
      expect(r2, isA<DownloadSuccess>());
      expect((r2 as DownloadSuccess).file.name, 'doc (1).pdf');
      expect(await File((r1 as DownloadSuccess).file.path).readAsString(),
          'first');
      expect(await File(r2.file.path).readAsString(), 'second');
    });
  });

  group('TransferReceiver sender rejections', () {
    test('wrong token → rejectedBySender / invalid_token, nothing stored',
        () async {
      final server = await _serve('secret');
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: 'ZZZZ9999ZZZZ9999ZZZZ9999',
      );

      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.rejectedBySender);
      expect(failure.errorCode, TransferErrorCode.invalidToken);
      expect(await storedFiles(), isEmpty);
    });

    test('expired session → rejectedBySender / expired_token', () async {
      final server = await _serve(
        'old',
        now: DateTime.now().subtract(const Duration(minutes: 6)),
        duration: const Duration(minutes: 5),
      );
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
      );

      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.rejectedBySender);
      expect(failure.errorCode, TransferErrorCode.expiredToken);
      expect(await storedFiles(), isEmpty);
    });

    test('missing backing file → rejectedBySender / file_unavailable',
        () async {
      final server = await _serve('ghost');
      await File(server.session.selectedFile.path).delete();
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
      );

      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.rejectedBySender);
      expect(failure.errorCode, TransferErrorCode.fileUnavailable);
      expect(await storedFiles(), isEmpty);
    });

    test('unreachable host → connection failure', () async {
      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: 1, // nothing listens here
        token: 'AAAA2222AAAA2222AAAA2222',
      );
      expect(outcome, isA<DownloadFailure>());
      expect((outcome as DownloadFailure).kind, DownloadFailureKind.connection);
    });
  });

  group('TransferReceiver integrity & concurrency', () {
    test('checksum mismatch → file deleted, nothing persists', () async {
      // Sender metadata claims a bogus digest; the real bytes hash differently.
      final server = await _serve('real content', shaHex: _shaA);
      addTearDown(() async {
        await server.stop();
        await File(server.session.selectedFile.path).parent
            .delete(recursive: true);
      });

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
      );

      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.checksumMismatch);
      expect(failure.errorCode, isNull);
      // The corrupt download must have been removed after commit.
      expect(await storedFiles(), isEmpty);
    });

    test('second receiver during an active download → 409 conflict', () async {
      final srcDir = await Directory.systemTemp.createTemp('zanado_2c_src_');
      dirs.add(srcDir);
      final f = File('${srcDir.path}${Platform.pathSeparator}big.bin');
      final bytes = List<int>.generate(12 * 1024 * 1024, (i) => i % 256);
      await f.writeAsBytes(bytes);
      final server = TransferServer(
        TransferSession.create(SelectedFile(
          name: 'big.bin',
          path: f.path,
          sizeBytes: bytes.length,
          sha256: ChecksumUtils.bytesToHex(sha256.convert(bytes).bytes),
        )),
      );
      await server.start();
      addTearDown(server.stop);

      // Receiver 1 starts but does not finish.
      final client1 = HttpClient();
      final req1 = await client1.openUrl(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}${TransferProtocol.filePath}'),
      );
      req1.headers
        ..set(TransferProtocol.versionHeader, '${TransferProtocol.version}')
        ..set(TransferProtocol.tokenHeader, server.session.token);
      final resp1 = await req1.close();
      expect(resp1.statusCode, TransferProtocol.statusOk);

      // Receiver 2 must be rejected with the protocol conflict code.
      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: server.port!,
        token: server.session.token,
      );
      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.rejectedBySender);
      expect(failure.errorCode, TransferErrorCode.receiverAlreadyConnected);

      // Receiver 1 still gets the complete stream.
      final received = <int>[];
      await resp1.listen(received.addAll).asFuture<void>();
      expect(received, bytes);
      client1.close();
    });
  });

  group('RC-08: receiver idle timeout (stalled connection)', () {
    Future<TransferReceiver> shortIdleReceiver() async {
      final dir = await Directory.systemTemp.createTemp('zanado_6_dst_');
      dirs.add(dir);
      return TransferReceiver(
        storage: LocalStorageRepository(baseDirectory: dir),
        idleTimeout: const Duration(milliseconds: 300),
      );
    }

    List<String> leftovers(String dirPath) => Directory(dirPath)
        .listSync()
        .map((e) => e.path)
        .where((p) => p.endsWith('.part'))
        .toList();

    test('sender never sends headers → connection failure, not a hang',
        () async {
      final receiver = await shortIdleReceiver();
      final storageDir = receiver.storage as LocalStorageRepository;
      final stallServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      stallServer.listen((request) {
        // Deliberately never respond — simulates a half-open connection.
      });
      addTearDown(() => stallServer.close(force: true));

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: stallServer.port,
        token: 'AAAA2222AAAA2222AAAA2222',
      );

      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.connection);
      expect(failure.message, contains('No response'));
      expect(storageDir.directoryPath(), isNotNull);
    });

    test('sender stalls mid-transfer → connection failure, .part cleaned',
        () async {
      final receiver = await shortIdleReceiver();
      final storageDir = receiver.storage as LocalStorageRepository;
      final stallServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      stallServer.listen((request) {
        request.response.headers
          ..set(
            TransferProtocol.fileNameHeader,
            Uri.encodeComponent('photo.jpg'),
          )
          ..set(TransferProtocol.checksumHeader, _shaA);
        request.response.statusCode = TransferProtocol.statusOk;
        request.response.contentLength = 1000;
        request.response.add(List<int>.filled(600, 65));
        request.response.flush();
        // Deliberately never complete — the connection stalls here.
      });
      addTearDown(() => stallServer.close(force: true));

      final outcome = await receiver.download(
        host: '127.0.0.1',
        port: stallServer.port,
        token: 'AAAA2222AAAA2222AAAA2222',
      );

      expect(outcome, isA<DownloadFailure>());
      final failure = outcome as DownloadFailure;
      expect(failure.kind, DownloadFailureKind.connection);
      expect(failure.message, contains('No data received'));
      // No completed file and no .part left behind.
      final dirPath = await storageDir.directoryPath();
      expect(leftovers(dirPath), isEmpty);
      expect(await storageDir.list(), isEmpty);
    });
  });

  group('RC-08: stale .part sweep', () {
    test('cleanupStaleParts removes leftover .part files only', () async {
      final dir = await Directory.systemTemp.createTemp('zanado_6_sweep_');
      final part = File('${dir.path}${Platform.pathSeparator}photo.jpg.part');
      await part.writeAsString('leftover');
      final done = File('${dir.path}${Platform.pathSeparator}photo.jpg');
      await done.writeAsString('done');

      final repo = LocalStorageRepository(baseDirectory: dir);
      await repo.cleanupStaleParts();

      expect(part.existsSync(), isFalse);
      expect(done.existsSync(), isTrue);
      await dir.delete(recursive: true);
    });
  });
}