# `dualscreen` — Flutter Plugin Implementation

A Flutter plugin for **multi-window support on desktop** (Windows, macOS, Linux)
and **dual-display / secondary-screen support on Android** (POS devices).

---

## Environment

| Item | Value |
|---|---|
| Flutter SDK | `^3.10.4` |
| Dart | `^3.10.4` (sealed classes, patterns) |
| `desktop_multi_window` | `^0.2.0` |
| Android plugin package | `app.mylekha.package.dualscreen` |
| Android Kotlin JVM target | 17 |
| Plugin registration | `FlutterPlugin` interface (auto via `GeneratedPluginRegistrant`) |

---

## Package Structure

```
dualscreen/
├── lib/
│   ├── dualscreen.dart                         ← barrel export (public API)
│   └── src/
│       ├── sub_display_state.dart              ← sealed state + JSON codec
│       ├── sub_window_size.dart                ← sealed window-size spec
│       ├── multi_window_manager.dart           ← abstract API + singleton factory
│       ├── desktop_multi_window_manager.dart   ← Windows / macOS / Linux impl
│       ├── android_second_display_manager.dart ← Android MethodChannel impl
│       └── unsupported_multi_window_manager.dart ← iOS / Web no-op fallback
├── android/
│   └── src/main/kotlin/com/example/dualscreen/
│       └── DualscreenPlugin.kt                 ← FlutterPlugin + Presentation API
├── example/                                    ← runnable demo app
│   ├── lib/
│   │   ├── main.dart                           ← entry-point router
│   │   ├── main_window.dart                    ← desktop + Android POS UI
│   │   ├── sub_window.dart                     ← desktop sub-window (own engine)
│   │   └── sub_screen_entry.dart               ← Android sub-screen entry + screens
│   ├── android/app/src/main/
│   │   ├── AndroidManifest.xml                 ← resizeableActivity="true"
│   │   └── kotlin/.../MainActivity.kt          ← bare FlutterActivity()
│   └── pubspec.yaml                            ← dualscreen: path: ../
├── pubspec.yaml
└── implementation.md                           ← this file
```

---

## Public API (`lib/dualscreen.dart`)

Three types are exported:

```dart
// Obtain the platform-appropriate manager
final manager = await MultiWindowManager.instance();

// Check whether the current device/platform supports a secondary display
if (await manager.isSupported()) {

  // Desktop: open a new independent OS window
  await manager.openSubWindow(
    {'myKey': 'myValue'},                               // passed as JSON to sub-window
    size: const SubWindowSize.fullScreen(),             // default — fills secondary display
  );

  // Or with a specific size:
  await manager.openSubWindow({}, size: const SubWindowSize.centered(width: 800, height: 600));
  await manager.openSubWindow({}, size: SubWindowSize.fixed(Rect.fromLTWH(100, 100, 400, 300)));

  // Android POS: push state to the customer-facing display
  await manager.sendStateToSubDisplay(
    OrderSummaryState(items: cart, total: 49.99),
  );

  // Close everything
  await manager.closeAll();
}
```

---

## Dart Source Files

### `lib/src/sub_display_state.dart`

Sealed class hierarchy with full JSON round-trip, used for Android Presentation API
state synchronisation:

```dart
sealed class SubDisplayState {
  const SubDisplayState();
  Map<String, dynamic> toJson();
  factory SubDisplayState.fromJson(Map<String, dynamic> json) { ... }
}

final class IdleState extends SubDisplayState { ... }          // {'type': 'idle'}
final class OrderSummaryState extends SubDisplayState { ... }  // items list + total
final class PaymentPromptState extends SubDisplayState { ... } // total only
```

---

### `lib/src/sub_window_size.dart`

Sealed class describing the initial desktop sub-window frame. Each variant
implements `Rect resolveFrame()` — keeping all display-detection logic
co-located with the type, away from the manager.

```dart
sealed class SubWindowSize {
  const SubWindowSize();

  // Fills the secondary display (default). Falls back to primary when single display.
  const factory SubWindowSize.fullScreen() = _FullScreen;

  // Exact screen-coordinate Rect (global logical pixels).
  const factory SubWindowSize.fixed(Rect frame) = _Fixed;

  // Fixed logical size centred on the secondary display.
  const factory SubWindowSize.centered({required double width, required double height}) = _Centered;

  Rect resolveFrame(); // implemented by each variant
}
```

**`fullScreen` resolution strategy:**
- Enumerate `PlatformDispatcher.instance.displays`
- Identify primary via `PlatformDispatcher.instance.implicitView?.display`
- Secondary is assumed **positioned to the right** of the primary (standard POS layout)
- `Rect.fromLTWH(primaryLogicalW, 0, secLogicalW, secLogicalH)`
- Falls back to the primary display bounds when only one display is detected

