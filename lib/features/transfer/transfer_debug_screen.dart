import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_debug_screen.dart';
import '../../data/network/transfer_receiver.dart';
import 'transfer_controller.dart';

/// Minimal debug screens for the MVP 2 Phase 2D device proof: manual pairing
/// (host/port/token), no polish, no progress UI — replaced in MVP 3.
class TransferDebugScreen extends ConsumerWidget {
  const TransferDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Zanado — Transfer (MVP 2 debug)'),
          actions: [
            IconButton(
              tooltip: 'Storage debug (MVP 1)',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorageDebugScreen()),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'SEND'),
            Tab(text: 'RECEIVE'),
          ]),
        ),
        body: const TabBarView(children: [_SenderTab(), _ReceiverTab()]),
      ),
    );
  }
}

class _SenderTab extends ConsumerWidget {
  const _SenderTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(senderControllerProvider);
    final controller = ref.read(senderControllerProvider.notifier);
    final busy = state.phase == SenderPhase.busy;
    final serving = state.phase == SenderPhase.serving;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: busy ? null : controller.pickFile,
          icon: const Icon(Icons.file_open),
          label: Text(state.fileName == null
              ? 'Pick a file to send'
              : 'File: ${state.fileName} — pick another'),
        ),
        const SizedBox(height: 12),
        if (state.fileName != null && !serving)
          FilledButton.icon(
            onPressed: busy ? null : controller.startServing,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Start transfer server'),
          ),
        if (serving) ...[
          _InfoCard(
            title: 'Enter these on the receiver device:',
            lines: [
              'IP: ${state.lanAddress?.address ?? 'resolving…'}',
              'Port: ${state.port ?? '?'}',
              'Token: ${state.token ?? '?'}',
            ],
          ),
          const SizedBox(height: 12),
          const Text('Waiting for the receiver to download…'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop server'),
          ),
        ],
        if (state.phase == SenderPhase.completed)
          const _PhaseBanner(
              icon: Icons.check_circle, text: 'Transfer completed ✅'),
        if (state.phase == SenderPhase.failed)
          const _PhaseBanner(
              icon: Icons.error, text: 'Transfer failed — see receiver side'),
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
    );
  }
}

class _ReceiverTab extends ConsumerStatefulWidget {
  const _ReceiverTab();

  @override
  ConsumerState<_ReceiverTab> createState() => _ReceiverTabState();
}

class _ReceiverTabState extends ConsumerState<_ReceiverTab> {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _host,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Sender IP (e.g. 192.168.1.42)',
          ),
        ),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Port'),
        ),
        TextField(
          controller: _token,
          decoration: const InputDecoration(labelText: 'Token'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: state.busy
              ? null
              : () => controller.download(_host.text, _port.text, _token.text),
          icon: state.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download),
          label: Text(state.busy ? 'Downloading…' : 'Download'),
        ),
        const SizedBox(height: 12),
        _ReceiverResult(outcome: state.outcome),
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
    );
  }
}

class _ReceiverResult extends StatelessWidget {
  const _ReceiverResult({required this.outcome});

  final DownloadOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final outcome = this.outcome;
    if (outcome == null) return const SizedBox.shrink();
    switch (outcome) {
      case final DownloadSuccess s:
        return _PhaseBanner(
          icon: Icons.check_circle,
          text: 'Saved "${s.file.name}" (${s.file.sizeBytes} bytes) — '
              'checksum verified',
        );
      case final DownloadFailure f:
        return _PhaseBanner(
          icon: Icons.error,
          text: 'FAILED (${f.kind.name}'
              '${f.errorCode == null ? '' : ', ${f.errorCode!.wireName}'}): '
              '${f.message}',
        );
    }
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...lines.map((l) => SelectableText(
                  l,
                  style: const TextStyle(fontFamily: 'monospace'),
                )),
          ],
        ),
      ),
    );
  }
}
