/// A file stored in the Zanado application directory (Module A).
///
/// Pure domain object: no Flutter or dart:io imports.
class StoredFile {
  const StoredFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.savedAt,
  });

  /// Always unique within the storage directory.
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime savedAt;

  /// Lowercased extension without the dot; empty string if none.
  String get extension {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredFile &&
          other.name == name &&
          other.path == path &&
          other.sizeBytes == sizeBytes &&
          other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(name, path, sizeBytes, savedAt);

  @override
  String toString() => 'StoredFile($name, $sizeBytes bytes)';
}