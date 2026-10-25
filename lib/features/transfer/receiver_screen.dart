import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/bytes_format.dart';
import '../../data/network/transfer_receiver.dart';
import 'transfer_controller.dart';

/// Receiver workflow (MVP 3 Phase 3B): manual connection entry → live
/// byte-level progress + speed → cancel → terminal result via an exhaustive
/// switch on the sealed [DownloadOutcome].
class ReceiverScreen extends ConsumerStatefulWidget {
  const ReceiverScreen({super.key});

  @override
  ConsumerState<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends ConsumerState<ReceiverScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _token = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiverControllerProvider);
    final controller = ref.read(receiverControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Receive a file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the sender\u2019s connection code:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    decoration:
                        const InputDecoration(labelText: 'Sender IP'),
                  ),
                  TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                  TextField(
                    controller: _token,
                    decoration:
                        const InputDecoration(labelText: 'Token'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!state.busy)
            FilledButton.icon(
              onPressed: () =>
                  controller.download(_host.text, _port.text, _token.text),
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          if (state.busy) ...[
            _ProgressCard(state: state),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel download'),
            ),
          ],
          if (state.outcome != null) ...[
            const SizedBox(height: 12),
            _OutcomeBanner(outcome: state.outcome!),
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

/// Determinate when the sender declared a Content-Length, indeterminate
/// otherwise. Speed is the state layer's rolling-window estimate.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});

  final ReceiverState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalBytes;
    final known = total > 0 && state.bytesReceived >= 0;
    final value = known && total > 0
        ? (state.bytesReceived / total).clamp(0.0, 1.0)
        : null;
    final speed = state.speedBytesPerSec.round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    known
                        ? '${formatBytes(state.bytesReceived)} of ${formatBytes(total)}'
                        : '${formatBytes(state.bytesReceived)} received…',
                  ),
                ),
                if (speed > 0)
                  Text(
                    '${formatBytes(speed)}/s',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: value),
          ],
        ),
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.outcome});

  final DownloadOutcome outcome;

  @override
  Widget build(BuildContext context) {
    switch (outcome) {
      case final DownloadSuccess s:
        return _Banner(
          icon: Icons.check_circle,
          color: Colors.green,
          text: 'Saved "${s.file.name}" (${formatBytes(s.file.sizeBytes)}) — '
              'checksum verified',
        );
      case final DownloadFailure f:
        final (icon, color, text) = switch (f.kind) {
          DownloadFailureKind.cancelled => (
            Icons.cancel_outlined,
            Colors.orange,
            'Transfer cancelled.'
          ),
          DownloadFailureKind.connection => (
            Icons.error,
            Colors.red,
            'Connection failed: ${f.message}'
          ),
          DownloadFailureKind.protocol => (
            Icons.error,
            Colors.red,
            'Sender violated the transfer protocol: ${f.message}'
          ),
          DownloadFailureKind.rejectedBySender => (
            Icons.block,
            Colors.red,
            'Sender rejected the download: ${f.message}'
          ),
          DownloadFailureKind.sizeMismatch => (
            Icons.error,
            Colors.red,
            'Incomplete download (size mismatch): ${f.message}'
          ),
          DownloadFailureKind.checksumMismatch => (
            Icons.warning,
            Colors.red,
            'File was corrupt and has been discarded: ${f.message}'
          ),
          DownloadFailureKind.storage => (
            Icons.error,
            Colors.red,
            'Could not save the file: ${f.message}'
          ),
        };
        return _Banner(icon: icon, color: color, text: text);
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
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
