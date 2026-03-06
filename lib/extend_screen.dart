/// `extend_screen` — Flutter plugin for multi-window (desktop) and
/// dual-display / secondary-screen (Android POS) support.
///
/// ## Usage
///
/// ```dart
/// import 'package:extend_screen/extend_screen.dart';
///
/// final manager = await MultiWindowManager.instance();
///
/// if (await manager.isSupported()) {
///   // Desktop: open a new independent OS window
///   await manager.openSubWindow({'title': 'My Sub Window'});
///
///   // Android POS: push a state to the customer-facing display
///   await manager.sendStateToSubDisplay(
///     OrderSummaryState(items: cart, total: 49.99),
///   );
/// }
/// ```
///
/// The Android sub-screen requires a Dart entry point annotated with
/// `@pragma('vm:entry-point')` named `subScreenMain` in your app:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void subScreenMain() {
///   WidgetsFlutterBinding.ensureInitialized();
///   runApp(const MySubScreenApp());
/// }
/// ```
library extend_screen;

export 'src/multi_window_manager.dart';
export 'src/sub_display_state.dart';
export 'src/sub_window_size.dart';
