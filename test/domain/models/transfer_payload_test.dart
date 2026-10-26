import 'package:flutter_test/flutter_test.dart';
import 'package:zanado/domain/models/transfer_payload.dart';

void main() {
  const token = 'ABCDEFGH23456789ABCDEFGH';
  final expiresAt = DateTime.utc(2026, 10, 26, 12, 0, 0);
  final now = DateTime.utc(2026, 10, 26, 11, 0, 0);

  TransferPayload payload() => TransferPayload.fromSession(
        host: '192.168.1.10',
        port: 54321,
        token: token,
        expiresAt: expiresAt,
      );

  group('generation', () {
    test('produces the canonical zanado://transfer URI', () {
      final uri = payload().toUriString();
      expect(
        uri,
        'zanado://transfer?host=192.168.1.10&port=54321'
        '&token=$token&expires=${expiresAt.millisecondsSinceEpoch}',
      );
    });

    test('expiresAt is normalized to UTC', () {
      final local = DateTime(2026, 10, 26, 12);
      expect(
        TransferPayload.fromSession(
          host: '192.168.1.10',
          port: 54321,
          token: token,
          expiresAt: local,
        ).expiresAt.isUtc,
        isTrue,
      );
    });

    test('rejects invalid construction inputs', () {
      expect(
        () => TransferPayload(host: '', port: 1, token: token, expiresAt: expiresAt),
        throwsArgumentError,
      );
      expect(
        () => TransferPayload(host: 'h', port: 0, token: token, expiresAt: expiresAt),
        throwsArgumentError,
      );
      expect(
        () => TransferPayload(host: 'h', port: 65536, token: token, expiresAt: expiresAt),
        throwsArgumentError,
      );
      expect(
        () => TransferPayload(host: 'h', port: 1, token: 'short!', expiresAt: expiresAt),
        throwsArgumentError,
      );
    });
  });

  group('parse — valid', () {
    test('round-trips a generated payload', () {
      final result = TransferPayload.parse(payload().toUriString(), now: now);
      expect(result, isA<TransferPayloadValid>());
      final p = (result as TransferPayloadValid).payload;
      expect(p.host, '192.168.1.10');
      expect(p.port, 54321);
      expect(p.token, token);
      expect(p.expiresAt, expiresAt);
      expect(p.isExpiredAt(now), isFalse);
    });

    test('a payload expiring exactly at `now` is not yet expired', () {
      final result = TransferPayload.parse(payload().toUriString(), now: expiresAt);
      expect(result, isA<TransferPayloadValid>());
    });
  });

  group('parse — malformed', () {
    test('unparseable string', () {
      expect(TransferPayload.parse('   '), isA<TransferPayloadMalformed>());
      expect(
        TransferPayload.parse('zanado://trans fer?host=x'),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('wrong scheme or host component', () {
      expect(
        TransferPayload.parse('http://transfer?host=h&port=1&token=$token&expires=1'),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse('zanado://other?host=h&port=1&token=$token&expires=1'),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('missing any required parameter', () {
      const base = 'zanado://transfer?host=192.168.1.10&port=54321&token=$token';
      expect(TransferPayload.parse(base, now: now), isA<TransferPayloadMalformed>());
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=192.168.1.10&port=54321&expires=123',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=192.168.1.10&token=$token&expires=123',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse(
          'zanado://transfer?port=54321&token=$token&expires=123',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('blank parameter values', () {
      expect(
        TransferPayload.parse('zanado://transfer?host=%20&port=1&token=$token&expires=1'),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=1&token=&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('port out of range or non-numeric', () {
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=0&token=$token&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=99999&token=$token&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=abc&token=$token&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('token with invalid format', () {
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=1&token=abc&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('non-numeric expires', () {
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=1&token=$token&expires=soon',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
    });

    test('duplicate query keys are rejected', () {
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&host=h2&port=1&token=$token&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
      expect(
        TransferPayload.parse(
          'zanado://transfer?host=h&port=1&token=$token&token=BAD&expires=1',
          now: now,
        ),
        isA<TransferPayloadMalformed>(),
      );
    });
  });

  group('parse — expired', () {
    test('payload past its expiry is expired, not malformed, with values intact', () {
      final result = TransferPayload.parse(
        payload().toUriString(),
        now: expiresAt.add(const Duration(seconds: 1)),
      );
      expect(result, isA<TransferPayloadExpired>());
      final p = (result as TransferPayloadExpired).payload;
      expect(p.token, token);
      expect(p.port, 54321);
      expect(p.host, '192.168.1.10');
    });
  });
}

