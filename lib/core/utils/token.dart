import 'dart:math';

/// Secure-random session token used to authenticate transfer requests.
class TransferToken {
  TransferToken._();

  /// Alphabet without visually ambiguous characters — the token must be
  /// retyped manually on Windows (desktop fallback), so `0/O` and `1/l/I`
  /// are excluded.
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int defaultLength = 24;

  /// Generates a cryptographically random token. [length] must be >= 8 so
  /// brute-forcing a live session stays infeasible on a local network.
  static String generate({int length = defaultLength}) {
    if (length < 8) {
      throw ArgumentError.value(length, 'length', 'must be at least 8');
    }
    final rng = Random.secure();
    return String.fromCharCodes(
      List.generate(
        length,
        (_) => _alphabet.codeUnitAt(rng.nextInt(_alphabet.length)),
      ),
    );
  }

  /// Structural validation for a token received from a peer. Does NOT check
  /// whether a session exists — that is the sender server's job (Phase 2B).
  static bool isValidFormat(String? token) {
    if (token == null || token.length < 8 || token.length > 64) return false;
    for (final c in token.codeUnits) {
      const upper = 0x41, lower = 0x61, digit = 0x30;
      final isUpper = c >= upper && c <= upper + 25;
      final isLower = c >= lower && c <= lower + 25;
      final isDigit = c >= digit && c <= digit + 9;
      if (!isUpper && !isLower && !isDigit) return false;
    }
    return true;
  }
}