package app.mylekha.extend_screen

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterJNI
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * `extend_screen` Flutter plugin — Android entry point.
 *
 * Registers with Flutter's plugin system via auto-registration
 * (GeneratedPluginRegistrant). No manual registration in MainActivity needed.
 *
 * Delegates all logic to [SecondDisplayManager].
 */
class ExtendScreenPlugin : FlutterPlugin {

    private var manager: SecondDisplayManager? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        manager = SecondDisplayManager(binding.applicationContext)
        manager!!.register(
            MethodChannel(binding.binaryMessenger, "second_display"),
            binding.binaryMessenger,
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        manager?.dispose()
        manager = null
    }
}

// ─── SecondDisplayManager ─────────────────────────────────────────────────────

/**
 * Manages a secondary Flutter engine rendered on a second physical display.
 *
 * Architecture:
 *
 *   Main FlutterEngine  →  MethodChannel("second_display")
 *     SecondDisplayManager bridges to →
 *   Sub FlutterEngine   →  MethodChannel("sub_screen_commands")
 *     sub_screen_entry.dart (subScreenMain entry point)
 *
 * Optimisations:
 *  - Sub-engine created lazily only when DisplayManager detects a Presentation display.
 *  - [FlutterEngineCache] prevents double-initialisation.
 *  - [initSecondDisplay] is guarded so the engine is never recreated while alive.
 *  - [SecondDisplayPresentation.detach] is called before engine destroy to
 *    prevent use-after-free in the FlutterView.
 */
