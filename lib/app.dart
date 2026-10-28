import 'package:flutter/material.dart';

import 'shared/visual_tokens.dart';
import 'features/transfer/home_screen.dart';

/// Home screen: user picks SEND or RECEIVE and navigates to the corresponding
/// workflow screen.
class ZanadoApp extends StatelessWidget {
  const ZanadoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zanado',
      theme: buildZanadoTheme(),
      home: const HomeScreen(),
    );
  }
}