**`centered` resolution strategy:**
- Same display detection as `fullScreen`
- `offsetX = secondary.id != primary.id ? primaryLogicalW : 0`
- `Rect.fromLTWH(offsetX + (secW - w) / 2, (secH - h) / 2, w, h)`

---

### `lib/src/multi_window_manager.dart`

Abstract class + singleton factory. Platform is detected once at construction time:

```dart
abstract class MultiWindowManager {
  static MultiWindowManager? _instance;

  static Future<MultiWindowManager> instance() async {
    _instance ??= await _create();
    return _instance!;
  }

  static Future<MultiWindowManager> _create() async {
    if (kIsWeb)           return UnsupportedMultiWindowManager();
    if (Platform.isAndroid) return AndroidSecondDisplayManager();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
                          return DesktopMultiWindowManager.create();
    return UnsupportedMultiWindowManager(); // iOS
  }

  Future<bool> isSupported();
  Future<void> openSubWindow(
    Map<String, dynamic> argument, {
    SubWindowSize size = const SubWindowSize.fullScreen(),
  });
  Future<void> sendStateToSubDisplay(SubDisplayState state);
  Future<void> closeAll();
}
```

---

### `lib/src/desktop_multi_window_manager.dart`

Windows / macOS / Linux implementation. Each `openSubWindow` call spawns a new
**OS process** with its own independent Flutter engine.

```dart
class DesktopMultiWindowManager extends MultiWindowManager {
  DesktopMultiWindowManager._();

  // Async factory — in kDebugMode closes any sub-windows that survived
  // a hot restart before the Dart VM state was reset (stale-window cleanup).
  static Future<DesktopMultiWindowManager> create() async {
    final manager = DesktopMultiWindowManager._();
    if (kDebugMode) await manager._closeStaleWindows();
    return manager;
  }

  // Queries DesktopMultiWindow.getAllSubWindowIds() and closes each one.
  Future<void> _closeStaleWindows() async { ... }

  int _windowCount = 0;
  final List<WindowController> _controllers = [];

  @override
  Future<void> openSubWindow(Map<String, dynamic> argument, {
    SubWindowSize size = const SubWindowSize.fullScreen(),
  }) async {
    _windowCount++;
    final controller = await DesktopMultiWindow.createWindow(
      jsonEncode({...argument, 'windowNumber': _windowCount}),
    );
    await controller.setFrame(size.resolveFrame());  // SubWindowSize drives the frame
    await controller.setTitle('Sub Window $_windowCount');
    await controller.show();
    _controllers.add(controller);
  }

  @override Future<void> sendStateToSubDisplay(SubDisplayState state) async {} // no-op
}
```

#### Hot Restart Fix

Sub-windows are separate OS processes. Hot restart resets Dart VM state
(`_controllers` cleared, `_instance` nulled) but leaves sub-window processes
alive — they become stale and unreachable.

**Fix:** The `create()` async factory calls `_closeStaleWindows()` in `kDebugMode`,
querying `DesktopMultiWindow.getAllSubWindowIds()` and closing every live sub-window
before the manager is returned to the caller. This guarantees a clean slate after
every hot restart in development.

---

### `lib/src/android_second_display_manager.dart`

Android implementation via `MethodChannel("second_display")`. Delegates all
Presentation API work to `DualscreenPlugin.kt`.

```dart
class AndroidSecondDisplayManager extends MultiWindowManager {
  static const _channel = MethodChannel('second_display');
  bool? _cachedSupported; // queried at most once

  @override
  Future<bool> isSupported() async {
    _cachedSupported ??=
        await _channel.invokeMethod<bool>('isSecondDisplayAvailable') ?? false;
    return _cachedSupported!;
  }

  @override Future<void> openSubWindow(...) async {} // no-op — desktop only

  @override
  Future<void> sendStateToSubDisplay(SubDisplayState state) async {
    await _channel.invokeMethod<void>('sendState', state.toJson());
  }

  @override
  Future<void> closeAll() async {
    await _channel.invokeMethod<void>('releaseSecondDisplay');
    _cachedSupported = null; // reset so reconnect is detected correctly
  }
}
```

---

### `lib/src/unsupported_multi_window_manager.dart`

Safe no-op fallback for iOS and Web. `isSupported()` always returns `false`.
All other methods are silent no-ops — callers never need platform guards.

---

## Android Plugin (`DualscreenPlugin.kt`)

Uses the `FlutterPlugin` interface — auto-registered by `GeneratedPluginRegistrant`,
**no changes to `MainActivity` needed in the host app**.

### Architecture

