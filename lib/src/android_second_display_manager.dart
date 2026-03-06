import 'package:flutter/services.dart';

import 'multi_window_manager.dart';
import 'sub_display_state.dart';
import 'sub_window_size.dart';

/// Android implementation.
///
/// Communicates with [ExtendscreenPlugin] (Kotlin) via
/// `MethodChannel("second_display")`. The plugin manages the Android
/// `Presentation` API and the secondary `FlutterEngine`.
class AndroidSecondDisplayManager extends MultiWindowManager {
  static const _channel = MethodChannel('second_display');

  // Cached after the first platform call — isSupported() never queries twice.
  bool? _cachedSupported;

  @override
  Future<bool> isSupported() async {
    _cachedSupported ??=
        await _channel.invokeMethod<bool>('isSecondDisplayAvailable') ?? false;
    return _cachedSupported!;
  }

  /// No-op on Android — programmatic sub-windows are desktop-only.
  @override
  Future<void> openSubWindow(
    Map<String, dynamic> argument, {
    SubWindowSize size = const SubWindowSize.fullScreen(),
  }) async {}

  /// Sends a full state snapshot to the secondary display in a single call.
  ///
  /// Callers should debounce rapid state changes to avoid saturating the
  /// MethodChannel (see the 100 ms debounce in the demo app's `main_window.dart`).
  @override
  Future<void> sendStateToSubDisplay(SubDisplayState state) async {
    await _channel.invokeMethod<void>('sendState', state.toJson());
  }

  @override
  Future<void> closeAll() async {
    await _channel.invokeMethod<void>('releaseSecondDisplay');
    // Reset so a re-connection is detected correctly next time.
    _cachedSupported = null;
  }
}
