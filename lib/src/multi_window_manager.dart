import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'sub_window_size.dart';
import 'desktop_multi_window_manager.dart';
import 'android_second_display_manager.dart';
import 'unsupported_multi_window_manager.dart';

/// Platform-agnostic API for multi-window and dual-display features.
///
/// Obtain the singleton via [MultiWindowManager.instance]. The factory
/// automatically selects the correct implementation:
///
/// | Platform            | Implementation                   |
/// |---------------------|----------------------------------|
/// | Windows/macOS/Linux | [DesktopMultiWindowManager]      |
/// | Android             | [AndroidSecondDisplayManager]    |
/// | iOS / Web           | [UnsupportedMultiWindowManager]  |
///
/// This is the stable public API surface of the `extend_screen` package.
abstract class MultiWindowManager {
  // Singleton — resolved once and cached so the platform is never queried twice.
  static MultiWindowManager? _instance;

  static Future<MultiWindowManager> instance() async {
    _instance ??= await _create();
    return _instance!;
  }

  static Future<MultiWindowManager> _create() async {
    if (kIsWeb) return UnsupportedMultiWindowManager();
    if (Platform.isAndroid) return AndroidSecondDisplayManager();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return DesktopMultiWindowManager.create();
    }
    return UnsupportedMultiWindowManager(); // iOS and any future platforms
  }

  /// Returns `true` when this platform supports an active secondary display
  /// or programmatic multi-window.
  ///
  /// On Android the result reflects whether a second physical display is
  /// currently connected. On desktop this always returns `true`.
  /// On iOS and Web this always returns `false`.
  Future<bool> isSupported();

  /// Opens a new independent sub-window (desktop only).
  ///
  /// [argument] is serialised to JSON and passed to the sub-window's Flutter
  /// engine via the `desktop_multi_window` package. The sub-window receives
  /// it as `args[2]` in `main(List<String> args)`.
  ///
  /// [size] controls the initial frame of the new window. Defaults to
  /// [SubWindowSize.fullScreen], which fills the secondary display (or the
  /// primary display when only one is detected).
  Future<void> openSubWindow(
    Map<String, dynamic> argument, {
    SubWindowSize size = const SubWindowSize.fullScreen(),
  });

  /// Sends a state snapshot to the secondary display (Android only).
  ///
  /// [state] is a free-form map — include a `'type'` key so the secondary
  /// display can route to the correct screen. The map is forwarded as-is
  /// to the Kotlin bridge via `MethodChannel("sendState")`.
  /// Implementors on unsupported platforms silently ignore this call.
  Future<void> sendStateToSecondaryDisplay(Map<String, dynamic> state);

  /// Sends a state snapshot from the secondary display back to the main app
  /// (Android only). Call this from within the secondary display's engine.
  ///
  /// The Kotlin bridge forwards the map to the main engine via
  /// `MethodChannel("secondary_to_main")`.
  /// Implementors on unsupported platforms silently ignore this call.
  Future<void> sendStateToMainDisplay(Map<String, dynamic> state);

  /// Broadcast stream of state maps pushed from the main app.
  ///
  /// Call this from within the secondary display's Flutter engine (i.e. in the
  /// `subScreenMain` entry point). Each event is the raw map sent by the main
  /// app via [sendStateToSecondaryDisplay].
  ///
  /// On unsupported platforms the stream completes immediately with no events.
  Stream<Map<String, dynamic>> receiveStateFromMainDisplay();

  /// Broadcast stream of state maps pushed from the secondary display.
  ///
  /// Call this from within the main app. Each event is the raw map sent by the
  /// secondary display via [sendStateToMainDisplay].
  ///
  /// On unsupported platforms the stream completes immediately with no events.
  Stream<Map<String, dynamic>> receiveStateFromSecondaryDisplay();

  /// Closes all open sub-windows (desktop) or releases the secondary display
  /// Flutter engine (Android).
  Future<void> closeAll();
}
