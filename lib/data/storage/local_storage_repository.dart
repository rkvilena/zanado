import 'dart:async';
import 'dart:io';

import '../../core/utils/filename.dart';
import '../../domain/models/stored_file.dart';
import '../../domain/repositories/storage_repository.dart';

/// Local file storage backed by the app's documents directory.
///
/// Write strategy: every save first writes to a `.part` temporary file and
/// renames it into place only after the write completes — a partial/interrupted
/// write never appears as a completed file. Duplicate names never overwrite:
/// `photo.jpg` becomes `photo (1).jpg`, `photo (2).jpg`, …
class LocalStorageRepository implements StorageRepository {
  LocalStorageRepository({required Directory baseDirectory})
      : _base = baseDirectory;

  final Directory _base;

  Directory _ensureDir() {
    if (!_base.existsSync()) _base.createSync(recursive: true);
    return _base;
  }

  @override
  Future<String> directoryPath() async => _ensureDir().path;

  @override
  Future<List<StoredFile>> list() async {
    final dir = _ensureDir();
    final files = <StoredFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      // Skip in-progress temp files — they are not completed stored files.
      if (entity.path.endsWith(_partSuffix)) continue;
      final stat = entity.statSync();
      if (stat.type == FileSystemEntityType.notFound) continue;
      files.add(
        StoredFile(
          name: fileNameOf(entity.path),
          path: entity.path,
          sizeBytes: stat.size,
          savedAt: stat.modified,
        ),
      );
    }
    files.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return files;
  }

  @override
  Future<StoredFile> saveFromFile(String sourcePath, {String? displayName}) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw StorageException('Source file does not exist: $sourcePath');
    }
    final name = _resolveUniqueName(displayName ?? fileNameOf(sourcePath));
    final dir = _ensureDir();
    final targetPath = join(dir.path, name);
    final tmpPath = '$targetPath$_partSuffix';
    try {
      // POSIX rename is atomic; on Windows it can fail over an existing
      // target, but duplicates never collide here so that path is unreachable.
      await source.copy(tmpPath).then((_) => File(tmpPath).rename(targetPath));
    } on FileSystemException catch (e) {
      _cleanupQuietly(tmpPath);
      throw StorageException('Failed to save "$name"', e);
    }
    return _stat(targetPath);
  }

  @override
  Future<StoredFile> saveStream(
    Stream<List<int>> bytes,
    String fileName, {
    int? expectedSize,
  }) async {
    final name = _resolveUniqueName(fileName);
    final dir = _ensureDir();
    final targetPath = join(dir.path, name);
    final tmpPath = '$targetPath$_partSuffix';
    IOSink? sink;
    var written = 0;
    try {
      sink = File(tmpPath).openWrite();
      await for (final chunk in bytes) {
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (expectedSize != null && written != expectedSize) {
        throw StorageException(
          'Size mismatch for "$name": expected $expectedSize, got $written',
        );
      }
      await File(tmpPath).rename(targetPath);
    } catch (e) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {/* sink may already be broken; cleanup below is what matters */}
      sink = null;
      _cleanupQuietly(tmpPath);
      if (e is StorageException) rethrow;
      throw StorageException('Failed to save "$name"', e);
    }
    return _stat(targetPath);
  }

  @override
  Future<bool> delete(String name) async {
    final safe = FileNameUtils.sanitize(name);
    if (safe == null) {
      throw const InvalidFileNameException('Invalid file name: cannot delete');
    }
    final file = File(join(_ensureDir().path, safe));
    if (!file.existsSync()) return false;
    try {
      await file.delete();
      return true;
    } on FileSystemException catch (e) {
      throw StorageException('Failed to delete "$safe"', e);
    }
  }

  /// Picks a sanitized, non-colliding name inside the storage directory.
  String _resolveUniqueName(String? rawName) {
    final sanitized = FileNameUtils.sanitize(rawName);
    if (sanitized == null) {
      throw const InvalidFileNameException('Invalid or empty file name');
    }
    final (base, ext) = FileNameUtils.splitExtension(sanitized);
    var candidate = sanitized;
    var index = 0;
    while (File(join(_ensureDir().path, candidate)).existsSync()) {
      index += 1;
      candidate = FileNameUtils.withCopySuffix(base, ext, index);
    }
    return candidate;
  }

  StoredFile _stat(String path) {
    final stat = File(path).statSync();
    return StoredFile(
      name: fileNameOf(path),
      path: path,
      sizeBytes: stat.size,
      savedAt: stat.modified,
    );
  }

  static const _partSuffix = '.part';

  /// Removes `.part` files left by a killed process (e.g. the receiver was
  /// terminated mid-download and its error-path cleanup never ran). Called at
  /// startup before any transfer; no transfer is active, so any `.part` here
  /// is stale.
  Future<void> cleanupStaleParts() async {
    final dir = _ensureDir();
    if (!dir.existsSync()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith(_partSuffix)) {
        _cleanupQuietly(entity.path);
      }
    }
  }

  static void _cleanupQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {/* best effort */}
  }

  static String fileNameOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final i = normalized.lastIndexOf('/');
    return i == -1 ? normalized : normalized.substring(i + 1);
  }

  static String join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';
}
