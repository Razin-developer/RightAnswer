import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors network connectivity and exposes a [ValueNotifier<bool>].
/// Registers callbacks that fire once when connectivity is restored.
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  final _connectivity = Connectivity();
  final _onlineNotifier = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;

  final List<Future<void> Function()> _reconnectCallbacks = [];

  ValueNotifier<bool> get isOnlineNotifier => _onlineNotifier;
  bool get isOnline => _onlineNotifier.value;

  /// Register an async callback invoked whenever connectivity is restored.
  void onReconnect(Future<void> Function() cb) => _reconnectCallbacks.add(cb);

  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    _onlineNotifier.value = _online(results);

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final wasOffline = !_onlineNotifier.value;
      final nowOnline = _online(results);
      _onlineNotifier.value = nowOnline;

      if (wasOffline && nowOnline) {
        for (final cb in _reconnectCallbacks) {
          cb(); // fire-and-forget; callers handle errors internally
        }
      }
    });
  }

  bool _online(List<ConnectivityResult> r) => r.any((e) =>
      e == ConnectivityResult.wifi ||
      e == ConnectivityResult.mobile ||
      e == ConnectivityResult.ethernet ||
      e == ConnectivityResult.vpn);

  void dispose() => _sub?.cancel();
}
