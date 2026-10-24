import 'package:flutter/material.dart';

import 'features/transfer/transfer_debug_screen.dart';

/// Home is the MVP 2 debug transfer screen; storage debug stays reachable via
/// the app-bar folder action. Real transfer UI arrives in MVP 3.
class ZanadoApp extends StatelessWidget {
  const ZanadoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zanado',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const TransferDebugScreen(),
    );
  }
}
