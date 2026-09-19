import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class DeviceService {
  static const _fingerprintKey = 'device_fingerprint';
  static const _deviceIdKey = 'device_id';

  static Future<String> fingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_fingerprintKey);
    if (value == null || value.isEmpty) {
      value = _randomId();
      await prefs.setString(_fingerprintKey, value);
    }
    return value;
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem;
  }

  static String defaultName() {
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isLinux) return 'Linux desktop';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows PC';
    return 'Device';
  }

  static Future<String> ensureRegistered(ApiClient client) async {
    final prefs = await SharedPreferences.getInstance();
    final fingerprintValue = await fingerprint();
    final id = await client.registerDevice(
      fingerprint: fingerprintValue,
      name: defaultName(),
      platform: platformName(),
    );
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  static Future<String?> cachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }
}
