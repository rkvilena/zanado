import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/storage/storage_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await createStorageRepository();

  runApp(
    ProviderScope(
      overrides: [
        storageRepositoryProvider.overrideWithValue(repo),
      ],
      child: const ZanadoApp(),
    ),
  );
}
