import 'dart:io';

Future<List<String>> localIpv4Addresses() async {
  final addresses = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address.isNotEmpty) addresses.add(address.address);
      }
    }
  } catch (_) {}
  return addresses;
}
