import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage/storage_providers.dart';
import '../../domain/models/stored_file.dart';
import '../../domain/repositories/storage_repository.dart';

/// Current listing of stored files plus UI status for the debug screen.
class StorageListState {
  const StorageListState({this.files = const [], this.busy = false, this.error});

  final List<StoredFile> files;
  final bool busy;
  final String? error;

  StorageListState copyWith({
    List<StoredFile>? files,
    bool? busy,
    String? error,
    bool clearError = false,
  }) =>
      StorageListState(
        files: files ?? this.files,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class StorageListController extends AsyncNotifier<StorageListState> {
  StorageRepository get _repo => ref.read(storageRepositoryProvider);

  @override
  Future<StorageListState> build() async {
    return StorageListState(files: await _repo.list());
  }

  Future<void> pickAndSave() async {
    _setBusy();
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      final String? path;
      if (files.isEmpty) {
        // User cancelled the picker.
        path = null;
      } else {
        path = files.first.path;
      }
      if (path == null) {
        state = AsyncValue.data(state.requireValue.copyWith(busy: false));
        return;
      }
      await _repo.saveFromFile(path);
      await _reload();
    } on StorageException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Unexpected error while picking file: $e');
    }
  }

  Future<void> delete(StoredFile file) async {
    _setBusy();
    try {
      await _repo.delete(file.name);
      await _reload();
    } on StorageException catch (e) {
      _fail(e.message);
    }
  }

  void clearError() =>
      state = AsyncValue.data(state.requireValue.copyWith(clearError: true));

  void _setBusy() =>
      state = AsyncValue.data(state.requireValue.copyWith(busy: true));

  Future<void> _reload() async =>
      state = AsyncValue.data(StorageListState(files: await _repo.list()));

  void _fail(String message) => state = AsyncValue.data(
        state.requireValue.copyWith(busy: false, error: message),
      );
}

final storageListControllerProvider =
    AsyncNotifierProvider<StorageListController, StorageListState>(
  StorageListController.new,
);

/// Resolved absolute path of the storage directory (debug display).
final storageDirectoryPathProvider = FutureProvider<String>(
  (ref) => ref.watch(storageRepositoryProvider).directoryPath(),
);