private class SecondDisplayManager(
    private val context: Context,
) : DisplayManager.DisplayListener {

    companion object {
        private const val SUB_CHANNEL = "sub_screen_commands"
        private const val ENGINE_ID = "extend_screen_sub_engine"
    }

    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    // All three are null until a secondary display is connected.
    private var subEngine: FlutterEngine? = null
    private var presentation: SecondDisplayPresentation? = null
    private var subChannel: MethodChannel? = null

    // Retained so the reverse channel (secondary → main) can reach the main engine.
    private var mainMessenger: io.flutter.plugin.common.BinaryMessenger? = null

    fun register(mainChannel: MethodChannel, messenger: io.flutter.plugin.common.BinaryMessenger) {
        mainMessenger = messenger
        mainChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSecondDisplayAvailable" ->
                    result.success(getSecondDisplay() != null)

                "sendState" -> {
                    subChannel?.invokeMethod("updateState", call.arguments)
                    result.success(null)
                }

                "releaseSecondDisplay" -> {
                    releaseEngine()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        displayManager.registerDisplayListener(this, Handler(Looper.getMainLooper()))
        // Initialise immediately if a secondary display is already connected.
        getSecondDisplay()?.let { initSecondDisplay(it) }
    }

    fun dispose() {
        displayManager.unregisterDisplayListener(this)
        mainMessenger = null
        releaseEngine()
    }

    // ── DisplayManager.DisplayListener ────────────────────────────────────────

    override fun onDisplayAdded(displayId: Int) {
        if (displayId == Display.DEFAULT_DISPLAY) return
        val display = displayManager.getDisplay(displayId) ?: return
        if (!isWiredExternalDisplay(display)) return

        if (subEngine == null) {
            // First time — create the engine and show the presentation.
            initSecondDisplay(display)
        } else {
            // Engine already running (rapid reconnect) — just re-show the presentation.
            presentation?.detach()
            presentation?.dismiss()
            presentation = null
            try {
                presentation = SecondDisplayPresentation(context, display, subEngine!!)
                    .also { it.show() }
            } catch (e: Exception) {
                // Display rejected Presentation window — ignore.
            }
        }
    }

    override fun onDisplayRemoved(displayId: Int) {
        // Dismiss the Presentation window but keep the FlutterEngine alive.
        // Destroying and recreating the engine on every display reconnect event
        // exhausts Adreno GPU draw-context slots (errno 28) and crashes Flutter.
        presentation?.detach()
        presentation?.dismiss()
        presentation = null
        // Engine (subEngine) intentionally kept alive for rapid reconnect.
    }

    override fun onDisplayChanged(displayId: Int) {
        // Geometry / rotation changes — no action needed.
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun getSecondDisplay(): Display? =
        displayManager.getDisplays().firstOrNull { isWiredExternalDisplay(it) }

    /**
     * Returns true for physical wired external displays only.
     *
     * Acceptance criteria (all public API):
     *  - Not the built-in display (DEFAULT_DISPLAY)
     *  - Active (not STATE_OFF)
     *  - Not a private system overlay (FLAG_PRIVATE)
     *  - Supports Presentation windows (FLAG_PRESENTATION) — set on HDMI, USB-C, Samsung DeX,
     *    and POS dual-screen devices (Sunmi, PAX)
     *
     * Exclusion:
     *  - Miracast / WiFi displays: Android always names them "Wireless Display" (all locales).
     *    FLAG_PRESENTATION is also set on these so a name check is the only public-API way
     *    to distinguish them from wired displays.
     */
    private fun isWiredExternalDisplay(display: Display): Boolean {
        if (display.displayId == Display.DEFAULT_DISPLAY) return false
        if (display.state == Display.STATE_OFF) return false
        if (display.flags and Display.FLAG_PRIVATE != 0) return false
        if (display.flags and Display.FLAG_PRESENTATION == 0) return false
        // Exclude Miracast / WiFi Displays — Android names them consistently.
        val name = display.name.lowercase()
        if (name.contains("wireless") || name.contains("wifi") || name.contains("miracast")) {
            return false
        }
        return true
    }

    private fun initSecondDisplay(display: Display) {
        if (subEngine != null) return // Guard: never recreate while already running.

        try {
            // automaticallyRegisterPlugins = false prevents GeneratedPluginRegistrant
            // from registering ExtendScreenPlugin on this sub-engine, which would cause
            // infinite recursion (sub-engine → plugin registered → detects display →
            // creates another sub-engine → ...) exhausting Adreno GPU context slots.
            subEngine = FlutterEngine(context, null, FlutterJNI(), null, false).also { engine ->
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                        "subScreenMain" // @pragma('vm:entry-point') in sub_screen_entry.dart
                    )
                )
                FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
                subChannel = MethodChannel(engine.dartExecutor.binaryMessenger, SUB_CHANNEL)

                // Reverse channel: secondary display → main app.
                // The sub engine calls invokeMethod("sendState") on this channel;
                // we forward it as "updateState" to the main engine.
                val reverseSubChannel = MethodChannel(
                    engine.dartExecutor.binaryMessenger, "secondary_to_main"
                )
                reverseSubChannel.setMethodCallHandler { call, result ->
                    if (call.method == "sendState") {
                        mainMessenger?.let { messenger ->
                            MethodChannel(messenger, "secondary_to_main")
                                .invokeMethod("updateState", call.arguments)
                        }
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }
            }

            presentation = SecondDisplayPresentation(context, display, subEngine!!)
                .also { it.show() }
        } catch (e: Exception) {
            // Display does not support Presentation (e.g. Samsung virtual UI layer).
            // Clean up any partially initialised state and silently ignore.
            releaseEngine()
        }
    }

    private fun releaseEngine() {
        presentation?.detach()   // Detach FlutterView before engine destroy.
        presentation?.dismiss()
        presentation = null

        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        subEngine?.destroy()
        subEngine = null
        subChannel = null
    }
}

// ─── SecondDisplayPresentation ────────────────────────────────────────────────

/**
 * An Android [Presentation] window hosting a [FlutterView] on the secondary
 * physical display, backed by an independent [FlutterEngine].
 */
private class SecondDisplayPresentation(
    context: Context,
    display: Display,
    private val engine: FlutterEngine,
) : Presentation(context, display) {

    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        flutterView = FlutterView(context).also { view ->
            view.attachToFlutterEngine(engine)
            setContentView(view)
        }
    }

    /** Detach before [dismiss] / engine destroy to prevent use-after-free. */
    fun detach() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
    }
}
