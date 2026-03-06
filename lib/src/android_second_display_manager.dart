import 'dart:async';

import 'package:flutter/services.dart';

import 'multi_window_manager.dart';
import 'sub_window_size.dart';

/// Android implementation.
///
/// Communicates with [ExtendscreenPlugin] (Kotlin) via
/// `MethodChannel("second_display")`. The plugin manages the Android
/// `Presentation` API and the secondary `FlutterEngine`.
class AndroidSecondDisplayManager extends MultiWindowManager {
  static const _channel = MethodChannel('second_display');
  static const _subCommandsChannel = MethodChannel('sub_screen_commands');
  static const _reverseChannel = MethodChannel('secondary_to_main');

  // Cached after the first platform call — isSupported() never queries twice.
  bool? _cachedSupported;

  StreamController<Map<String, dynamic>>? _fromMainController;
  StreamController<Map<String, dynamic>>? _fromSecondaryController;

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
  Future<void> sendStateToSecondaryDisplay(Map<String, dynamic> state) async {
    await _channel.invokeMethod<void>('sendState', state);
  }

  /// Sends a state snapshot from the secondary display back to the main app.
  ///
  /// Call this from within the secondary display's Flutter engine. The Kotlin
  /// bridge forwards the map to the main engine.
  @override
  Future<void> sendStateToMainDisplay(Map<String, dynamic> state) async {
    await _reverseChannel.invokeMethod<void>('sendState', state);
  }

  /// Broadcast stream of state updates pushed by the main app.
  ///
  /// Intended for use inside the secondary display's Flutter engine. Lazily
  /// registers a [MethodChannel] handler on `"sub_screen_commands"`.
  @override
  Stream<Map<String, dynamic>> receiveStateFromMainDisplay() {
    if (_fromMainController == null) {
      _fromMainController =
          StreamController<Map<String, dynamic>>.broadcast();
      _subCommandsChannel.setMethodCallHandler((call) async {
        if (call.method == 'updateState') {
          _fromMainController?.add(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        }
      });
    }
    return _fromMainController!.stream;
  }

  /// Broadcast stream of state updates pushed by the secondary display.
  ///
  /// Intended for use inside the main app. Lazily registers a [MethodChannel]
  /// handler on `"secondary_to_main"`.
  @override
  Stream<Map<String, dynamic>> receiveStateFromSecondaryDisplay() {
    if (_fromSecondaryController == null) {
      _fromSecondaryController =
          StreamController<Map<String, dynamic>>.broadcast();
      _reverseChannel.setMethodCallHandler((call) async {
        if (call.method == 'updateState') {
          _fromSecondaryController?.add(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        }
      });
    }
    return _fromSecondaryController!.stream;
  }

  @override
  Future<void> closeAll() async {
    await _channel.invokeMethod<void>('releaseSecondDisplay');
    // Reset so a re-connection is detected correctly next time.
    _cachedSupported = null;
    await _fromMainController?.close();
    _fromMainController = null;
    await _fromSecondaryController?.close();
    _fromSecondaryController = null;
  }
}
