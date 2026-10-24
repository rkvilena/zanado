import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/utils/checksum.dart';

const _helloSha256 = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

void main() {
  group('ChecksumUtils', () {
    test('sha256Hex produces the canonical lowercase digest', () {
      expect(ChecksumUtils.sha256Hex('hello'.codeUnits), _helloSha256);
    });

    test('streaming digest equals one-shot digest', () {
      final stream = ChecksumUtils.startStreaming();
      stream.add('hel'.codeUnits);
      stream.add('lo'.codeUnits);
      expect(stream.finalize(), _helloSha256);
    });

    test('streaming sink rejects use after finalize', () {
      final stream = ChecksumUtils.startStreaming();
      stream.add([1]);
      stream.finalize();
      expect(() => stream.add([2]), throwsStateError);
    });

    test('format validation', () {
      expect(ChecksumUtils.isValidFormat(_helloSha256), isTrue);
      expect(ChecksumUtils.isValidFormat(_helloSha256.toUpperCase()), isFalse);
      expect(ChecksumUtils.isValidFormat(_helloSha256.substring(1)), isFalse);
      expect(ChecksumUtils.isValidFormat(''), isFalse);
      expect(ChecksumUtils.isValidFormat(null), isFalse);
      expect(ChecksumUtils.isValidFormat('g' * 64), isFalse);
    });

    test('matches is case-insensitive but format-strict', () {
      expect(ChecksumUtils.matches(_helloSha256, ' ${_helloSha256.toUpperCase()} '), isTrue);
      expect(ChecksumUtils.matches(_helloSha256, 'nope'), isFalse);
      expect(ChecksumUtils.matches(null, _helloSha256), isFalse);
      expect(ChecksumUtils.matches(_helloSha256, null), isFalse);
    });
  });
}