package app.mylekha.package.dualscreen

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * `dualscreen` Flutter plugin — Android entry point.
 *
 * Registers with Flutter's plugin system via auto-registration
 * (GeneratedPluginRegistrant). No manual registration in MainActivity needed.
 *
 * Delegates all logic to [SecondDisplayManager].
 */
class DualscreenPlugin : FlutterPlugin {

    private var manager: SecondDisplayManager? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        manager = SecondDisplayManager(binding.applicationContext)
        manager!!.register(
            MethodChannel(binding.binaryMessenger, "second_display")
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
        private const val ENGINE_ID = "dualscreen_sub_engine"
    }

    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    // All three are null until a secondary display is connected.
    private var subEngine: FlutterEngine? = null
    private var presentation: SecondDisplayPresentation? = null
    private var subChannel: MethodChannel? = null

    fun register(mainChannel: MethodChannel) {
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

        displayManager.registerDisplayListener(this, null)
        // Initialise immediately if a secondary display is already connected.
        getSecondDisplay()?.let { initSecondDisplay(it) }
    }

    fun dispose() {
        displayManager.unregisterDisplayListener(this)
        releaseEngine()
    }

    // ── DisplayManager.DisplayListener ────────────────────────────────────────

    override fun onDisplayAdded(displayId: Int) {
        displayManager.getDisplay(displayId)?.let { initSecondDisplay(it) }
    }

    override fun onDisplayRemoved(displayId: Int) {
        releaseEngine()
    }

    override fun onDisplayChanged(displayId: Int) {
        // Geometry / rotation changes — no action needed.
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun getSecondDisplay(): Display? =
        displayManager
            .getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .firstOrNull()

    private fun initSecondDisplay(display: Display) {
        if (subEngine != null) return // Guard: never recreate while already running.

        subEngine = FlutterEngine(context).also { engine ->
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "subScreenMain" // @pragma('vm:entry-point') in sub_screen_entry.dart
                )
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            subChannel = MethodChannel(engine.dartExecutor.binaryMessenger, SUB_CHANNEL)
        }

        presentation = SecondDisplayPresentation(context, display, subEngine!!)
            .also { it.show() }
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
