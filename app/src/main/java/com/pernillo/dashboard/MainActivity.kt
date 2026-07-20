package com.pernillo.dashboard

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import java.lang.ref.WeakReference

/**
 * Actividad única: WebView a pantalla completa que carga el tablero desde
 * assets/. Todo lo demás (Telegram, Spotify, alarmas de tema) cuelga de aquí.
 */
class MainActivity : Activity() {

    companion object {
        private const val TAG = "Dashboard"
        const val EXTRA_THEME = "theme" // "light" | "dark" | "off"
        private const val START_URL = "https://appassets.androidx.dev/assets/index.html"

        /**
         * Instancia viva para que ThemeAlarmReceiver le hable directo:
         * en Android 10+ un receiver en segundo plano no puede lanzar
         * actividades, pero sí puede tocar la actividad ya existente.
         */
        @Volatile
        var live: WeakReference<MainActivity>? = null
    }

    lateinit var webView: WebView
        private set

    private lateinit var bridge: DashboardBridge
    private var telegramPoller: TelegramPoller? = null
    private var webReady = false
    private val pendingJs = ArrayDeque<String>()

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        live = WeakReference(this)

        setShowWhenLocked(true)
        setTurnScreenOn(true)

        webView = WebView(this)
        webView.setBackgroundColor(android.graphics.Color.BLACK)
        setContentView(webView)

        val assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true      // IndexedDB
            mediaPlaybackRequiresUserGesture = false
            textZoom = 100
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView, request: WebResourceRequest
            ): WebResourceResponse? = assetLoader.shouldInterceptRequest(request.url)

            override fun onPageFinished(view: WebView, url: String) {
                // El JS avisa con Android.ready(); esto es solo respaldo de log.
                Log.i(TAG, "Página cargada: $url")
            }
        }

        bridge = DashboardBridge(this)
        webView.addJavascriptInterface(bridge, "Android")
        webView.loadUrl(START_URL)

        requestRuntimePermissions()
        requestBatteryOptimizationExemption()

        telegramPoller = TelegramPoller(this).also { it.start() }

        ScreenScheduler.scheduleNext(this)
        applyThemePowerState(ScreenScheduler.currentTheme())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Disparado por ThemeAlarmReceiver en cada corte 05:00 / 18:00 / 22:00.
        intent.getStringExtra(EXTRA_THEME)?.let { theme ->
            Log.i(TAG, "Corte de tema recibido: $theme")
            applyThemePowerState(theme)
            pushJs("window.setTheme && window.setTheme('$theme')")
        }
    }

    override fun onResume() {
        super.onResume()
        enterImmersiveMode()
        // Al volver, re-sincroniza tema y keep-awake por si dormimos un corte.
        applyThemePowerState(ScreenScheduler.currentTheme())
        pushJs("window.syncTheme && window.syncTheme()")
    }

    override fun onDestroy() {
        if (live?.get() === this) live = null
        telegramPoller?.stop()
        super.onDestroy()
    }

    /** LIGHT/DARK: pantalla siempre encendida. OFF: se suelta el keep-awake. */
    fun applyThemePowerState(theme: String) {
        runOnUiThread {
            if (theme == "off") {
                webView.keepScreenOn = false
                // La pantalla se apagará sola al vencer el timeout del sistema
                // (ver README: poner el timeout en 1 minuto). No se puede
                // apagar la pantalla por código sin device-admin.
            } else {
                webView.keepScreenOn = true
                wakeScreen()
            }
        }
    }

    /** Despierta la pantalla a las 05:00 (vuelta de BLACK-OFF a LIGHT). */
    private fun wakeScreen() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                @Suppress("DEPRECATION")
                val wl = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "dashboard:wake"
                )
                wl.acquire(10_000)
                Log.i(TAG, "Wakelock de despertar adquirido (10 s)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo despertar la pantalla", e)
        }
    }

    private fun enterImmersiveMode() {
        window.insetsController?.let { c ->
            c.hide(WindowInsets.Type.systemBars())
            c.systemBarsBehavior =
                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterImmersiveMode()
    }

    // ── Puente hacia la página ────────────────────────────────────────────

    /** El JS llamó a Android.ready(): vacía la cola de mensajes pendientes. */
    fun onWebReady() {
        runOnUiThread {
            webReady = true
            while (pendingJs.isNotEmpty()) {
                webView.evaluateJavascript(pendingJs.removeFirst(), null)
            }
        }
    }

    /** Ejecuta JS en la página; si aún no está lista, lo encola. */
    fun pushJs(js: String) {
        runOnUiThread {
            if (webReady) webView.evaluateJavascript(js, null) else pendingJs.addLast(js)
        }
    }

    /** El loop de Telegram empuja acciones ya parseadas (JSON) a la página. */
    fun pushTelegramAction(actionJson: String) {
        // JSON.parse del lado JS; se pasa como literal entre comillas simples.
        val escaped = actionJson
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "\\n")
        pushJs("window.TG && window.TG.handle('$escaped')")
    }

    fun sendTelegramMessage(chatId: Long, text: String) {
        telegramPoller?.sendMessage(chatId, text)
    }

    fun openSpotifyUri(uri: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                putExtra(Intent.EXTRA_REFERRER, Uri.parse("android-app://$packageName"))
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo abrir Spotify (¿está instalado?)", e)
            pushJs("window.onSpotifyError && window.onSpotifyError('Spotify no está instalado')")
        }
    }

    // ── Permisos ──────────────────────────────────────────────────────────

    private fun requestRuntimePermissions() {
        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 1)
        }
    }

    @SuppressLint("BatteryLife")
    private fun requestBatteryOptimizationExemption() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    )
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo pedir exención de batería", e)
        }
    }
}
