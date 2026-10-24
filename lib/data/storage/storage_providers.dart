import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'local_storage_repository.dart';
import 'media_storage_repository.dart';
import '../../domain/repositories/storage_repository.dart';

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
Future<StorageRepository> createStorageRepository() async {
  if (Platform.isAndroid) {
    final staging = await getTemporaryDirectory();
    return MediaStorageRepository(
      channel: const MethodChannel('zanado/storage'),
      staging: staging,
    );
  }
  final Directory base =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  return LocalStorageRepository(
    baseDirectory: Directory('${base.path}${Platform.pathSeparator}zanado'),
  );
}