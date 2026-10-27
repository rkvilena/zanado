import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'local_storage_repository.dart';
import 'media_storage_repository.dart';
import '../../domain/repositories/storage_repository.dart';

/// Monotonic counter bumped whenever a file is committed to storage from
/// outside the storage feature (transfer receive). The storage list watches
/// this so an already-mounted screen re-fetches. It lives in this shared
/// wiring layer because a features/transfer → features/storage import would
/// cross feature internals.
class StorageListRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final storageListRevisionProvider =
    NotifierProvider<StorageListRevision, int>(StorageListRevision.new);

/// Resolves the platform-appropriate USER-VISIBLE storage (MVP 1.1,
/// SHAREit-like) and exposes the concrete repository. This is the composition
/// root wiring (features depend only on the `StorageRepository` interface).
final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  throw UnimplementedError(
    'storageRepositoryProvider must be overridden in main.dart '
    '(platform bindings are unavailable during tests).',
  );
});

/// Builds the repository once the platform storage location is known:
/// - Android: public `Download/zanado/` via MediaStore (system file manager
///   can see it; no storage permissions on API 29+).
/// - Windows: `Downloads/zanado` under the user profile.
/// - Fallback (any platform without a Downloads dir): documents dir.
///
/// Leftover `.part` files from a previously killed process are swept at
/// startup: only one transfer runs at a time, so every `.part` present here
/// is stale (RC-08: zero-byte artifacts after a killed receiver).
Future<StorageRepository> createStorageRepository() async {
  if (Platform.isAndroid) {
    final staging = await getTemporaryDirectory();
    final repo = MediaStorageRepository(
      channel: const MethodChannel('zanado/storage'),
      staging: staging,
    );
    await repo.cleanupStaleParts();
    return repo;
  }
  final Directory base =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final repo = LocalStorageRepository(
    baseDirectory: Directory('${base.path}${Platform.pathSeparator}zanado'),
  );
  await repo.cleanupStaleParts();
  return repo;
}