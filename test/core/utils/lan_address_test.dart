import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/utils/lan_address.dart';

InternetAddress _ip(String s) =>
    InternetAddress(s, type: InternetAddressType.IPv4);

void main() {
  group('pickLanAddress', () {
    test('prefers 192.168 over 10 and 172 private ranges', () {
      final picked = pickLanAddress([
        _ip('10.0.0.5'),
        _ip('172.20.1.5'),
        _ip('192.168.1.42'),
      ]);
      expect(picked!.address, '192.168.1.42');
    });

    test('prefers 10/8 over 172.16/12', () {
      final picked = pickLanAddress([_ip('172.20.1.5'), _ip('10.0.0.5')]);
      expect(picked!.address, '10.0.0.5');
    });

    test('ignores loopback, link-local, and IPv6 addresses', () {
      final picked = pickLanAddress([
        InternetAddress('127.0.0.1', type: InternetAddressType.IPv4),
        InternetAddress('169.254.10.20', type: InternetAddressType.IPv4),
        InternetAddress('fe80::1', type: InternetAddressType.IPv6),
      ]);
      expect(picked, isNull);
    });

    test('falls back to any non-loopback IPv4 when no private range matches',
        () {
      final picked = pickLanAddress([
        _ip('100.64.0.7'),
        _ip('8.8.8.8'),
      ]);
      expect(picked!.address, '100.64.0.7');
    });
  });
}