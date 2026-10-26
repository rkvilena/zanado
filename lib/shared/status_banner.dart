import 'package:flutter/material.dart';

import 'visual_tokens.dart';

/// Status/result banner card shared by the sender and receiver screens
/// (deduplicates the identical private _StatusBanner/_Banner widgets).
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
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
        padding: ZanadoSpacing.banner,
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: ZanadoSpacing.s),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}