import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/transfer_protocol.dart';
import '../../core/utils/bytes_format.dart';
import '../../data/network/transfer_receiver.dart';
import '../../domain/models/transfer_payload.dart';
import '../../shared/status_banner.dart';
import '../../shared/visual_tokens.dart';
import 'qr_scanner_sheet.dart';
import 'transfer_controller.dart';

/// Receiver workflow: manual connection entry → live
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

  /// Exhaustive switch over the payload parse result: valid codes prefill
  /// the manual form, expired ones point at recovery, malformed ones explain
  /// why nothing was filled. Shared by the QR scanner and the paste button
  /// so both inputs behave identically.
  void _applyCode(String raw) {
    final result = TransferPayload.parse(raw);
    switch (result) {
      case final TransferPayloadValid valid:
        _host.text = valid.payload.host;
        _port.text = '${valid.payload.port}';
        _token.text = valid.payload.token;
        _showSnack('Connection code filled — verify it and download.');
      case final TransferPayloadExpired _:
        _showSnack(
          'That session has expired. Ask the sender to start a new transfer.',
        );
      case final TransferPayloadMalformed _:
        _showSnack('The scanned code is not a valid Zanado transfer code.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Windows-friendly pairing — the sender's full connection code
  /// can be copied once and pasted here, no camera required.
  Future<void> _pasteCode() async {
    final data = await Clipboard.getData('text/plain');
    final raw = data?.text;
    if (raw == null || raw.trim().isEmpty) {
      _showSnack(
        'The clipboard is empty — copy the sender\u2019s full connection '
        'code first.',
      );
      return;
    }
    _applyCode(raw);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiverControllerProvider);
    final controller = ref.read(receiverControllerProvider.notifier);
    final desktop = ZanadoLayout.isWindowsDesktop(context);
    final wideForm =
        MediaQuery.sizeOf(context).width >= ZanadoLayout.wideFormBreakpoint;

    final scanButton = OutlinedButton.icon(
      onPressed: () => showQrScannerSheet(
        context,
        onCodeScanned: _applyCode,
        cameraBuilder: ref.read(qrCameraBuilderProvider),
      ),
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('Scan QR code'),
    );
    final pasteButton = OutlinedButton.icon(
      onPressed: _pasteCode,
      icon: const Icon(Icons.content_paste),
      label: const Text('Paste connection code'),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Receive a file')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ZanadoLayout.maxContentWidth,
          ),
          child: ListView(
            padding: ZanadoSpacing.screen,
            children: [
          Card(
            child: Padding(
              padding: ZanadoSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the sender\u2019s connection code:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: ZanadoSpacing.s),
                  if (desktop && wideForm) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _host,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Sender IP',
                            ),
                          ),
                        ),
                        const SizedBox(width: ZanadoSpacing.m),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _port,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Port'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    TextField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      decoration:
                          const InputDecoration(labelText: 'Sender IP'),
                    ),
                    const SizedBox(height: ZanadoSpacing.s),
                    TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ],
                  const SizedBox(height: ZanadoSpacing.s),
                  TextField(
                    controller: _token,
                    decoration:
                        const InputDecoration(labelText: 'Token'),
                    // Desktop ergonomics: Enter in the last field starts the
                    // download (same controller call as the Download button,
                    // so validation/errors are identical).
                    onSubmitted: (_) => controller
                        .download(_host.text, _port.text, _token.text),
                  ),
                  if (!state.busy) ...[
                    const SizedBox(height: ZanadoSpacing.m),
                    // Windows: side-by-side compact methods inside the card
                    // (agreed desktop composition); Android and narrow Windows
                    // windows keep stacked full-width touch targets.
                    desktop && wideForm
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              scanButton,
                              const SizedBox(width: ZanadoSpacing.m),
                              pasteButton,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              scanButton,
                              const SizedBox(height: ZanadoSpacing.m),
                              pasteButton,
                            ],
                          ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: ZanadoSpacing.m),
          if (!state.busy)
            ZanadoPageAction(
              child: FilledButton.icon(
                onPressed: () =>
                    controller.download(_host.text, _port.text, _token.text),
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
            ),
          if (state.busy) ...[
            _ProgressCard(state: state),
            const SizedBox(height: ZanadoSpacing.m),
            ZanadoPageAction(
              child: OutlinedButton.icon(
                onPressed: controller.cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel download'),
              ),
            ),
          ],
          if (state.outcome != null) ...[
            const SizedBox(height: ZanadoSpacing.m),
            _OutcomeBanner(outcome: state.outcome!),
            if (state.outcome is DownloadFailure &&
                (state.outcome! as DownloadFailure).kind !=
                    DownloadFailureKind.cancelled) ...[
              const SizedBox(height: ZanadoSpacing.m),
              ZanadoPageAction(
                child: FilledButton.tonalIcon(
                  onPressed: controller.retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            ],
            if (state.outcome is DownloadSuccess) ...[
              const SizedBox(height: ZanadoSpacing.m),
              ZanadoPageAction(
                child: OutlinedButton.icon(
                  onPressed: controller.reset,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Receive another file'),
                ),
              ),
            ],
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
        ),
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
        padding: ZanadoSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download, size: 20),
                const SizedBox(width: ZanadoSpacing.s),
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
            const SizedBox(height: ZanadoSpacing.m),
            LinearProgressIndicator(value: value),
          ],
        ),
      ),
    );
  }
}

