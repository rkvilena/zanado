import '../models/stored_file.dart';

/// Errors thrown by storage operations.
class StorageException implements Exception {
  const StorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? 'StorageException: $message' : 'StorageException: $message ($cause)';
}

/// Thrown when a caller-supplied name is invalid or unsafe (e.g. path
/// traversal, empty, or reserved characters that cannot be sanitized).
class InvalidFileNameException extends StorageException {
  const InvalidFileNameException(super.message);
}

/// Abstract local file storage.
///
/// Implementations must:
/// - never expose partial writes as completed files (tmp-then-rename),
/// - handle duplicate names safely (never overwrite an existing file),
/// - reject unsafe filenames (path traversal, empty, control chars).
abstract class StorageRepository {
  /// All files currently stored, newest first.
  Future<List<StoredFile>> list();

  /// Copies an existing file on disk into the app storage directory.
  /// [displayName] overrides the stored name when provided.
  Future<StoredFile> saveFromFile(String sourcePath, {String? displayName});

  /// Streams bytes into the app storage directory. Intended for incoming
  /// network transfers: writes to a temporary path and renames only
  /// after the stream completes successfully.
  Future<StoredFile> saveStream(
    Stream<List<int>> bytes,
    String fileName, {
    int? expectedSize,
  });

  /// Deletes a stored file by name. Returns true if something was deleted.
  Future<bool> delete(String name);

  /// The absolute path of the storage directory.
  Future<String> directoryPath();
}