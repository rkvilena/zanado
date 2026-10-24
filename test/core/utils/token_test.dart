import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/utils/token.dart';

void main() {
  group('TransferToken', () {
    test('default token is 24 unambiguous alphanumeric characters', () {
      final token = TransferToken.generate();
      expect(token.length, 24);
      expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(token), isTrue);
    });

    test('rejects lengths below the security floor', () {
      expect(() => TransferToken.generate(length: 7), throwsArgumentError);
    });

    test('generation is non-deterministic across calls', () {
      expect(TransferToken.generate(), isNot(TransferToken.generate()));
    });

    test('format validation accepts generated tokens', () {
      expect(TransferToken.isValidFormat(TransferToken.generate()), isTrue);
    });

    test('format validation rejects junk', () {
      expect(TransferToken.isValidFormat(null), isFalse);
      expect(TransferToken.isValidFormat(''), isFalse);
      expect(TransferToken.isValidFormat('SHORT!'), isFalse); // too short + symbol
      expect(TransferToken.isValidFormat('abcdefgh'), isTrue); // manual entry may be lowercase
      expect(TransferToken.isValidFormat('TOOLONG${'A' * 60}'), isFalse);
      expect(TransferToken.isValidFormat('has space in it'), isFalse);
      expect(TransferToken.isValidFormat('Ünïcode123456'), isFalse);
      expect(TransferToken.isValidFormat('ABCDEFGH'), isTrue); // exactly 8
    });
  });
}