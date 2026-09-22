import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/network_info.dart';

const _compileTimeApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Address of the development API on the VM. The phone hotspot hands out a
/// different subnet at every restart, so this is only a first guess: the app
/// falls back to detection (and a LAN scan) when it does not answer.
const defaultApiBaseUrl = 'http://10.234.121.225:8787';

const fallbackApiBaseUrl = 'http://localhost:8787';

String platformDefaultApiBaseUrl() {
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host.isNotEmpty) {
      return 'http://$host:8787';
    }
  }
  return defaultApiBaseUrl;
}

bool isLoopbackBaseUrl(String value) {
  final host = Uri.tryParse(value)?.host ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

/// Server addresses worth trying, most likely first.
List<String> apiBaseUrlCandidates({String? prefer, String? saved}) {
  final candidates = <String>[];
  void add(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty || candidates.contains(normalized)) return;
    candidates.add(normalized);
  }

  add(prefer ?? '');
  add(saved ?? '');
  add(_compileTimeApiBaseUrl);
  if (kIsWeb) {
    if (Uri.base.host.isNotEmpty) add('http://${Uri.base.host}:8787');
  } else {
    add(defaultApiBaseUrl);
  }
  add(fallbackApiBaseUrl);
  return candidates;
}

class ApiBaseUrlNotifier extends Notifier<String> {
  static const _key = 'api_base_url';

  @override
  String build() {
    _load();
    if (_compileTimeApiBaseUrl.isNotEmpty) return _compileTimeApiBaseUrl;
    return platformDefaultApiBaseUrl();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null || value.isEmpty) return;
    if (kIsWeb && isLoopbackBaseUrl(value)) {
      state = platformDefaultApiBaseUrl();
      return;
    }
    state = value;
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalized);
  }

  Future<String?> detectAndSave({String? prefer, bool scanLan = false}) async {
    for (final candidate in apiBaseUrlCandidates(
      prefer: prefer,
      saved: state,
    )) {
      if (await _isOnline(candidate)) {
        await setBaseUrl(candidate);
        return candidate;
      }
    }
    if (scanLan) {
      final found = await _scanLan();
      if (found != null) {
        await setBaseUrl(found);
        return found;
      }
    }
    return null;
  }

  Future<bool> _isOnline(String baseUrl) =>
      ApiClient(baseUrl).health(timeout: const Duration(seconds: 2));

  /// Probes `<prefix>.1-254:8787` on every private subnet of the device.
  Future<String?> _scanLan() async {
    final prefixes = await localSubnetPrefixes();
    if (prefixes.isEmpty) return null;
    final hosts = <String>[];
    for (final prefix in prefixes) {
      for (var host = 1; host <= 254; host += 1) {
        hosts.add('http://$prefix.$host:8787');
      }
    }
    final completer = Completer<String?>();
    var next = 0;
    Future<void> worker() async {
      while (!completer.isCompleted && next < hosts.length) {
        final host = hosts[next];
        next += 1;
        final online = await ApiClient(host)
            .health(timeout: const Duration(milliseconds: 400));
        if (online && !completer.isCompleted) {
          completer.complete(host);
          return;
        }
      }
    }

    final workers = [
      for (var index = 0; index < math.min(32, hosts.length); index += 1)
        worker(),
    ];
    await Future.wait(workers);
    if (!completer.isCompleted) completer.complete(null);
    return completer.future;
  }
}

final apiBaseUrlProvider = NotifierProvider<ApiBaseUrlNotifier, String>(
  ApiBaseUrlNotifier.new,
);
