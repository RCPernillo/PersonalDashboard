package com.pernillo.dashboard

import android.content.Context
import android.os.BatteryManager
import android.util.Log
import android.webkit.JavascriptInterface
import org.json.JSONObject
import kotlin.concurrent.thread

/**
 * Puente JS ↔ nativo. En la página vive como `window.Android`.
 *
 * Métodos rápidos (batería, luz) responden en línea; los lentos (Spotify,
 * bocina) regresan por callback: window.onSpotifyResults / window.onSpeakerStatus.
 */
class DashboardBridge(private val activity: MainActivity) {

    companion object { private const val TAG = "DashboardBridge" }

    private val spotify = SpotifyClient()

    /** La página terminó de arrancar: vacía la cola de acciones pendientes. */
    @JavascriptInterface
    fun ready() {
        Log.i(TAG, "WebView listo")
        activity.onWebReady()
    }

    /** Estado inicial de tema según el reloj nativo (America/Guatemala). */
    @JavascriptInterface
    fun getThemeState(): String = ScreenScheduler.currentTheme()

    /** {"pct":87,"charging":true} leído de BatteryManager. */
    @JavascriptInterface
    fun getBattery(): String {
        val bm = activity.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val charging = bm.isCharging
        return JSONObject().put("pct", pct).put("charging", charging).toString()
    }

    /** STUB de la luz — ver LightController. Devuelve el estado simulado. */
    @JavascriptInterface
    fun toggleLight(): String = LightController.toggle()

    /**
     * Conexión A2DP a la bocina ya emparejada. Asíncrono: el resultado llega
     * por window.onSpeakerStatus(texto). Componente más frágil — probar al final.
     */
    @JavascriptInterface
    fun connectSpeaker() {
        SpeakerConnector.connect(activity) { status ->
            val safe = status.replace("\\", "\\\\").replace("'", "\\'")
            activity.pushJs("window.onSpeakerStatus && window.onSpeakerStatus('$safe')")
        }
    }

    /**
     * Búsqueda en Spotify (client credentials, todo en nativo). Asíncrono:
     * resultados por window.onSpotifyResults(jsonArray).
     */
    @JavascriptInterface
    fun spotifySearch(query: String) {
        thread(name = "spotify-search") {
            val json = spotify.searchTracks(query)
            val safe = json.replace("\\", "\\\\").replace("'", "\\'")
            activity.pushJs("window.onSpotifyResults && window.onSpotifyResults('$safe')")
        }
    }

    /** Abre un URI spotify: en la app de Spotify (deep link, no SDK). */
    @JavascriptInterface
    fun openSpotifyUri(uri: String) {
        if (uri.startsWith("spotify:")) activity.openSpotifyUri(uri)
    }

    /** El JS responde a un comando de Telegram (p. ej. la salida de /lista). */
    @JavascriptInterface
    fun telegramReply(chatId: String, text: String) {
        chatId.toLongOrNull()?.let { activity.sendTelegramMessage(it, text) }
    }

    @JavascriptInterface
    fun log(msg: String) = Log.i(TAG, "[web] $msg")
}
