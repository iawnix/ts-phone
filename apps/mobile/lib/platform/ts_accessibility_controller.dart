import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef TsAccessibilityProbe = Future<bool> Function();

/// Bridges platform accessibility preferences that Flutter does not expose in
/// [MediaQuery]. Business and feature widgets consume only the resulting
/// boolean through the visual accessibility scope.
class TsAccessibilityController extends ChangeNotifier
    with WidgetsBindingObserver {
  TsAccessibilityController({
    TsAccessibilityProbe? probe,
    Stream<bool>? changes,
  }) : _probe = probe ?? _probePlatform,
       _changes = changes ?? _platformChanges;

  static const MethodChannel _methods = MethodChannel(
    'xyz.iawnix.ts_phone/accessibility',
  );
  static const EventChannel _events = EventChannel(
    'xyz.iawnix.ts_phone/accessibility_changes',
  );

  static Future<bool> _probePlatform() async =>
      await _methods.invokeMethod<bool>('getReduceTransparencyEnabled') ??
      false;

  static Stream<bool> get _platformChanges => _events
      .receiveBroadcastStream()
      .where((event) => event is bool)
      .cast<bool>();

  final TsAccessibilityProbe _probe;
  final Stream<bool> _changes;
  StreamSubscription<bool>? _subscription;
  bool _initialized = false;
  bool _disposed = false;
  bool _reduceTransparency = false;
  int _preferenceGeneration = 0;

  bool get reduceTransparency => _reduceTransparency;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _subscription = _changes.listen(
        _handlePlatformChange,
        onError: (_) {
          // The optional native event channel is not available everywhere.
        },
      );
    } on MissingPluginException {
      // A missing event channel must not prevent the initial preference probe.
    } on PlatformException {
      // Preserve the opaque startup fallback until the probe completes.
    }
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_preferenceGeneration;
    try {
      final value = await _probe();
      if (!_disposed && generation == _preferenceGeneration) {
        _setReduceTransparency(value);
      }
    } on MissingPluginException {
      // The native preference is currently iOS-only.
    } on PlatformException {
      // Preserve the last known value when the platform query is unavailable.
    }
  }

  void _handlePlatformChange(bool value) {
    _preferenceGeneration += 1;
    _setReduceTransparency(value);
  }

  void _setReduceTransparency(bool value) {
    if (_disposed) return;
    if (_reduceTransparency == value) return;
    _reduceTransparency = value;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
