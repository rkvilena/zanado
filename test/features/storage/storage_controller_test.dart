import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/data/storage/local_storage_repository.dart';
import 'package:zanado/data/storage/storage_providers.dart';
import 'package:zanado/features/storage/storage_controller.dart';

/// Phase 6B: the storage list must reflect files committed by a transfer even
/// when the storage screen is (re)opened after the transfer completed — no app
/// restart, no manual delete required.
void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zanado_storage_ctrl_');
  });
  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('reopening the storage screen lists a file committed after close',
      () async {
    final container = ProviderContainer(overrides: [
      storageRepositoryProvider.overrideWithValue(
        LocalStorageRepository(baseDirectory: tempDir),
      ),
    ]);
    addTearDown(container.dispose);

    // Screen open #1: empty directory.
    final sub1 = container.listen(storageListControllerProvider, (_, _) {});
    final first = await container.read(storageListControllerProvider.future);
    expect(first.files, isEmpty);
    sub1.close(); // Screen popped — the list state is discarded.

    // A transfer completes through the same repository while no screen is
    // watching the list.
    await container
        .read(storageRepositoryProvider)
        .saveStream(Stream.value([1, 2, 3]), 'received.bin', expectedSize: 3);

    // Screen open #2: the list must be re-fetched, not replayed from cache.
    final sub2 = container.listen(storageListControllerProvider, (_, _) {});
    final second = await container.read(storageListControllerProvider.future);
    expect(second.files.map((f) => f.name), contains('received.bin'));
    sub2.close();
  });

  test('mounted storage screen re-fetches when the revision is bumped',
      () async {
    final container = ProviderContainer(overrides: [
      storageRepositoryProvider.overrideWithValue(
        LocalStorageRepository(baseDirectory: tempDir),
      ),
    ]);
    addTearDown(container.dispose);

    final updates = <StorageListState>[];
    final sub = container.listen(storageListControllerProvider, (_, next) {
      if (next is AsyncData<StorageListState>) updates.add(next.value);
    });
    await container.read(storageListControllerProvider.future);
    expect(updates.last.files, isEmpty);

    // Simulate a transfer committing a file while the screen stays mounted.
    await container
        .read(storageRepositoryProvider)
        .saveStream(Stream.value([9, 8, 7]), 'live.bin', expectedSize: 3);
    container.read(storageListRevisionProvider.notifier).bump();
    await container.read(storageListControllerProvider.future);

    expect(updates.last.files.map((f) => f.name), contains('live.bin'));
    sub.close();
  });
}
