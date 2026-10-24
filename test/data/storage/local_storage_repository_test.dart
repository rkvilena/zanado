import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zanado/data/storage/local_storage_repository.dart';
import 'package:zanado/domain/repositories/storage_repository.dart';

void main() {
  late Directory tempDir;
  late LocalStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zanado_test_');
    repo = LocalStorageRepository(baseDirectory: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<File> makeSourceFile(String name, List<int> bytes) async {
    final f = File('${tempDir.parent.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('saveFromFile / list / delete', () {
    test('saves a file and lists it with correct metadata', () async {
      final src = await makeSourceFile('song.mp3', [1, 2, 3, 4, 5]);
      final stored = await repo.saveFromFile(src.path);

      expect(stored.name, 'song.mp3');
      expect(stored.sizeBytes, 5);
      expect(stored.extension, 'mp3');

      final list = await repo.list();
      expect(list, hasLength(1));
      expect(list.single.name, 'song.mp3');
      expect(File(list.single.path).readAsBytesSync(), [1, 2, 3, 4, 5]);
    });

    test('handles duplicate names without overwriting', () async {
      final src = await makeSourceFile('doc.pdf', [9, 9]);
      final a = await repo.saveFromFile(src.path);
      final b = await repo.saveFromFile(src.path);
      final c = await repo.saveFromFile(src.path, displayName: 'doc.pdf');

      expect(a.name, 'doc.pdf');
      expect(b.name, 'doc (1).pdf');
      expect(c.name, 'doc (2).pdf');

      final list = await repo.list();
      expect(list, hasLength(3));
      // Original must be untouched.
      expect(File(a.path).readAsBytesSync(), [9, 9]);
      expect(File(b.path).existsSync(), isTrue);
    });

    test('delete removes the file and returns false when absent', () async {
      final src = await makeSourceFile('x.txt', [1]);
      final stored = await repo.saveFromFile(src.path);

      expect(await repo.delete('x.txt'), isTrue);
      expect(File(stored.path).existsSync(), isFalse);
      expect(await repo.delete('x.txt'), isFalse);
      expect(await repo.list(), isEmpty);
    });

    test('delete rejects/handles unsafe names safely', () async {
      // '../escape.txt' sanitizes to 'escape.txt' (traversal stripped), which
      // does not exist — so nothing is deleted and no throw occurs.
      expect(await repo.delete('../escape.txt'), isFalse);
      await expectLater(
        repo.delete('   '),
        throwsA(isA<InvalidFileNameException>()),
      );
    });
  });

  group('saveStream (tmp-then-rename)', () {
    test('writes streamed bytes and verifies size', () async {
      final stored = await repo.saveStream(
        Stream.value([1, 2, 3, 4]),
        'video.mp4',
        expectedSize: 4,
      );
      expect(stored.sizeBytes, 4);
      expect(stored.name, 'video.mp4');
      expect(File(stored.path).readAsBytesSync(), [1, 2, 3, 4]);
      // No .part leftovers.
      expect(
        (await repo.list()).every((f) => !f.path.endsWith('.part')),
        isTrue,
      );
    });

    test('size mismatch fails and leaves no completed file', () async {
      await expectLater(
        repo.saveStream(
          Stream.value([1, 2, 3]),
          'file.bin',
          expectedSize: 10,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(await repo.list(), isEmpty);
      // And no temp file remains.
      expect(tempDir.listSync(), isEmpty);
    });

    test('interrupted stream leaves no completed file', () async {
      // A stream that fails mid-transfer must leave no completed file and
      // no .part leftover.
      final errController = StreamController<List<int>>();
      errController.add([4, 5]);
      errController.addError(Exception('network dropped'));
      errController.close(); // ignore: unawaited_futures

      await expectLater(
        repo.saveStream(errController.stream, 'failed.bin'),
        throwsA(isA<StorageException>()),
      );

      expect(await repo.list(), isEmpty);
      expect(
        tempDir.listSync().whereType<File>().any((f) => f.path.endsWith('.part')),
        isFalse,
      );
    });

    test('rejects empty names; traversal names are sanitized, not thrown',
        () async {
      await expectLater(
        repo.saveStream(Stream.value([1]), '   '),
        throwsA(isA<InvalidFileNameException>()),
      );
      // '../evil' → traversal stripped → saved as 'evil' inside the storage dir.
      final stored = await repo.saveStream(Stream.value([1]), '../evil');
      expect(stored.name, 'evil');
      expect(stored.path.startsWith(tempDir.path), isTrue);
    });

    test('duplicate streamed names get copy suffixes', () async {
      final bytes = Stream.value([7]);
      final a = await repo.saveStream(bytes, 'same.dat');
      final b = await repo.saveStream(Stream.value([7]), 'same.dat');
      expect(a.name, 'same.dat');
      expect(b.name, 'same (1).dat');
    });
  });

  group('sanitization on save', () {
    test('path-traversal source display name is sanitized', () async {
      final src = await makeSourceFile('ok.txt', [1]);
      final stored = await repo.saveFromFile(
        src.path,
        displayName: '../../dangerous.txt',
      );
      expect(stored.name, 'dangerous.txt');
      expect(stored.path.startsWith(tempDir.path), isTrue);
    });
  });
}
