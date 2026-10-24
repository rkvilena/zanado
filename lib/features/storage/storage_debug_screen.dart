import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_controller.dart';

/// Temporary debug screen for MVP 1 — exercises select / save / list / delete
/// on-device. Will be replaced by real transfer UI in MVP 3.
class StorageDebugScreen extends ConsumerWidget {
  const StorageDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(storageListControllerProvider);
    final controller = ref.read(storageListControllerProvider.notifier);
    final dirPath = ref.watch(storageDirectoryPathProvider).value;

    final Widget body;
    if (asyncState.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final value = asyncState.value;
      final files = value?.files ?? const [];
      body = files.isEmpty
          ? const Center(child: Text('No files stored yet.'))
          : ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, i) {
                final f = files[i];
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(f.name),
                  subtitle: Text(
                    '${_formatBytes(f.sizeBytes)} • saved ${f.savedAt.toLocal()}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: (value?.busy ?? false) ? null : () => controller.delete(f),
                  ),
                );
              },
            );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Zanado — Storage (MVP 1 debug)')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Storage dir: ${dirPath ?? 'resolving…'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: (asyncState.value?.busy ?? false) || asyncState.isLoading
                  ? null
                  : controller.pickAndSave,
              icon: const Icon(Icons.file_open),
              label: Text((asyncState.value?.busy ?? false) ? 'Working…' : 'Pick a file & save'),
            ),
          ),
          if (asyncState.value?.error != null)
            MaterialBanner(
              content: Text(asyncState.value!.error!),
              actions: [
                TextButton(
                  onPressed: controller.clearError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          const Divider(height: 24),
          Expanded(child: body),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
