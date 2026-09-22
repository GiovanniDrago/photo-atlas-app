import 'network_info_stub.dart'
    if (dart.library.io) 'network_info_io.dart'
    as impl;

/// Returns `a.b.c` for a private IPv4 address (RFC 1918), `null` otherwise.
String? privateSubnetPrefix(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  final isPrivate =
      octets[0] == 10 ||
      (octets[0] == 192 && octets[1] == 168) ||
      (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31);
  if (!isPrivate) return null;
  return '${octets[0]}.${octets[1]}.${octets[2]}';
}

/// Private `/24` prefixes of this device, used to look for the API on the LAN.
Future<List<String>> localSubnetPrefixes() async {
  final addresses = await impl.localIpv4Addresses();
  final prefixes = <String>[];
  for (final address in addresses) {
    final prefix = privateSubnetPrefix(address);
    if (prefix != null && !prefixes.contains(prefix)) prefixes.add(prefix);
  }
  return prefixes;
}
