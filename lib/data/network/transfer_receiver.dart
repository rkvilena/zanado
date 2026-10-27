import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/transfer_protocol.dart';
import '../../core/utils/checksum.dart';
import '../../domain/models/stored_file.dart';
import '../../domain/repositories/storage_repository.dart';

// RC-03 diagnostic phase markers removed 2026-10-28 after the ANR fix was
// device-verified (synchronous multi-GB MediaStore copy moved off the main
// thread in MainActivity.kt).

/// Result of a receiver download attempt (Phase 2C).
sealed class DownloadOutcome {
  const DownloadOutcome();
}

class DownloadSuccess extends DownloadOutcome {
  const DownloadSuccess({
    required this.file,
    required this.expectedChecksum,
    required this.actualChecksum,
    this.wireFileName = '',
  });

  final StoredFile file;

  /// Digest the sender claimed (from `X-Zanado-Checksum`).
  final String expectedChecksum;

  /// Digest computed over the received bytes.
  final String actualChecksum;

  /// Name the sender declared in `X-Zanado-File-Name`, before the storage
  /// layer's duplicate rename (`photo.jpg` → `photo (1).jpg`). The UI
  /// compares it with [StoredFile.name] to surface renames.
  final String wireFileName;
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

  /// The user cancelled the download on the receiver side; the partial file
  /// is cleaned up by the storage layer's interrupted-stream handling.
  cancelled,
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

/// Co-operative cancellation handle for a receiver download (MVP 3 Phase 3B).
/// The receiver checks it between chunks; cancelling aborts the stream and
/// yields a `DownloadFailureKind.cancelled` outcome.
class TransferCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
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
    this.idleTimeout = const Duration(seconds: 30),
  });

  final StorageRepository storage;
  final Duration connectTimeout;

  /// Max gap between received body chunks (and the wait for the response
  /// headers). A stalled/half-open connection — e.g. Wi-Fi dropped mid-transfer
  /// — never produces a socket error, so without this the receiver would hang
  /// on the download loop until the user manually aborts (RC-08).
  final Duration idleTimeout;

  /// [onProgress] fires once per received chunk with the running byte count;
  /// `totalBytes` is the declared Content-Length, or -1 when the sender did
  /// not declare one. Optional [cancelToken] enables co-operative
  /// cancellation (MVP 3 Phase 3B). No stage callbacks: the streamed sha-256
  /// is computed per chunk (MVP 5A revision), so the only post-download wait
  /// is disk flush/rename inside the storage layer — no honest UI state
  /// exists for it.
  Future<DownloadOutcome> download({
    required String host,
    required int port,
    required String token,
    void Function(int bytesReceived, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      return const DownloadFailure(
        DownloadFailureKind.cancelled,
        message: 'Download cancelled before it started',
      );
    }
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final request = await client.getUrl(
        Uri.http('$host:$port', TransferProtocol.filePath),
      );
      request.headers
        ..set(TransferProtocol.versionHeader, '${TransferProtocol.version}')
        ..set(TransferProtocol.tokenHeader, token);
      final response = await request.close().timeout(idleTimeout, onTimeout: () {
        throw _IdleTimeoutException(
          'No response from the sender within ${idleTimeout.inSeconds}s',
        );
      });

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
          _tapped(
            _idleWatched(response),
            sink,
            onProgress: onProgress,
            cancelToken: cancelToken,
            totalBytes: declaredLength,
          ),
          fileName,
          expectedSize: declaredLength < 0 ? null : declaredLength,
        );
      } on StorageException catch (e) {
        // saveStream wraps source-stream errors; a transport failure must
        // surface as a connection failure, not storage (2E finding).
        final cause = e.cause;
        if (cause is _CancelledException) {
          return const DownloadFailure(
            DownloadFailureKind.cancelled,
            message: 'Download cancelled',
          );
        }
        if (cause is SocketException) {
          return DownloadFailure(DownloadFailureKind.connection,
              message: cause.message);
        }
        if (cause is HttpException) {
          return DownloadFailure(DownloadFailureKind.connection,
              message: cause.message);
        }
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
        wireFileName: fileName,
      );
    } on SocketException catch (e) {
      return DownloadFailure(DownloadFailureKind.connection, message: e.message);
    } on HttpException catch (e) {
      return DownloadFailure(DownloadFailureKind.connection, message: e.message);
    } on _IdleTimeoutException catch (e) {
      return DownloadFailure(DownloadFailureKind.connection, message: e.message);
    } finally {
      client.close(force: true);
    }
  }

  Stream<List<int>> _idleWatched(Stream<List<int>> body) {
    return body.timeout(
      idleTimeout,
      onTimeout: (sink) {
        sink.addError(
          _IdleTimeoutException(
            'No data received from the sender for ${idleTimeout.inSeconds}s',
          ),
        );
      },
    );
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
  /// hashing without buffering the whole file. Network errors are re-wrapped
  /// as [HttpException] so `saveStream`'s catch-all StorageException wrapping
  /// cannot misclassify a connection abort as a storage failure (2E finding).
  /// Also reports per-chunk progress and honours co-operative cancellation.
  Stream<List<int>> _tapped(
    Stream<List<int>> source,
    Sha256StreamSink sink, {
    void Function(int bytesReceived, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    required int totalBytes,
  }) {
    var received = 0;
    return source
        .map((chunk) {
          final token = cancelToken;
          if (token != null && token.isCancelled) {
            throw _CancelledException();
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, totalBytes);
          return chunk;
        })
        .transform(StreamTransformer.fromHandlers(
          handleError: (Object e, StackTrace st, EventSink<List<int>> dst) {
            if (e is _CancelledException) {
              dst.addError(e);
              dst.close();
              return;
            }
            if (e is _IdleTimeoutException) {
              // Re-wrapped so the storage layer's catch-all maps it to a
              // connection failure (2E finding), not storage.
              dst.addError(HttpException(e.message));
              return;
            }
            dst.addError(HttpException(e.toString()));
          },
        ));
  }
}

/// Internal marker so cancellation survives `saveStream`'s StorageException
/// wrapping and can be mapped back to a cancelled outcome.
class _CancelledException implements Exception {
  const _CancelledException();
}

/// Internal marker for a body/header idle-timeout breach; mapped to a
/// `DownloadFailureKind.connection` outcome.
class _IdleTimeoutException implements Exception {
  const _IdleTimeoutException(this.message);
  final String message;
  @override
  String toString() => message;
}
