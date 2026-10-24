import 'dart:io';

/// Picks the device's LAN address to advertise to a receiver (Phase 2D).
///
/// The sender binds anyIPv4, so this selection only affects what we DISPLAY.
/// Rank order: 192.168/16 (typical home Wi-Fi), 10/8, 172.16/12, then any
/// remaining non-loopback IPv4. IPv6 and loopback are never advertised — the
/// receiver UI expects a dotted IPv4 literal.
InternetAddress? pickLanAddress(List<InternetAddress> addresses) {
  final candidates = addresses
      .where((a) =>
          a.type == InternetAddressType.IPv4 &&
          !a.isLoopback &&
          !a.isLinkLocal)
      .toList();
  if (candidates.isEmpty) return null;

  int rank(InternetAddress a) {
    final o = a.address.split('.');
    if (o.length != 4) return 3;
    final b1 = int.parse(o[0]);
    final b2 = int.parse(o[1]);
    if (b1 == 192 && b2 == 168) return 0;
    if (b1 == 10) return 1;
    if (b1 == 172 && b2 >= 16 && b2 <= 31) return 2;
    return 3;
  }

  candidates.sort((a, b) => rank(a).compareTo(rank(b)));
  return candidates.first;
}

/// Discovers the first usable LAN IPv4 address of this device.
Future<InternetAddress?> findLanAddress() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
  );
  return pickLanAddress(
    interfaces.expand((i) => i.addresses).toList(),
  );
}