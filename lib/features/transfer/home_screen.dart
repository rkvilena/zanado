import 'package:flutter/material.dart';

import '../storage/storage_debug_screen.dart';
import 'receiver_screen.dart';
import 'sender_screen.dart';

/// MVP 3 app shell: user picks SEND or RECEIVE and navigates to the
/// corresponding workflow screen. Storage debug stays reachable for
/// developer verification until the library UI (MVP 5) replaces it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zanado'),
        actions: [
          IconButton(
            tooltip: 'Storage debug (MVP 1)',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StorageDebugScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeCard(
              icon: Icons.upload_rounded,
              title: 'Send',
              subtitle: 'Share a file from this device',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SenderScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.download_rounded,
              title: 'Receive',
              subtitle: 'Get a file from another device',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiverScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
