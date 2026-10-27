import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/filename.dart';
import '../../domain/models/stored_file.dart';
import '../../domain/repositories/storage_repository.dart';

/// Android implementation of [StorageRepository] backed by the PUBLIC
/// `Download/zanado/` directory via MediaStore (MVP 1.1, SHAREit-like).
///
/// Files saved here are visible to the system file manager and other apps.
/// The native side (MainActivity.kt, channel `zanado/storage`) performs all
/// MediaStore work; `IS_PENDING` guarantees no partial file is ever visible.
///
/// `saveStream` stages incoming bytes into a `.part` file inside the app's
/// private cache directory (fast, always writable), then commits the staged
/// file into MediaStore — size is verified BEFORE the entry is published, so
/// the tmp-then-rename contract is preserved.
class MediaStorageRepository implements StorageRepository {
  MediaStorageRepository({
    required this._channel,
    required this._staging,
  });

  final MethodChannel _channel;
  final Directory _staging;

  /// Wraps platform errors into the domain [StorageException].
  Future<T> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      return (await _channel.invokeMethod<T>(method, arguments))!;
    } on PlatformException catch (e) {
      throw StorageException(
        'Failed to $method: ${e.message ?? e.code}',
        e,
      );
    }
  }

  @override
  Future<String> directoryPath() async => _invoke<String>('directoryPath', {});

  @override
  Future<List<StoredFile>> list() async {
    final rows = await _invoke<List<Object?>>('list', {});
    final files = <StoredFile>[];
    for (final row in rows) {
      final map = row as Map<Object?, Object?>;
      files.add(
        StoredFile(
          name: map['name'] as String,
          path: _mediaPathFor(map['name'] as String),
          sizeBytes: (map['size'] as num).toInt(),
          savedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['date'] as num).toInt(),
          ),
        ),
      );
    }
    return files;
  }

  @override
  Future<StoredFile> saveFromFile(String sourcePath, {String? displayName}) async {
    final name = _requireName(displayName ?? _fileNameOf(sourcePath));
    final result = await _invoke<Map<Object?, Object?>>('saveFromFile', {
      'displayName': name,
      'sourcePath': sourcePath,
    });
    return _storedFileFrom(result);
  }

  @override
  Future<StoredFile> saveStream(
    Stream<List<int>> bytes,
    String fileName, {
    int? expectedSize,
  }) async {
    final name = _requireName(fileName);
    final staged = File(_join(_staging.path, '$name$_partSuffix'));
    IOSink? sink;
    var written = 0;
    try {
      sink = staged.openWrite();
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
      // Commit publishes into MediaStore only after a successful size check;
      // the native side deletes the staged file once it is published.
      final result = await _invoke<Map<Object?, Object?>>('commitFromPath', {
        'displayName': name,
        'partPath': staged.path,
        'expectedSize': ?expectedSize,
      });
      return _storedFileFrom(result);
    } catch (e) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {/* sink may already be broken; staging cleanup matters */}
      sink = null;
      _deleteQuietly(staged);
      if (e is StorageException) rethrow;
      throw StorageException('Failed to save "$name"', e);
    }
  }

  @override
  Future<bool> delete(String name) async {
    final safe = FileNameUtils.sanitize(name);
    if (safe == null) {
      throw const InvalidFileNameException('Invalid file name: cannot delete');
    }
    return _invoke<bool>('delete', {'name': safe});
  }

  StoredFile _storedFileFrom(Map<Object?, Object?> result) => StoredFile(
        name: result['name'] as String,
        path: _mediaPathFor(result['name'] as String),
        sizeBytes: (result['size'] as num).toInt(),
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          (result['date'] as num).toInt(),
        ),
      );

  String _requireName(String? raw) {
    final safe = FileNameUtils.sanitize(raw);
    if (safe == null) {
      throw const InvalidFileNameException('Invalid or empty file name');
    }
    return safe;
  }

  String _mediaPathFor(String name) =>
      '/storage/emulated/0/Download/zanado/$name';

  static const _partSuffix = '.part';

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  static String _fileNameOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final i = normalized.lastIndexOf('/');
    return i == -1 ? normalized : normalized.substring(i + 1);
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {/* best effort */}
  }

  /// Removes `.part` staging files left by a killed process; the receiver's
  /// error-path cleanup never ran in that case. Called at startup before any
  /// transfer, so every `.part` in the staging directory is stale.
  Future<void> cleanupStaleParts() async {
    if (!_staging.existsSync()) return;
    await for (final entity in _staging.list()) {
      if (entity is File && entity.path.endsWith(_partSuffix)) {
        _deleteQuietly(entity);
      }
    }
  }
}