import 'package:flutter/material.dart';

import 'features/storage/storage_debug_screen.dart';

/// Screens beyond storage debug (transfer UI, pairing, library) arrive in MVP 3+.
class ZanadoApp extends StatelessWidget {
  const ZanadoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zanado',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const StorageDebugScreen(),
    );
  }
}
