import 'dart:convert';
import 'dart:io';

import '../../core/constants/transfer_protocol.dart';
import '../../core/utils/checksum.dart';
import '../../domain/models/stored_file.dart';
import '../../domain/repositories/storage_repository.dart';

/// Result of a receiver download attempt (Phase 2C).
sealed class DownloadOutcome {
  const DownloadOutcome();
}

class DownloadSuccess extends DownloadOutcome {
  const DownloadSuccess({
    required this.file,
    required this.expectedChecksum,
    required this.actualChecksum,
  });

  final StoredFile file;

  /// Digest the sender claimed (from `X-Zanado-Checksum`).
  final String expectedChecksum;

  /// Digest computed over the received bytes.
  final String actualChecksum;
}

enum DownloadFailureKind {
  /// Never reached the sender (host unreachable, refused, HTTP error).
  connection,

  /// Sender responded but violated the wire contract (missing/malformed
  /// required headers).
  protocol,

  /// Sender rejected the request per the 2A status contract (401/403/404/409/400).
  rejectedBySender,

  /// Received byte count differs from the declared Content-Length.
  sizeMismatch,

  /// Stream completed but the computed sha-256 differs from the claimed one.
  /// The partially committed file has been deleted.
  checksumMismatch,

  /// Storage layer failed to persist the received bytes.
  storage,
}

class DownloadFailure extends DownloadOutcome {
  const DownloadFailure(
    this.kind, {
    this.errorCode,
    required this.message,
  });

  final DownloadFailureKind kind;

  /// Machine-readable code from the sender's error body, when identifiable.
  final TransferErrorCode? errorCode;
  final String message;

  @override
  String toString() =>
      'DownloadFailure($kind, ${errorCode?.wireName}, $message)';
}

/// Receiver-side downloader (Phase 2C, Module B): fetches one file from a
/// sender `TransferServer` over the Phase 2A contract and commits it through
/// the storage abstraction.
///
/// Flow: request with token + protocol headers → non-200 mapped to
/// [DownloadFailureKind.rejectedBySender] → 200 streamed through a
/// [Sha256StreamSink] tee into `saveStream` (size checked against
/// Content-Length, `.part`-then-rename) → checksum verified after commit;
/// a mismatch deletes the stored file so corrupt bytes never persist.
class TransferReceiver {
  TransferReceiver({
    required this.storage,
    this.connectTimeout = const Duration(seconds: 10),
  });

  final StorageRepository storage;
  final Duration connectTimeout;

  Future<DownloadOutcome> download({
    required String host,
    required int port,
    required String token,
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final request = await client.getUrl(
        Uri.http('$host:$port', TransferProtocol.filePath),
      );
      request.headers
        ..set(TransferProtocol.versionHeader, '${TransferProtocol.version}')
        ..set(TransferProtocol.tokenHeader, token);
      final response = await request.close();

      if (response.statusCode != TransferProtocol.statusOk) {
        final code = await _errorCodeFrom(response);
        return DownloadFailure(
          DownloadFailureKind.rejectedBySender,
          errorCode: code,
          message: 'Sender rejected the download '
              '(HTTP ${response.statusCode}${code == null ? '' : ', ${code.wireName}'})',
        );
      }

      final nameHeader =
          response.headers.value(TransferProtocol.fileNameHeader);
      if (nameHeader == null || nameHeader.isEmpty) {
        return const DownloadFailure(
          DownloadFailureKind.protocol,
          message: 'Sender did not send the file-name header',
        );
      }
      final fileName = Uri.decodeComponent(nameHeader);

      final checksumHeader =
          response.headers.value(TransferProtocol.checksumHeader);
      final expectedChecksum = checksumHeader?.trim().toLowerCase();
      if (!ChecksumUtils.isValidFormat(expectedChecksum)) {
        return const DownloadFailure(
          DownloadFailureKind.protocol,
          message: 'Sender sent a missing or malformed sha-256 checksum header',
        );
      }

      // -1 means the sender did not declare a length; let storage accept it.
      final declaredLength = response.contentLength;
      final sink = ChecksumUtils.startStreaming();
      final StoredFile stored;
      try {
        stored = await storage.saveStream(
          _tapped(response, sink),
          fileName,
          expectedSize: declaredLength < 0 ? null : declaredLength,
        );
      } on StorageException catch (e) {
        if (e.message.startsWith('Size mismatch')) {
          return DownloadFailure(
            DownloadFailureKind.sizeMismatch,
            message:
                'Received size differs from the declared Content-Length: ${e.message}',
          );
        }
        return DownloadFailure(DownloadFailureKind.storage, message: e.message);
      }

      final actualChecksum = sink.finalize();
      if (!ChecksumUtils.matches(expectedChecksum, actualChecksum)) {
        // Corrupt bytes must not persist as a completed file.
        await storage.delete(stored.name);
        return DownloadFailure(
          DownloadFailureKind.checksumMismatch,
          message:
              'sha-256 mismatch: expected $expectedChecksum, got $actualChecksum',
        );
      }

      return DownloadSuccess(
        file: stored,
        expectedChecksum: expectedChecksum!,
        actualChecksum: actualChecksum,
      );
    } on SocketException catch (e) {
      return DownloadFailure(DownloadFailureKind.connection, message: e.message);
    } on HttpException catch (e) {
      return DownloadFailure(DownloadFailureKind.connection, message: e.message);
    } finally {
      client.close(force: true);
    }
  }

  /// Reads the JSON error body of a non-200 response and maps it to a
  /// [TransferErrorCode]; an unparsable body still yields a rejection.
  Future<TransferErrorCode?> _errorCodeFrom(HttpClientResponse response) async {
    try {
      final body = await utf8.decoder.bind(response).join();
      final json = jsonDecode(body);
      if (json is Map && json['error'] is String) {
        return TransferErrorCode.fromWireName(json['error'] as String);
      }
    } catch (_) {
      // Body missing or not JSON — the status code alone still identifies it.
    }
    return null;
  }

  /// Passes chunks through untouched while feeding the streaming digest —
  /// hashing without buffering the whole file.
  Stream<List<int>> _tapped(Stream<List<int>> source, Sha256StreamSink sink) {
    return source.map((chunk) {
      sink.add(chunk);
      return chunk;
    });
  }
}
