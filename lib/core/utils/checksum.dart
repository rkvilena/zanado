import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SHA-256 checksum helpers: canonical representation + validation.
class ChecksumUtils {
  ChecksumUtils._();

  /// Encodes a raw SHA-256 digest as the canonical lowercase hex form used
  /// everywhere in the protocol (models, headers, error reports).
  static String bytesToHex(List<int> digest) =>
      digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String sha256Hex(List<int> bytes) =>
      bytesToHex(sha256.convert(bytes).bytes);

  /// Incremental digest for streamed verification (2B serving / 2C receiving):
  /// feed chunks in, finalize once at the end — never buffers whole files.
  static Sha256StreamSink startStreaming() => Sha256StreamSink();

  /// Accepts only the canonical form: 64 lowercase hex chars. A peer-supplied
  /// value that doesn't match can never be a valid sha-256 digest.
  static bool isValidFormat(String? value) =>
      value != null &&
      value.length == 64 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  /// Case/whitespace-tolerant comparison of two digests; returns false for
  /// any malformed input instead of throwing.
  static bool matches(String? expected, String? actual) {
    if (expected == null || actual == null) return false;
    final e = expected.trim().toLowerCase();
    final a = actual.trim().toLowerCase();
    return e == a && isValidFormat(e);
  }
}

/// Streaming SHA-256 accumulator for chunked transfer verification.
class Sha256StreamSink {
  Sha256StreamSink() {
    _converter = sha256.startChunkedConversion(_sink);
  }

  final _DigestSink _sink = _DigestSink();
  late final ChunkedConversionSink<List<int>> _converter;
  bool _closed = false;

  void add(List<int> chunk) {
    if (_closed) {
      throw StateError('Sha256StreamSink already finalized');
    }
    _converter.add(chunk);
  }

  String finalize() {
    _closed = true;
    _converter.close();
    return ChecksumUtils.bytesToHex(_sink.digest!.bytes);
  }
}

class _DigestSink implements ChunkedConversionSink<Digest> {
  Digest? digest;

  @override
  void add(Digest d) => digest = d;

  @override
  void close() {}
}