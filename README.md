# extend_screen

A Flutter plugin for **multi-window support on desktop** and **dual-display support on Android**.

| Platform | Feature | How it works |
|---|---|---|
| Windows / macOS / Linux | Open multiple independent OS windows | `desktop_multi_window` — each window is a separate OS process with its own Flutter engine |
| Android | Mirror content to a secondary display | Android `Presentation` API — a second `FlutterEngine` drives the customer-facing screen |
| iOS / Web | Graceful no-op | `isSupported()` returns `false`; all other calls are silent no-ops |

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  extend_screen:
    path: ../extend_screen   # or pub.dev package name once published
```

Then run:

```bash
flutter pub get
```

---

## Quick Start

```dart
import 'package:extend_screen/extend_screen.dart';

// Obtain the singleton — platform is detected once and cached
final manager = await MultiWindowManager.instance();

if (await manager.isSupported()) {
  // Desktop: open a new OS window that fills the secondary display
  await manager.openSubWindow({'title': 'Customer Display'});

  // Android POS: push state to the customer-facing screen
  await manager.sendStateToSubDisplay(
    OrderSummaryState(items: cart, total: 49.99),
  );
}

// Clean up (call on app exit or when done)
await manager.closeAll();
```

---

## Desktop Integration

### 1. Route sub-windows in `main.dart`

The `desktop_multi_window` package re-invokes the app executable for each
sub-window with the arguments `['multi_window', windowId, argumentJson]`.
You must detect this at startup and run a different widget tree:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';

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

### 2. Open sub-windows

```dart
final manager = await MultiWindowManager.instance();

// Default — fills the secondary display (or primary if only one display)
await manager.openSubWindow({});

// Custom size: centred on the secondary display
await manager.openSubWindow(
  {'myData': 'hello'},
  size: const SubWindowSize.centered(width: 800, height: 600),
);

// Explicit frame (global screen coordinates, logical pixels)
await manager.openSubWindow(
  {},
  size: SubWindowSize.fixed(const Rect.fromLTWH(100, 100, 1280, 800)),
);
```

### 3. Pass data to the sub-window

The `argument` map is JSON-encoded and available in the sub-window's
`main(List<String> args)` as `jsonDecode(args[2])`:

```dart
// Main window
await manager.openSubWindow({'orderId': 42, 'customerName': 'Alice'});

// Sub-window (in MySubWindowApp)
class MySubWindowApp extends StatelessWidget {
  final Map<String, dynamic> argument;
  // argument['orderId'] == 42
  // argument['windowNumber'] is added automatically (1-based counter)
}
```

### 4. Close all sub-windows

```dart
await manager.closeAll();
```

---

## Android Integration

### 1. Add the sub-screen Dart entry point

The plugin starts a second `FlutterEngine` with a custom Dart entrypoint.
Add this function to your app (the `@pragma` prevents tree-shaking):

```dart
@pragma('vm:entry-point')
void subScreenMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MySubScreenApp());
}
```

`MySubScreenApp` listens on `MethodChannel('sub_screen_commands')` for
`'updateState'` calls sent by the plugin bridge:

```dart
class _MySubScreenAppState extends State<MySubScreenApp> {
  static const _channel = MethodChannel('sub_screen_commands');
  SubDisplayState _state = const IdleState();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateState') {
        setState(() {
          _state = SubDisplayState.fromJson(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: switch (_state) {
        IdleState()          => const IdleScreen(),
        OrderSummaryState s  => OrderSummaryScreen(items: s.items, total: s.total),
        PaymentPromptState s => PaymentPromptScreen(total: s.total),
      },
    );
  }
}
```

### 2. Update `AndroidManifest.xml`

Enable multi-window and presentation display support:

```xml
<activity
    android:name=".MainActivity"
    android:resizeableActivity="true"
    ...>
```

### 3. No `MainActivity` changes needed

The plugin registers itself automatically via `GeneratedPluginRegistrant`.
Keep `MainActivity` as a bare `FlutterActivity`:

```kotlin
class MainActivity : FlutterActivity()
```

### 4. Send state to the secondary display

```dart
final manager = await MultiWindowManager.instance();

if (await manager.isSupported()) {
  // Show idle/welcome screen
  await manager.sendStateToSubDisplay(const IdleState());

  // Update with order items
  await manager.sendStateToSubDisplay(
    OrderSummaryState(
      items: [
        {'name': 'Coffee', 'qty': 2, 'price': 3.50},
        {'name': 'Sandwich', 'qty': 1, 'price': 6.75},
      ],
      total: 13.75,
    ),
  );

  // Show payment prompt
  await manager.sendStateToSubDisplay(PaymentPromptState(total: 13.75));

  // Release the secondary display engine
  await manager.closeAll();
}
```

---

## API Reference

### `MultiWindowManager`

Singleton. Obtain via `MultiWindowManager.instance()`.

| Method | Description |
|---|---|
| `Future<bool> isSupported()` | Whether the current device/platform has an active secondary display or multi-window support |
| `Future<void> openSubWindow(Map<String,dynamic> argument, {SubWindowSize size})` | Desktop only — opens a new independent OS window |
| `Future<void> sendStateToSubDisplay(SubDisplayState state)` | Android only — pushes a state snapshot to the secondary-display Flutter engine |
| `Future<void> closeAll()` | Desktop: closes all sub-windows. Android: releases the secondary-display engine |

---

### `SubWindowSize`

Controls the initial frame of a desktop sub-window. Three constructors:

| Constructor | Behaviour |
|---|---|
| `SubWindowSize.fullScreen()` | Fills the secondary display. Falls back to the primary if only one display is present. **(default)** |
| `SubWindowSize.centered({required double width, required double height})` | A fixed logical size centred on the secondary display |
| `SubWindowSize.fixed(Rect frame)` | An exact frame in global screen coordinates (logical pixels). Use for non-standard display arrangements |

> **Multi-display layout assumption:** `fullScreen` and `centered` assume the secondary display
> is positioned **to the right** of the primary — the most common POS / dual-display setup.
> Use `SubWindowSize.fixed` for vertical stacking or other arrangements.

---

### `SubDisplayState`

Sealed class hierarchy for communicating with the Android secondary-display engine.

```dart
// Three concrete states
const IdleState()

OrderSummaryState(
  items: List<Map<String, dynamic>>,   // [{name, qty, price}]
  total: double,
)

PaymentPromptState(total: double)
```

Full JSON round-trip is built in:

```dart
final json = state.toJson();                          // Map<String, dynamic>
final state = SubDisplayState.fromJson(json);         // sealed → concrete type
```

---

## Platform Support

| Platform | `isSupported()` | `openSubWindow` | `sendStateToSubDisplay` |
|---|---|---|---|
| macOS | always `true` | ✅ | no-op |
| Windows | always `true` | ✅ | no-op |
| Linux | always `true` | ✅ | no-op |
| Android (secondary display connected) | `true` | no-op | ✅ |
| Android (no secondary display) | `false` | no-op | no-op |
| iOS | always `false` | no-op | no-op |
| Web | always `false` | no-op | no-op |

---

## Performance Tips

- **Debounce rapid state updates.** If your app pushes state on every keystroke or
  slider drag, add a short debounce (100–200 ms) so you don't saturate the MethodChannel:

  ```dart
  Timer? _debounce;