```
Host app MainActivity (bare FlutterActivity)
    │
    └── GeneratedPluginRegistrant.registerWith()
            │
            └── DualscreenPlugin.onAttachedToEngine()
                    │
                    └── SecondDisplayManager
                            ├── MethodChannel("second_display")  ← Flutter → Kotlin
                            ├── DisplayManager.DisplayListener   ← hotplug detection
                            ├── FlutterEngine (lazy)             ← second Dart VM
                            ├── MethodChannel("sub_screen_commands") ← Kotlin → 2nd engine
                            └── SecondDisplayPresentation        ← Android Presentation
```

### Key Implementation Details

**Auto-registration:**
```kotlin
class DualscreenPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        manager = SecondDisplayManager(binding.applicationContext)
        manager!!.register(MethodChannel(binding.binaryMessenger, "second_display"))
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        manager?.dispose(); manager = null
    }
}
```

**Secondary display detection:**
```kotlin
private fun getSecondDisplay(): Display? =
    displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull()
```

**Lazy Flutter engine init (guard prevents double-init):**
```kotlin
private fun initSecondDisplay(display: Display) {
    if (subEngine != null) return   // guard: never recreate if alive

    subEngine = FlutterEngine(context).also { engine ->
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "subScreenMain"   // @pragma('vm:entry-point') in the host app
            )
        )
        FlutterEngineCache.getInstance().put("dualscreen_sub_engine", engine)
        subChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "sub_screen_commands")
    }
    presentation = SecondDisplayPresentation(context, display, subEngine!!).also { it.show() }
}
```

**Clean engine teardown (detach FlutterView before dismiss):**
```kotlin
private fun releaseEngine() {
    presentation?.detach()   // detaches FlutterView from engine before dismiss
    presentation?.dismiss()
    presentation = null
    FlutterEngineCache.getInstance().remove("dualscreen_sub_engine")
    subEngine?.destroy()
    subEngine = null
    subChannel = null
}
```

**Method channel handler:**

| Method | Response |
|---|---|
| `isSecondDisplayAvailable` | `Boolean` — `true` if a presentation display is connected |
| `sendState` | Forwards JSON args to `sub_screen_commands` channel → sub engine |
| `releaseSecondDisplay` | Tears down engine + presentation |

---

## Host App Requirements

### Android sub-screen Dart entry point

The host app must have a `@pragma('vm:entry-point')` annotated function. Without
the pragma, tree-shaking removes it and `DualscreenPlugin.kt` cannot start it:

```dart
@pragma('vm:entry-point')
void subScreenMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MySubScreenApp());
}
```

### AndroidManifest.xml

```xml
<activity
    android:name=".MainActivity"
    android:resizeableActivity="true"
    ...>
```

### Desktop entry-point routing (`main.dart`)

```dart
void main(List<String> args) {
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args.length > 2 && args[2].isNotEmpty
        ? jsonDecode(args[2]) as Map<String, dynamic>
        : <String, dynamic>{};
    WidgetsFlutterBinding.ensureInitialized();
    runApp(MySubWindowApp(windowId: windowId, argument: argument));
    return;
  }
  runApp(const MyMainApp());
}
```

---

## Example App (`example/`)

A complete runnable demo. Run with:

```bash
cd example

# macOS
flutter run -d macos

# Windows / Linux
flutter run -d windows
flutter run -d linux

# Android (device with secondary display for full POS demo)
flutter run -d <device-id>
```

### Files

| File | Purpose |
|---|---|
| `lib/main.dart` | Entry-point router (identical pattern to host app requirements above) |
| `lib/main_window.dart` | Desktop counter + "Open Sub Window" (fullScreen + centered buttons); Android POS cashier with Add Item / Payment / New Order |
| `lib/sub_window.dart` | Independent desktop sub-window with own counter |
| `lib/sub_screen_entry.dart` | `subScreenMain()` entry point + `IdleScreen` / `OrderSummaryScreen` / `PaymentPromptScreen` |

### Desktop walk-through

1. Launch → **Main Window** (counter + two "Open Sub Window" buttons)
2. "Open Sub Window (full screen)" → new OS window fills secondary display (`SubWindowSize.fullScreen()`)
3. "Open Sub Window (640 × 480 centred)" → centred on secondary display (`SubWindowSize.centered(width: 640, height: 480)`)
4. Each sub-window has its own independent counter — no shared state
5. "Close All" (app bar) → all sub-windows dismissed

### Android POS walk-through

1. Connect secondary display (or use Android presentation display emulator)
2. Launch → sub-screen shows **Idle** ("Welcome" screen)
3. Tap "Add Item" → sub-screen updates in real time (100ms debounced) → **Order Summary**
4. Tap "Payment" → sub-screen shows **Payment Prompt** with total
5. Tap "New Order" → sub-screen returns to **Idle**

---

## Optimizations

