import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Fast transport check used to choose the on-device path before starting an
/// HTTP request. A transport can still lack Internet access, so callers must
/// retain their normal backend error fallback as a second line of defence.
abstract final class NetworkAvailability {
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool? _lastKnownTransport;
  static DateTime? _lastUpdatedAt;

  static Future<bool> hasTransport() async {
    _subscription ??= _connectivity.onConnectivityChanged.listen((results) {
      _lastKnownTransport = _containsTransport(results);
      _lastUpdatedAt = DateTime.now();
    }, onError: (_) {});
    final cached = _lastKnownTransport;
    final lastUpdatedAt = _lastUpdatedAt;
    if (cached != null &&
        lastUpdatedAt != null &&
        DateTime.now().difference(lastUpdatedAt) < const Duration(seconds: 2)) {
      return cached;
    }
    try {
      final results = await _connectivity.checkConnectivity();
      _lastUpdatedAt = DateTime.now();
      return _lastKnownTransport = _containsTransport(results);
    } catch (_) {
      // If the optional platform signal is unavailable, preserve the existing
      // online-first behaviour and let the HTTP error path decide.
      return true;
    }
  }

  static bool _containsTransport(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
