import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/providers/settings_provider.dart';
import 'package:photoatlas/services/network_info.dart';

void main() {
  test('privateSubnetPrefix accepts only private IPv4 addresses', () {
    expect(privateSubnetPrefix('10.234.121.225'), '10.234.121');
    expect(privateSubnetPrefix('192.168.1.7'), '192.168.1');
    expect(privateSubnetPrefix('172.16.4.9'), '172.16.4');
    expect(privateSubnetPrefix('172.31.255.1'), '172.31.255');
    expect(privateSubnetPrefix('172.32.0.1'), isNull);
    expect(privateSubnetPrefix('8.8.8.8'), isNull);
    expect(privateSubnetPrefix('100.64.0.1'), isNull);
    expect(privateSubnetPrefix('not-an-address'), isNull);
    expect(privateSubnetPrefix('10.234.121'), isNull);
    expect(privateSubnetPrefix('10.234.121.999'), isNull);
  });

  test('apiBaseUrlCandidates lists the saved server before the default', () {
    final candidates = apiBaseUrlCandidates(
      prefer: 'http://10.0.0.5:8787/',
      saved: 'http://10.0.0.9:8787',
    );
    expect(candidates.first, 'http://10.0.0.5:8787');
    expect(candidates, contains('http://10.0.0.9:8787'));
    expect(candidates, contains(defaultApiBaseUrl));
    expect(candidates, contains(fallbackApiBaseUrl));
    expect(
      candidates.toSet().length,
      candidates.length,
      reason: 'candidates must be unique',
    );
  });

  test('apiBaseUrlCandidates skips empty values', () {
    final candidates = apiBaseUrlCandidates(saved: '  ');
    expect(candidates, isNot(contains('')));
    expect(candidates.first, defaultApiBaseUrl);
  });
}
