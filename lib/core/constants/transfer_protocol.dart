/// Wire contract between the sender server (Phase 2B) and the receiver
/// downloader (Phase 2C). Both sides must agree on these names/values; a
/// change here is a protocol change and requires updating both phases.
class TransferProtocol {
  TransferProtocol._();

  /// Bumped whenever the wire contract below changes incompatibly.
  static const int version = 1;

  /// Single file endpoint served by the sender.
  static const String filePath = '/zanado/v1/file';

  /// Header carrying the session token on every receiver request.
  static const String tokenHeader = 'X-Zanado-Token';

  /// Header echoing the protocol version; receiver rejects mismatches.
  static const String versionHeader = 'X-Zanado-Protocol';

  /// Checksum algorithm used for integrity verification. The digest is
  /// represented as a 64-char lowercase hex string.
  static const String checksumAlgorithm = 'sha-256';

  /// Session lifetime bounds. The requested duration is clamped into this
  /// range so a hostile or buggy payload can neither create an
  /// effectively permanent session nor expire instantly.
  static const Duration minSessionDuration = Duration(seconds: 30);
  static const Duration maxSessionDuration = Duration(minutes: 30);
  static const Duration defaultSessionDuration = Duration(minutes: 10);

  /// Response contract for GET [filePath]:
  /// - 200 + streamed body: token valid, file streaming begins.
  /// - 401: missing/malformed token header or unknown token.
  /// - 403: token known but session expired.
  /// - 404: session valid but the backing file is unreadable/missing.
  /// - 409: session valid but another transfer is already active
  ///   (single-receiver enforcement).
  /// - 400: [versionHeader] missing or unsupported.
  /// Error bodies are JSON `{"error": "<code>"}` with a [TransferErrorCode].
  static const int statusOk = 200;
  static const int statusBadRequest = 400;
  static const int statusUnauthorized = 401;
  static const int statusForbidden = 403;
  static const int statusNotFound = 404;
  static const int statusConflict = 409;
}

/// Machine-readable error codes sent in the `{"error": ...}` JSON body.
enum TransferErrorCode {
  missingToken('missing_token'),
  invalidToken('invalid_token'),
  expiredToken('expired_token'),
  fileUnavailable('file_unavailable'),
  receiverAlreadyConnected('receiver_already_connected'),
  unsupportedProtocol('unsupported_protocol');

  const TransferErrorCode(this.wireName);
  final String wireName;

  static TransferErrorCode? fromWireName(String name) {
    for (final code in values) {
      if (code.wireName == name) return code;
    }
    return null;
  }
}