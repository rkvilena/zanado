import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/bytes_format.dart';
import '../../domain/models/transfer_payload.dart';
import '../../shared/status_banner.dart';
import '../../shared/visual_tokens.dart';
import 'transfer_controller.dart';

/// Sender workflow (MVP 3 Phase 3A): pick file → start serving → share the
/// connection code (QR + per-row copy, full-code copy added in Phase 4D) →
/// live status + expiry countdown → cancel. Progress here is session-state
/// only by design — the sender serves bytes and does not track receiver-side
/// progress.
class SenderScreen extends ConsumerWidget {
  const SenderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(senderControllerProvider);
    final controller = ref.read(senderControllerProvider.notifier);
    final busy = state.phase == SenderPhase.busy;
    final preparing = state.phase == SenderPhase.preparing;
    final serving = state.phase == SenderPhase.serving;

    return Scaffold(
      appBar: AppBar(title: const Text('Send a file')),
      body: ListView(
        padding: ZanadoSpacing.screen,
        children: [
          Card(
            child: Padding(
              padding: ZanadoSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.file_open),
                      const SizedBox(width: ZanadoSpacing.m),
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
                  const SizedBox(height: ZanadoSpacing.m),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy || preparing ? null : controller.pickFile,
                      icon: busy || preparing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_open),
                      label: Text(state.fileName == null
                          ? 'Pick a file to send'
                          : 'Pick a different file'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (preparing) ...[
            const SizedBox(height: ZanadoSpacing.m),
            _PreparingCard(state: state),
          ],
          if (state.fileName != null && !serving && !preparing) ...[
            const SizedBox(height: ZanadoSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : controller.startServing,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Start transfer'),
              ),
            ),
          ],
          if (serving) ...[
            const SizedBox(height: ZanadoSpacing.m),
            _QrCodeCard(state: state),
            const SizedBox(height: ZanadoSpacing.m),
            _ConnectionCodeCard(state: state),
            const SizedBox(height: ZanadoSpacing.m),
            _ServingStatus(state: state),
            const SizedBox(height: ZanadoSpacing.m),
            OutlinedButton.icon(
              onPressed: controller.stop,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel transfer'),
            ),
          ],
          if (state.phase == SenderPhase.completed ||
            state.phase == SenderPhase.failed) ...[
          state.phase == SenderPhase.completed
              ? const StatusBanner(
                  icon: Icons.check_circle,
                  color: ZanadoStatusColors.success,
                  text: 'Transfer completed — the receiver saved the file.',
                )
              : const StatusBanner(
                  icon: Icons.error,
                  color: ZanadoStatusColors.danger,
                  text: 'Transfer failed — the receiver did not complete it.',
                ),
          const SizedBox(height: ZanadoSpacing.m),
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

/// Sender hashing wait made visible (MVP 5 Phase 5A): a determinate progress
/// bar over the streamed sha-256 computation, indeterminate only when the
/// file size could not be read beforehand.
class _PreparingCard extends StatelessWidget {
  const _PreparingCard({required this.state});

  final SenderState state;

  @override
  Widget build(BuildContext context) {
    final total = state.fileSizeBytes;
    final hashed = state.hashedBytes;
    final known = total != null && total > 0 && hashed >= 0;
    final value = known ? (hashed / total).clamp(0.0, 1.0) : null;
    final label = known
        ? 'Hashing ${formatBytes(hashed)} of ${formatBytes(total)}…'
        : 'Hashing…';

    return Card(
      child: Padding(
        padding: ZanadoSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.enhanced_encryption, size: 20),
                const SizedBox(width: ZanadoSpacing.s),
                Expanded(
                  child: Text('Preparing file…',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: ZanadoSpacing.s),
            Text(
              'Verifying “${state.fileName}” with a checksum before the '
              'transfer starts.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: value),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _QrCodeCard extends StatelessWidget {
  const _QrCodeCard({required this.state});

  final SenderState state;

  @override
  Widget build(BuildContext context) {
    final host = state.lanAddress?.address;
    final port = state.port;
    final token = state.token;
    final expiresAt = state.expiresAt;
    if (host == null || port == null || token == null || expiresAt == null) {
      return const SizedBox.shrink();
    }

    final payload = TransferPayload.fromSession(
      host: host,
      port: port,
      token: token,
      expiresAt: expiresAt,
    );

    return Card(
      child: Padding(
        padding: ZanadoSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Receiver scans this to connect:',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ZanadoSpacing.m),
            Center(
              child: Container(
                padding: ZanadoSpacing.banner,
                color: Colors.white,
                child: QrImageView(
                  data: payload.toUriString(),
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
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
    final host = state.lanAddress?.address;
    final port = state.port;
    final token = state.token;
    final expiresAt = state.expiresAt;
    final payloadReady =
        host != null && port != null && token != null && expiresAt != null;
    final fullCode = payloadReady
        ? TransferPayload.fromSession(
            host: host,
            port: port,
            token: token,
            expiresAt: expiresAt,
          ).toUriString()
        : null;

    return Card(
      child: Padding(
        padding: ZanadoSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter this code on the receiving device:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ZanadoSpacing.s),
            _CodeRow(
              label: 'IP',
              value: host ?? 'resolving…',
              onCopy: (v) => _copy(context, 'IP', v),
            ),
            _CodeRow(
              label: 'Port',
              value: '${port ?? '?'}',
              onCopy: (v) => _copy(context, 'Port', v),
            ),
            _CodeRow(
              label: 'Token',
              value: token ?? '?',
              onCopy: (v) => _copy(context, 'Token', v),
            ),
            // Phase 4D: one-tap copy of the entire payload so a desktop
            // receiver can paste it instead of retyping three fields.
            if (fullCode != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copy(context, 'Full connection code',
                      fullCode),
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('Copy full connection code'),
                ),
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
      padding: const EdgeInsets.symmetric(vertical: ZanadoSpacing.xs),
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
        padding: ZanadoSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                connected
                    ? const Icon(Icons.link, color: ZanadoStatusColors.success)
                    : const Icon(Icons.hourglass_empty),
                const SizedBox(width: ZanadoSpacing.m),
                Expanded(
                  child: Text(
                    connected
                        ? 'Receiver connected — sending…'
                        : 'Waiting for a receiver…',
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZanadoSpacing.s),
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
