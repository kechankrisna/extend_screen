import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'sub_display_state.dart';
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

  /// Sends a [SubDisplayState] snapshot to the secondary display (Android only).
  ///
  /// The Kotlin bridge forwards the JSON-encoded state to the sub-screen
  /// Flutter engine via `MethodChannel("sub_screen_commands")`.
  /// Implementors on unsupported platforms silently ignore this call.
  Future<void> sendStateToSubDisplay(SubDisplayState state);

  /// Closes all open sub-windows (desktop) or releases the secondary display
  /// Flutter engine (Android).
  Future<void> closeAll();
}
