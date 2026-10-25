import 'package:flutter/material.dart';

import 'features/transfer/home_screen.dart';

/// Home is the MVP 3 app shell (SEND / RECEIVE navigation). The storage
/// debug screen stays reachable from the home app bar until MVP 5.
class ZanadoApp extends StatelessWidget {
  const ZanadoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zanado',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const HomeScreen(),
    );
  }
}
