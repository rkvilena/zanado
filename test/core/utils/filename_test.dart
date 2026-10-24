import 'package:flutter_test/flutter_test.dart';
import 'package:zanado/core/utils/filename.dart';

void main() {
  group('FileNameUtils.sanitize', () {
    test('keeps simple names unchanged', () {
      expect(FileNameUtils.sanitize('photo.jpg'), 'photo.jpg');
      expect(FileNameUtils.sanitize('my file.mp3'), 'my file.mp3');
    });

    test('strips path traversal components (slashes)', () {
      expect(FileNameUtils.sanitize('../../etc/passwd'), 'passwd');
      expect(FileNameUtils.sanitize('..\\..\\windows\\system32\\evil.dll'),
          'evil.dll');
      expect(FileNameUtils.sanitize('C:/Users/x/file.txt'), 'file.txt');
    });

    test('rejects dot and dotdot', () {
      expect(FileNameUtils.sanitize('.'), isNull);
      expect(FileNameUtils.sanitize('..'), isNull);
      expect(FileNameUtils.sanitize('../..'), isNull);
    });

    test('rejects empty and null', () {
      expect(FileNameUtils.sanitize(''), isNull);
      expect(FileNameUtils.sanitize('   '), isNull);
      expect(FileNameUtils.sanitize(null), isNull);
    });

    test('removes illegal Windows characters and control chars', () {
      expect(FileNameUtils.sanitize('bad:name*?<>|".txt'), 'badname.txt');
      expect(FileNameUtils.sanitize('a\x00\x1fb.txt'), 'ab.txt');
    });

    test('trims trailing dots and spaces (Windows-illegal)', () {
      expect(FileNameUtils.sanitize('name. ..'), 'name');
    });

    test('collapses whitespace', () {
      // Control characters (tab/newline) are removed first, then spaces collapse.
      expect(FileNameUtils.sanitize('  my\t\nfile  .mp3  '), 'myfile .mp3');
    });

    test('enforces max length preserving extension', () {
      final long = '${'a' * 300}.mp3';
      final out = FileNameUtils.sanitize(long, maxLength: 200)!;
      expect(out.length, lessThanOrEqualTo(200));
      expect(out.endsWith('.mp3'), isTrue);
    });
  });

  group('FileNameUtils.splitExtension / withCopySuffix', () {
    test('splits name and extension', () {
      expect(FileNameUtils.splitExtension('photo.jpg'), ('photo', '.jpg'));
      expect(FileNameUtils.splitExtension('archive.tar.gz'), ('archive.tar', '.gz'));
    });

    test('handles missing or leading-dot extensions', () {
      expect(FileNameUtils.splitExtension('noext'), ('noext', ''));
      expect(FileNameUtils.splitExtension('.hidden'), ('.hidden', ''));
    });

    test('builds duplicate suffixes', () {
      expect(FileNameUtils.withCopySuffix('photo', '.jpg', 1), 'photo (1).jpg');
      expect(FileNameUtils.withCopySuffix('photo', '.jpg', 12), 'photo (12).jpg');
      expect(FileNameUtils.withCopySuffix('file', '', 2), 'file (2)');
    });
  });
}
