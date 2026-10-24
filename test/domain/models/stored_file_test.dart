import 'package:flutter_test/flutter_test.dart';
import 'package:zanado/domain/models/stored_file.dart';

void main() {
  test('extension getter', () {
    expect(
      StoredFile(
        name: 'song.MP3',
        path: '/x/song.MP3',
        sizeBytes: 1,
        savedAt: DateTime(2026),
      ).extension,
      'mp3',
    );
    expect(
      StoredFile(
        name: 'noext',
        path: '/x/noext',
        sizeBytes: 1,
        savedAt: DateTime(2026),
      ).extension,
      '',
    );
    expect(
      StoredFile(
        name: '.hidden',
        path: '/x/.hidden',
        sizeBytes: 1,
        savedAt: DateTime(2026),
      ).extension,
      '',
    );
  });

  test('equality and toString', () {
    final t = DateTime(2026, 1, 1);
    final a = StoredFile(name: 'a', path: '/a', sizeBytes: 1, savedAt: t);
    final b = StoredFile(name: 'a', path: '/a', sizeBytes: 1, savedAt: t);
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('a'));
  });
}