  void _onCartChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      manager.sendStateToSubDisplay(OrderSummaryState(items: cart, total: total));
    });
  }
  ```

- **Use `ValueNotifier` for scoped rebuilds.** Wrap fast-changing values (counters,
  totals) in `ValueNotifier` and read them with `ValueListenableBuilder` so only the
  affected widget rebuilds.

- **`isSupported()` is cached.** The first call queries the platform; subsequent calls
  return the cached result. Call it once in `initState` and store the result.

---

## Hot Restart on Desktop (Development)

Sub-windows are separate OS processes. When you hot-restart the main app, the Dart VM
resets all state but the sub-window processes keep running — leaving stale windows on
screen that the new manager instance cannot reach.

**This is handled automatically.** In debug builds, `MultiWindowManager.instance()`
queries the OS for all alive sub-window IDs and closes them before returning. You always
start from a clean slate after a hot restart.

*This cleanup only runs in `kDebugMode` — release builds are unaffected.*

---

## Example App

A full working demo is in the [`example/`](example/) directory.

```bash
cd example

# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux

# Android (connect a device with a secondary display for full POS demo)
flutter run -d <device-id>
```

The example demonstrates:

- **Desktop:** Main window with a counter and two "Open Sub Window" buttons
  (full-screen and 640 × 480 centred variants). Each sub-window has its own
  independent counter — no shared state between windows.
- **Android POS:** Cashier screen with Add Item / Payment / New Order buttons.
  The customer-facing display shows Idle → Order Summary → Payment Prompt states
  in real time.

---

## Requirements

| Requirement | Detail |
|---|---|
| Flutter | `>=3.10.0` |
| Dart | `^3.10.4` |
| Android `minSdk` | default Flutter `minSdkVersion` (no extra requirement) |
| `desktop_multi_window` | `^0.2.0` (transitive — no need to add manually) |

---

## Project Structure

```
lib/
├── extend_screen.dart                         ← public barrel export
└── src/
    ├── multi_window_manager.dart           ← abstract API + singleton factory
    ├── sub_display_state.dart              ← sealed state (Idle / OrderSummary / PaymentPrompt)
    ├── sub_window_size.dart                ← sealed window-size spec (fullScreen / centered / fixed)
    ├── desktop_multi_window_manager.dart   ← Windows / macOS / Linux implementation
    ├── android_second_display_manager.dart ← Android MethodChannel implementation
    └── unsupported_multi_window_manager.dart ← iOS / Web no-op fallback

android/src/main/kotlin/app/mylekha/package/extend_screen/
└── ExtendScreenPlugin.kt                     ← FlutterPlugin, Presentation API, second FlutterEngine

example/                                    ← runnable demo app
```
