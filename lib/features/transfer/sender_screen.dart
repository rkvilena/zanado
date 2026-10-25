import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/bytes_format.dart';
import 'transfer_controller.dart';

/// Sender workflow (MVP 3 Phase 3A): pick file → start serving → share the
/// connection code (manual copy; QR is MVP 4) → live status + expiry
/// countdown → cancel. Progress here is session-state only by design — the
/// sender serves bytes and does not track receiver-side progress.
class SenderScreen extends ConsumerWidget {
  const SenderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(senderControllerProvider);
    final controller = ref.read(senderControllerProvider.notifier);
    final busy = state.phase == SenderPhase.busy;
    final serving = state.phase == SenderPhase.serving;

    return Scaffold(
      appBar: AppBar(title: const Text('Send a file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.file_open),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.fileName ?? 'No file selected',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (state.fileSizeBytes != null)
                              Text(
                                formatBytes(state.fileSizeBytes!),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : controller.pickFile,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open),
                    label: Text(state.fileName == null
                        ? 'Pick a file to send'
                        : 'Pick a different file'),
                  ),
                ],
              ),
            ),
          ),
          if (state.fileName != null && !serving) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : controller.startServing,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Start transfer'),
            ),
          ],
          if (serving) ...[
            const SizedBox(height: 12),
            _ConnectionCodeCard(state: state),
            const SizedBox(height: 12),
            _ServingStatus(state: state),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.stop,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel transfer'),
            ),
          ],
          if (state.phase == SenderPhase.completed ||
            state.phase == SenderPhase.failed) ...[
          state.phase == SenderPhase.completed
              ? const _StatusBanner(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  text: 'Transfer completed — the receiver saved the file.',
                )
              : const _StatusBanner(
                  icon: Icons.error,
                  color: Colors.red,
                  text: 'Transfer failed — the receiver did not complete it.',
                ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: controller.stop,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Start over'),
          ),
        ],
          if (state.error != null)
            MaterialBanner(
              content: Text(state.error!),
              actions: [
                TextButton(
                  onPressed: controller.clearError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ConnectionCodeCard extends StatelessWidget {
  const _ConnectionCodeCard({required this.state});

  final SenderState state;

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter this code on the receiving device:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _CodeRow(
              label: 'IP',
              value: state.lanAddress?.address ?? 'resolving…',
              onCopy: (v) => _copy(context, 'IP', v),
            ),
            _CodeRow(
              label: 'Port',
              value: '${state.port ?? '?'}',
              onCopy: (v) => _copy(context, 'Port', v),
            ),
            _CodeRow(
              label: 'Token',
              value: state.token ?? '?',
              onCopy: (v) => _copy(context, 'Token', v),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            tooltip: 'Copy $label',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () => onCopy(value),
          ),
        ],
      ),
    );
  }
}

/// Live session status + expiry countdown. The 500 ms controller poll keeps
/// the state fresh, so a plain rebuild-driven countdown is sufficient here.
class _ServingStatus extends StatelessWidget {
  const _ServingStatus({required this.state});

  final SenderState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.receiverConnected;
    final expiry = state.expiresAt;
    final remaining = expiry?.difference(DateTime.now());
    final expired = remaining != null && remaining.isNegative;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                connected
                    ? const Icon(Icons.link, color: Colors.green)
                    : const Icon(Icons.hourglass_empty),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    connected
                        ? 'Receiver connected — sending…'
                        : 'Waiting for a receiver…',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              expiry == null
                  ? ''
                  : expired
                      ? 'Session expired.'
                      : 'Expires in ${_formatRemaining(remaining!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRemaining(Duration d) {
    final total = d.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
