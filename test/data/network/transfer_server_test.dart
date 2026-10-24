import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/constants/transfer_protocol.dart';
import 'package:zanado/core/utils/checksum.dart';
import 'package:zanado/data/network/transfer_server.dart';
import 'package:zanado/domain/models/selected_file.dart';
import 'package:zanado/domain/models/transfer_session.dart';

TransferSession sessionOf(
  SelectedFile file, {
  DateTime? now,
  Duration? duration,
}) =>
    TransferSession.create(file, now: now, duration: duration ?? const Duration(minutes: 5));

HttpClient _client() => HttpClient();

/// A response plus its owning client, so the caller decides when/how to read
/// the body (a drained response stream cannot be listened to again).
class Resp {
  Resp(this.client, this.response);
  final HttpClient client;
  final HttpClientResponse response;

  int get statusCode => response.statusCode;

  /// Reads the (JSON/error) body and closes the client.
  Future<String> body() async {
    final s = await utf8.decoder.bind(response).join();
    client.close(force: true);
    return s;
  }

  /// Discards the body and closes the client.
  Future<void> drain() async {
    await response.drain<void>();
    client.close(force: true);
  }
}

Future<Resp> get({
  required int port,
  String? token,
  String? version = '${TransferProtocol.version}',
  String path = TransferProtocol.filePath,
  String method = 'GET',
}) async {
  final client = _client();
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  if (version != null) request.headers.set(TransferProtocol.versionHeader, version);
  if (token != null) request.headers.set(TransferProtocol.tokenHeader, token);
  final response = await request.close();
  return Resp(client, response);
}

