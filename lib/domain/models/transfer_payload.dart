import '../../core/utils/token.dart';

/// Pairing payload encoded into the sender's QR code (Module C).
///
/// Wire format: `zanado://transfer?host=<ip>&port=<port>&token=<token>&expires=<epochMillisUtc>`
/// — UTC epoch millis so both platforms parse the expiry identically
/// regardless of local timezone.
class TransferPayload {
  TransferPayload({
    required this.host,
    required this.port,
    required this.token,
    required this.expiresAt,
  }) {
    if (host.trim().isEmpty) {
      throw ArgumentError('host must not be empty');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be 1..65535');
    }
    if (!TransferToken.isValidFormat(token)) {
      throw ArgumentError('token has an invalid format');
    }
  }

  /// Builds the payload from the sender's live session inputs.
  static TransferPayload fromSession({
    required String host,
    required int port,
    required String token,
    required DateTime expiresAt,
  }) =>
      TransferPayload(
        host: host.trim(),
        port: port,
        token: token,
        expiresAt: expiresAt.toUtc(),
      );

  final String host;
  final int port;
  final String token;
  final DateTime expiresAt;

  /// Canonical URI string for QR rendering (Phase 4B).
  String toUriString() =>
      'zanado://transfer?host=${Uri.encodeComponent(host)}'
      '&port=$port'
      '&token=${Uri.encodeComponent(token)}'
      '&expires=${expiresAt.millisecondsSinceEpoch}';

  bool isExpiredAt(DateTime time) => time.isAfter(expiresAt);

  /// Parses a scanned or manually entered payload string. Never throws for
  /// bad input — the sealed [TransferPayloadParseResult] lets the receiver UI
  /// switch exhaustively over valid / malformed / expired.
  static TransferPayloadParseResult parse(String raw, {DateTime? now}) {
    Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } on FormatException {
      return const TransferPayloadParseResult.malformed();
    }
    if (uri.scheme != 'zanado' || uri.host != 'transfer') {
      return const TransferPayloadParseResult.malformed();
    }
    final params = uri.queryParametersAll;
    // Duplicate query keys are rejected: they could smuggle in a second
    // (attacker-chosen) value for a security-relevant parameter.
    for (final values in params.values) {
      if (values.length != 1) return const TransferPayloadParseResult.malformed();
    }
    final host = params['host']?.first.trim();
    final portRaw = params['port']?.first.trim();
    final token = params['token']?.first.trim();
    final expiresRaw = params['expires']?.first.trim();
    if (host == null ||
        host.isEmpty ||
        portRaw == null ||
        portRaw.isEmpty ||
        token == null ||
        token.isEmpty ||
        expiresRaw == null ||
        expiresRaw.isEmpty) {
      return const TransferPayloadParseResult.malformed();
    }
    final port = int.tryParse(portRaw);
    if (port == null || port < 1 || port > 65535) {
      return const TransferPayloadParseResult.malformed();
    }
    if (!TransferToken.isValidFormat(token)) {
      return const TransferPayloadParseResult.malformed();
    }
    final expiresMillis = int.tryParse(expiresRaw);
    if (expiresMillis == null) {
      return const TransferPayloadParseResult.malformed();
    }
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(expiresMillis, isUtc: true);
    final payload = TransferPayload(
      host: host,
      port: port,
      token: token,
      expiresAt: expiresAt,
    );
    if (payload.isExpiredAt(now ?? DateTime.now())) {
      return TransferPayloadParseResult.expired(payload);
    }
    return TransferPayloadParseResult.valid(payload);
  }
}

/// Outcome of [TransferPayload.parse]. [expired] still carries the parsed
/// values so the UI can show recovery details (e.g. which session expired).
sealed class TransferPayloadParseResult {
  const TransferPayloadParseResult();

  const factory TransferPayloadParseResult.valid(TransferPayload payload) =
      TransferPayloadValid;

  const factory TransferPayloadParseResult.malformed() = TransferPayloadMalformed;

  const factory TransferPayloadParseResult.expired(TransferPayload payload) =
      TransferPayloadExpired;
}

class TransferPayloadValid extends TransferPayloadParseResult {
  const TransferPayloadValid(this.payload);
  final TransferPayload payload;
}

class TransferPayloadMalformed extends TransferPayloadParseResult {
  const TransferPayloadMalformed();
}

class TransferPayloadExpired extends TransferPayloadParseResult {
  const TransferPayloadExpired(this.payload);
  final TransferPayload payload;
}
