import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/domain/models/selected_file.dart';

SelectedFile file({
  String name = 'photo.jpg',
  String path = '/tmp/photo.jpg',
  int size = 10,
  String? sha,
}) =>
    SelectedFile(
      name: name,
      path: path,
      sizeBytes: size,
      sha256: sha ?? 'a' * 64,
    );

void main() {
  group('SelectedFile', () {
    test('valid metadata passes validation', () {
      expect(file().isValid, isTrue);
    });

    test('rejects empty name', () {
      expect(file(name: '  ').isValid, isFalse);
    });

    test('rejects negative size', () {
      expect(file(size: -1).isValid, isFalse);
    });

    test('rejects malformed checksums', () {
      expect(file(sha: 'A' * 64).isValid, isFalse); // uppercase not canonical
      expect(file(sha: 'a' * 63).isValid, isFalse);
      expect(file(sha: '').isValid, isFalse);
    });

    test('value equality is field-based', () {
      expect(file(), file());
      expect(file(size: 11), isNot(file()));
    });
  });
}