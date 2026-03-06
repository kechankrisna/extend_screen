import 'multi_window_manager.dart';
import 'sub_window_size.dart';

/// Fallback implementation for platforms that do not support multi-window
/// or secondary displays (iOS, Web).
///
/// [isSupported] always returns `false`. All other methods are safe no-ops so
/// callers never need to guard against platform checks at the call site.
class UnsupportedMultiWindowManager extends MultiWindowManager {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<void> openSubWindow(
    Map<String, dynamic> argument, {
    SubWindowSize size = const SubWindowSize.fullScreen(),
  }) async {}

  @override
  Future<void> sendStateToSecondaryDisplay(Map<String, dynamic> state) async {}

  @override
  Future<void> sendStateToMainDisplay(Map<String, dynamic> state) async {}

  @override
  Stream<Map<String, dynamic>> receiveStateFromMainDisplay() => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> receiveStateFromSecondaryDisplay() => const Stream.empty();

  @override
  Future<void> closeAll() async {}
}
