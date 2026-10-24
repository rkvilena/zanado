import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/transfer_protocol.dart';
import '../../core/utils/token.dart';
import '../../domain/models/transfer_session.dart';

/// Sender-side HTTP server for one transfer session (Phase 2B, Module B).
///
/// Contract (from `TransferProtocol`):
/// - one file endpoint, token-authenticated, streamed response;
/// - 401 missing/malformed/unknown token, 403 expired/terminal session,
///   404 file unreadable, 409 second receiver while one is active,
///   400 missing/unsupported protocol version header;
/// - single-receiver enforcement: a session serves exactly one download.
///
/// One-shot lifecycle: the listener shuts down automatically once the session
/// reaches a terminal state (completed or failed) — no token reuse, no port
/// leak.
class TransferServer {
  TransferServer(this._session, {InternetAddress? bindAddress})
      : _bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  TransferSession _session;
  final InternetAddress _bindAddress;
  HttpServer? _server;
  bool _receiverConnected = false;

  TransferSession get session => _session;
  InternetAddress? get address => _server?.address;
  int? get port => _server?.port;
  bool get isRunning => _server != null;

  /// Binds to [_bindAddress] on an ephemeral port (port 0 → OS-assigned).
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(_bindAddress, 0);
    server.listen(
      (request) {
        _handleRequest(request).catchError((Object _) {
          // Headers may already be sent mid-stream; nothing safe to do.
          request.response.close().catchError((Object _) {});
        });
      },
      cancelOnError: false,
    );
    _server = server;
  }

  /// Immediately closes the listener and all open sockets.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET' ||
        request.uri.path != TransferProtocol.filePath) {
      await _sendError(
        request,
        TransferProtocol.statusNotFound,
        TransferErrorCode.fileUnavailable,
      );
      return;
    }

    final version = request.headers.value(TransferProtocol.versionHeader);
    if (version != '${TransferProtocol.version}') {
      await _sendError(
        request,
        TransferProtocol.statusBadRequest,
        TransferErrorCode.unsupportedProtocol,
      );
      return;
    }

    final token = request.headers.value(TransferProtocol.tokenHeader);
    if (token == null || token.isEmpty) {
      await _sendError(
        request,
        TransferProtocol.statusUnauthorized,
        TransferErrorCode.missingToken,
      );
      return;
    }
    if (!TransferToken.isValidFormat(token) || token != _session.token) {
      await _sendError(
        request,
        TransferProtocol.statusUnauthorized,
        TransferErrorCode.invalidToken,
      );
      return;
    }

    if (_session.isExpiredAt(DateTime.now()) || !_session.isDownloadable) {
      await _sendError(
        request,
        TransferProtocol.statusForbidden,
        TransferErrorCode.expiredToken,
      );
      return;
    }

    if (_receiverConnected) {
      await _sendError(
        request,
        TransferProtocol.statusConflict,
        TransferErrorCode.receiverAlreadyConnected,
      );
      return;
    }

    final file = File(_session.selectedFile.path);
    if (!await file.exists()) {
      await _sendError(
        request,
        TransferProtocol.statusNotFound,
        TransferErrorCode.fileUnavailable,
      );
      return;
    }

    _receiverConnected = true;
    try {
      final response = request.response;
      response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..set(
          TransferProtocol.checksumHeader,
          _session.selectedFile.sha256,
        )
        ..set(
          TransferProtocol.fileNameHeader,
          Uri.encodeComponent(_session.selectedFile.name),
        );
      response.contentLength = _session.selectedFile.sizeBytes;
      await response.addStream(file.openRead());
      await response.close();
      _markTerminal(TransferSessionStatus.completed);
    } catch (_) {
      await stop();
      _markTerminal(TransferSessionStatus.failed);
    }
  }

  void _markTerminal(TransferSessionStatus status) {
    _session = status == TransferSessionStatus.completed
        ? _session.markCompleted()
        : _session.markFailed();
    // One-shot: as soon as the session is terminal, accept no more requests.
    _server?.close().catchError((Object _) {});
    _server = null;
  }

  Future<void> _sendError(
    HttpRequest request,
    int status,
    TransferErrorCode code,
  ) async {
    try {
      final response = request.response;
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': code.wireName}));
      await response.close();
    } catch (_) {
      await request.response.close().catchError((Object _) {});
    }
  }
}