/// User-facing text per sender rejection code; the raw code
/// message is the fallback for unknown/unparsed bodies.
String _rejectionText(TransferErrorCode? code, String fallback) {
  switch (code) {
    case TransferErrorCode.expiredToken:
      return 'The sender\u2019s transfer session expired. '
          'Ask them to start a new transfer.';
    case TransferErrorCode.missingToken:
    case TransferErrorCode.invalidToken:
      return 'The token was rejected — check it against the sender\u2019s '
          'connection code.';
    case TransferErrorCode.receiverAlreadyConnected:
      return 'Another device is already downloading from this sender.';
    case TransferErrorCode.fileUnavailable:
      return 'The sender can no longer provide the file.';
    case TransferErrorCode.unsupportedProtocol:
      return 'The sender runs an incompatible app version.';
    case null:
      return 'Sender rejected the download: $fallback';
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.outcome});

  final DownloadOutcome outcome;

  @override
  Widget build(BuildContext context) {
    switch (outcome) {
      case final DownloadSuccess s:
        final renamed = s.wireFileName.isNotEmpty &&
            s.wireFileName != s.file.name;
        return StatusBanner(
          icon: Icons.check_circle,
          color: ZanadoStatusColors.success,
          text: 'Saved "${s.file.name}" (${formatBytes(s.file.sizeBytes)}) — '
              'checksum verified'
              '${renamed ? ' (renamed — "${s.wireFileName}" already existed)' : ''}',
        );
      case final DownloadFailure f:
        // Checksum failure gets a dedicated, unmissable card
        // — the file was discarded, not saved.
        if (f.kind == DownloadFailureKind.checksumMismatch) {
          return _ChecksumFailureCard(message: f.message);
        }
        final (icon, color, text) = switch (f.kind) {
          DownloadFailureKind.cancelled => (
            Icons.cancel_outlined,
            ZanadoStatusColors.warning,
            'Transfer cancelled.'
          ),
          DownloadFailureKind.connection => (
            Icons.error,
            ZanadoStatusColors.danger,
            'Connection failed: ${f.message}'
          ),
          DownloadFailureKind.protocol => (
            Icons.error,
            ZanadoStatusColors.danger,
            'Sender violated the transfer protocol: ${f.message}'
          ),
          DownloadFailureKind.rejectedBySender => (
            Icons.block,
            ZanadoStatusColors.danger,
            _rejectionText(f.errorCode, f.message)
          ),
          DownloadFailureKind.sizeMismatch => (
            Icons.error,
            ZanadoStatusColors.danger,
            'Incomplete download (size mismatch): ${f.message}'
          ),
          DownloadFailureKind.checksumMismatch => (
            Icons.warning,
            ZanadoStatusColors.danger,
            'File was corrupt and has been discarded: ${f.message}'
          ),
          DownloadFailureKind.storage => (
            Icons.error,
            ZanadoStatusColors.danger,
            'Could not save the file: ${f.message}'
          ),
        };
        return StatusBanner(icon: icon, color: color, text: text);
    }
  }
}

/// Explicit checksum-failure state. The corrupt bytes were
/// discarded (temporary/committed file removed), so nothing partial is shown
/// as complete and the user must retry to get the file.
class _ChecksumFailureCard extends StatelessWidget {
  const _ChecksumFailureCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: ZanadoStatusColors.danger.withValues(alpha: 0.08),
      child: Padding(
        padding: ZanadoSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.report, color: ZanadoStatusColors.danger),
                const SizedBox(width: ZanadoSpacing.s),
                Expanded(
                  child: Text('File verification failed',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: ZanadoStatusColors.danger)),
                ),
              ],
            ),
            const SizedBox(height: ZanadoSpacing.s),
            Text(
              'The received file did not match the sender\u2019s checksum and '
              'has been discarded — nothing was saved. Try the transfer again.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: ZanadoSpacing.xs),
            Text(message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
