import '../../core/utils/checksum.dart';

/// Metadata of a file offered for transfer (sender side). The sender shares
/// this with the receiver so it can verify size and integrity independently
/// of HTTP framing.
///
/// Pure domain object: no Flutter or dart:io imports.
class SelectedFile {
  const SelectedFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  /// Sanitized display name (already passed through FileNameUtils by the
  /// caller; never a raw peer/OS path).
  final String name;

  /// Absolute local path on the SENDING device. Never sent to the receiver —
  /// only [name] travels over the wire.
  final String path;

  final int sizeBytes;

  /// Canonical lowercase-hex SHA-256 digest of the full file content.
  final String sha256;

  /// Fails fast on structurally impossible metadata (receiver would reject
  /// these anyway; better to reject before a session is ever created).
  bool get isValid =>
      name.trim().isNotEmpty &&
      sizeBytes >= 0 &&
      ChecksumUtils.isValidFormat(sha256);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectedFile &&
          other.name == name &&
          other.path == path &&
          other.sizeBytes == sizeBytes &&
          other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(name, path, sizeBytes, sha256);

  @override
  String toString() => 'SelectedFile($name, $sizeBytes bytes)';
}