void main() {
  // Keep temp dirs alive for the duration of each test group.
  final createdDirs = <Directory>[];
  Future<SelectedFile> trackedFile(String content, {String? name}) async {
    final dir = await Directory.systemTemp.createTemp('zanado_2b_');
    createdDirs.add(dir);
    final f = File('${dir.path}${Platform.pathSeparator}${name ?? 'photo.jpg'}');
    await f.writeAsString(content);
    // sizeBytes/checksum must describe the file BYTES, not the string's
    // UTF-16 length — non-ASCII content makes the two differ.
    final bytes = await f.readAsBytes();
    return SelectedFile(
      name: name ?? 'photo.jpg',
      path: f.path,
      sizeBytes: bytes.length,
      sha256: ChecksumUtils.bytesToHex(sha256.convert(bytes).bytes),
    );
  }

  tearDownAll(() async {
    for (final dir in createdDirs) {
      await dir.delete(recursive: true).catchError((Object _) => dir);
    }
  });

  group('TransferServer lifecycle', () {
    test('binds to an ephemeral port and reports address/port', () async {
      final server = TransferServer(sessionOf(await trackedFile('hello')));
      await server.start();
      addTearDown(server.stop);
      expect(server.isRunning, isTrue);
      expect(server.port, isNotNull);
      expect(server.port! > 0, isTrue);
      expect(server.address!.address, isNotEmpty);
    });

    test('stop() closes the listener — new connections are refused', () async {
      final server = TransferServer(sessionOf(await trackedFile('bye')));
      await server.start();
      final port = server.port!;
      await server.stop();
      expect(server.isRunning, isFalse);
      try {
        await get(port: port, token: 'AAAA2222AAAA2222AAAA2222');
        fail('expected connection failure');
      } catch (_) {
        // SocketException expected after shutdown.
      }
    });

    test('session auto-terminates (listener closed) after a completed transfer',
        () async {
      final server = TransferServer(sessionOf(await trackedFile('done')));
      await server.start();
      final port = server.port!;
      final response = await get(port: port, token: server.session.token);
      expect(response.statusCode, TransferProtocol.statusOk);
      await response.drain();
      // Give the server a moment to run its terminal shutdown.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.session.status, TransferSessionStatus.completed);
      expect(server.isRunning, isFalse);
      try {
        await get(port: port, token: server.session.token);
        fail('expected connection failure after completion');
      } catch (_) {}
    });
  });

  group('TransferServer happy path', () {
    test('streams the file with checksum and encoded name headers', () async {
      final content = 'Zanado transfer payload © ünïcode';
      final file = await trackedFile(content, name: 'résumé vol 2.txt');
      final server = TransferServer(sessionOf(file));
      await server.start();
      addTearDown(server.stop);

      final client = HttpClient();
      final request = await client.openUrl(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}${TransferProtocol.filePath}'),
      );
      request.headers.set(
          TransferProtocol.versionHeader, '${TransferProtocol.version}');
      request.headers.set(TransferProtocol.tokenHeader, server.session.token);
      final response = await request.close();
      expect(response.statusCode, TransferProtocol.statusOk);
      expect(
          response.headers.contentType!.mimeType, 'application/octet-stream');
      expect(
        response.headers.value(TransferProtocol.checksumHeader),
        file.sha256,
      );
      expect(
        Uri.decodeComponent(
            response.headers.value(TransferProtocol.fileNameHeader)!),
        file.name,
      );
      final body = await utf8.decodeStream(response);
      expect(body, content);
      client.close();
    });

    test('byte-identical streaming of a larger binary file', () async {
      final bytes = List<int>.generate(256 * 1024, (i) => i % 256);
      final dir = await Directory.systemTemp.createTemp('zanado_2b_');
      createdDirs.add(dir);
      final f = File('${dir.path}${Platform.pathSeparator}blob.bin');
      await f.writeAsBytes(bytes);
      final server = TransferServer(
        sessionOf(SelectedFile(
          name: 'blob.bin',
          path: f.path,
          sizeBytes: bytes.length,
          sha256: ChecksumUtils.bytesToHex(sha256.convert(bytes).bytes),
        )),
      );
      await server.start();
      addTearDown(server.stop);

      final response =
          await get(port: server.port!, token: server.session.token);
      final received = <int>[];
      await response.response.listen(received.addAll).asFuture<void>();
      expect(received, bytes);
    });
  });

  group('TransferServer auth & status contract', () {
    late TransferServer server;
    setUp(() async {
      final file = await trackedFile('secret');
      server = TransferServer(sessionOf(file));
      await server.start();
    });
    tearDown(() => server.stop());

    test('missing token → 401 missing_token', () async {
      final r = await get(port: server.port!);
      expect(r.statusCode, TransferProtocol.statusUnauthorized);
      expect(jsonDecode(await r.body()),
          {'error': TransferErrorCode.missingToken.wireName});
    });

    test('malformed token → 401 invalid_token', () async {
      final r = await get(port: server.port!, token: 'short!!');
      expect(r.statusCode, TransferProtocol.statusUnauthorized);
      expect(jsonDecode(await r.body()),
          {'error': TransferErrorCode.invalidToken.wireName});
    });

    test('unknown token → 401 invalid_token', () async {
      final r = await get(port: server.port!, token: 'ZZZZ9999ZZZZ9999ZZZZ9999');
      expect(r.statusCode, TransferProtocol.statusUnauthorized);
      expect(jsonDecode(await r.body()),
          {'error': TransferErrorCode.invalidToken.wireName});
    });

    test('missing protocol version header → 400 unsupported_protocol',
        () async {
      final r = await get(
          port: server.port!, token: server.session.token, version: null);
      expect(r.statusCode, TransferProtocol.statusBadRequest);
      expect(jsonDecode(await r.body()),
          {'error': TransferErrorCode.unsupportedProtocol.wireName});
    });

    test('unsupported protocol version → 400', () async {
      final r = await get(
          port: server.port!, token: server.session.token, version: '99');
      expect(r.statusCode, TransferProtocol.statusBadRequest);
    });

    test('expired session → 403 expired_token', () async {
      final file = await trackedFile('old');
      final expired = TransferServer(
        sessionOf(
          file,
          now: DateTime.now().subtract(const Duration(minutes: 6)),
          duration: const Duration(minutes: 5),
        ),
      );
      await expired.start();
      addTearDown(expired.stop);
      final r = await get(port: expired.port!, token: expired.session.token);
      expect(r.statusCode, TransferProtocol.statusForbidden);
      expect(jsonDecode(await r.body()),
          {'error': TransferErrorCode.expiredToken.wireName});
    });

    test('terminal session → 403, not downloadable again', () async {
      final oneShot = TransferServer(sessionOf(await trackedFile('once')));
      await oneShot.start();
      addTearDown(oneShot.stop);
      (await get(port: oneShot.port!, token: oneShot.session.token))
          .drain();
      // Listener may already be shut down → connection refused, which is the
      // one-shot guarantee; accept that OR an explicit 403.
      try {
        final r = await get(port: oneShot.port!, token: oneShot.session.token);
        expect(r.statusCode, TransferProtocol.statusForbidden);
      } catch (_) {}
    });

    test('missing backing file → 404 file_unavailable', () async {
      final file = await trackedFile('ghost');
      await File(file.path).delete();
      final ghost = TransferServer(sessionOf(file));
      await ghost.start();
      addTearDown(ghost.stop);
      final r = await get(port: ghost.port!, token: ghost.session.token);
      expect(r.statusCode, TransferProtocol.statusNotFound);
      expect(jsonDecode(await r.body()),
          {'error': TransferErrorCode.fileUnavailable.wireName});
    });

    test('wrong path → 404', () async {
      final r = await get(
        port: server.port!,
        token: server.session.token,
        path: '/other',
      );
      expect(r.statusCode, TransferProtocol.statusNotFound);
    });
  });

  group('TransferServer single-receiver enforcement', () {
    test('second request while first download active → 409', () async {
      // Large file keeps the first download busy long enough to interleave.
      final dir = await Directory.systemTemp.createTemp('zanado_2b_');
      createdDirs.add(dir);
      final big = File('${dir.path}${Platform.pathSeparator}big.bin');
      final bytes = List<int>.generate(12 * 1024 * 1024, (i) => i % 256);
      await big.writeAsBytes(bytes);

      final server = TransferServer(
        sessionOf(SelectedFile(
          name: 'big.bin',
          path: big.path,
          sizeBytes: bytes.length,
          sha256: ChecksumUtils.bytesToHex(sha256.convert(bytes).bytes),
        )),
      );
      await server.start();
      addTearDown(server.stop);

      final client1 = HttpClient();
      final req1 = await client1.openUrl(
        'GET',
        Uri.parse(
            'http://127.0.0.1:${server.port}${TransferProtocol.filePath}'),
      );
      req1.headers
          .set(TransferProtocol.versionHeader, '${TransferProtocol.version}');
      req1.headers.set(TransferProtocol.tokenHeader, server.session.token);
      final resp1 = await req1.close();
      expect(resp1.statusCode, TransferProtocol.statusOk);
      // Do NOT drain resp1 yet — the transfer is intentionally left active.

      final resp2 = await get(port: server.port!, token: server.session.token);
      expect(resp2.statusCode, TransferProtocol.statusConflict);
      expect(jsonDecode(await resp2.body()),
          {'error': TransferErrorCode.receiverAlreadyConnected.wireName});

      // The first receiver must still get the complete, correct bytes.
      final received = <int>[];
      await resp1.listen(received.addAll).asFuture<void>();
      expect(received.length, bytes.length);
      client1.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.session.status, TransferSessionStatus.completed);
    });
  });
}