| # | Optimization | Location |
|---|---|---|
| 1 | `FlutterEngine` lazy init — only when secondary display detected | `DualscreenPlugin.initSecondDisplay()` |
| 2 | `if (subEngine != null) return` guard — prevents double-init | `DualscreenPlugin.initSecondDisplay()` |
| 3 | `FlutterEngineCache` — engine reusable across config changes | `DualscreenPlugin` (`"dualscreen_sub_engine"`) |
| 4 | `_cachedSupported` — `isSupported()` queries platform only once | `AndroidSecondDisplayManager` |
| 5 | 100ms `Timer` debounce on `sendStateToSubDisplay` | Example `main_window.dart._syncSubDisplay()` |
| 6 | `ValueNotifier` + `ValueListenableBuilder` — scoped rebuilds | Example `main_window.dart`, `sub_window.dart` |
| 7 | `const` constructors on all sub-screen widgets | Example `sub_screen_entry.dart` |
| 8 | Full state snapshot JSON in one call — not per-field | `SubDisplayState.toJson()` |
| 9 | `MultiWindowManager` singleton — `_instance` cached at class level | `multi_window_manager.dart` |
| 10 | `SubWindowSize.resolveFrame()` on the type — avoids `switch` on private subtypes across files | `sub_window_size.dart` |
| 11 | Stale sub-window cleanup on hot restart (debug only) | `DesktopMultiWindowManager.create()` |

---

## Platform Support Matrix

| Platform | `isSupported()` | `openSubWindow` | `sendStateToSubDisplay` |
|---|---|---|---|
| Windows | `true` | ✅ new OS process | no-op |
| macOS | `true` | ✅ new OS process | no-op |
| Linux | `true` | ✅ new OS process | no-op |
| Android (secondary display connected) | `true` | no-op | ✅ Presentation API |
| Android (no secondary display) | `false` | no-op | no-op |
| iOS | `false` | no-op | no-op |
| Web | `false` | no-op | no-op |

---

## MethodChannel Reference

### `"second_display"` — Flutter ↔ Kotlin (main engine)

| Method | Direction | Arguments | Return |
|---|---|---|---|
| `isSecondDisplayAvailable` | Flutter → Kotlin | none | `bool` |
| `sendState` | Flutter → Kotlin | `Map<String,dynamic>` (JSON state) | `void` |
| `releaseSecondDisplay` | Flutter → Kotlin | none | `void` |

### `"sub_screen_commands"` — Kotlin → sub-screen Flutter engine

| Method | Direction | Arguments |
|---|---|---|
| `updateState` | Kotlin → Flutter | `Map<String,dynamic>` (JSON state) |

---

## File Checklist

### Package (`dualscreen/`)

| File | Status |
|---|---|
| `pubspec.yaml` | plugin manifest, `desktop_multi_window: ^0.2.0` |
| `lib/dualscreen.dart` | barrel export |
| `lib/src/sub_display_state.dart` | sealed state + JSON codec |
| `lib/src/sub_window_size.dart` | sealed window-size spec + `resolveFrame()` |
| `lib/src/multi_window_manager.dart` | abstract API + singleton factory |
| `lib/src/desktop_multi_window_manager.dart` | desktop impl (hot restart fix + `SubWindowSize`) |
| `lib/src/android_second_display_manager.dart` | Android MethodChannel impl |
| `lib/src/unsupported_multi_window_manager.dart` | iOS / Web no-op |
| `android/.../DualscreenPlugin.kt` | `FlutterPlugin` + `SecondDisplayManager` + `SecondDisplayPresentation` |

### Example app (`dualscreen/example/`)

| File | Status |
|---|---|
| `pubspec.yaml` | `dualscreen: path: ../` |
| `lib/main.dart` | entry-point router |
| `lib/main_window.dart` | desktop + Android POS UI |
| `lib/sub_window.dart` | desktop sub-window |
| `lib/sub_screen_entry.dart` | Android sub-screen entry + 3 screen widgets |
| `android/.../AndroidManifest.xml` | `resizeableActivity="true"` |
| `android/.../MainActivity.kt` | bare `FlutterActivity()` |

---

## Verification Steps

1. `flutter pub get` in `example/` — resolves without conflicts
2. `flutter analyze` in `example/` — zero issues
3. **macOS / Windows / Linux:**
   - `isSupported()` → `true`
   - "Open Sub Window (full screen)" → independent OS window fills secondary display
   - "Open Sub Window (640 × 480 centred)" → centred window on secondary display
   - Each sub-window counter is independent of main window and other sub-windows
   - "Close All" dismisses all sub-windows
   - Hot restart → stale sub-windows are closed automatically before new ones open
4. **Android — single display:** `isSupported()` → `false` → `_UnsupportedBanner` shown, no crash
5. **Android — dual display (POS):** Idle → OrderSummary (debounced updates) → PaymentPrompt → Idle
6. **iOS / Web:** `isSupported()` → `false` → banner shown, no crash
