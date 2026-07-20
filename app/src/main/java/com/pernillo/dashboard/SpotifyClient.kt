package com.pernillo.dashboard

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Búsqueda en Spotify vía client credentials — deep link, NO Web Playback SDK.
 *
 * Las llaves viven en Config (lado nativo); la capa web nunca las ve. El flujo
 * client-credentials solo permite búsqueda/catálogo, suficiente porque la
 * reproducción sale por la app oficial de Spotify (Intent con URI spotify:).
 */
class SpotifyClient {

    companion object {
        private const val TAG = "SpotifyClient"
        private const val TOKEN_URL = "https://accounts.spotify.com/api/token"
        private const val SEARCH_URL = "https://api.spotify.com/v1/search"
    }

    private var token: String? = null
    private var tokenExpiresAt: Long = 0

    /**
     * Devuelve un JSON string:
     *   {"tracks":[{"name":..,"artist":..,"uri":"spotify:track:.."},...]}
     * o {"error":"mensaje en español"} si algo falla.
     */
    fun searchTracks(query: String): String {
        if (Config.SPOTIFY_CLIENT_ID.startsWith("PEGA_AQUI")) {
            return error("Faltan las llaves de Spotify (ver README)")
        }
        if (query.isBlank()) return error("Búsqueda vacía")
        return try {
            val tk = getToken() ?: return error("No se pudo obtener token de Spotify")
            val url = "$SEARCH_URL?type=track&limit=12&market=GT&q=" +
                    URLEncoder.encode(query.trim(), "UTF-8")
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.setRequestProperty("Authorization", "Bearer $tk")
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            val body = conn.inputStream.bufferedReader().use(BufferedReader::readText)
            conn.disconnect()

            val items = JSONObject(body)
                .getJSONObject("tracks").getJSONArray("items")
            val out = JSONArray()
            for (i in 0 until items.length()) {
                val t = items.getJSONObject(i)
                val artists = t.getJSONArray("artists")
                val names = (0 until artists.length())
                    .joinToString(", ") { artists.getJSONObject(it).getString("name") }
                out.put(
                    JSONObject()
                        .put("name", t.getString("name"))
                        .put("artist", names)
                        .put("uri", t.getString("uri"))
                )
            }
            JSONObject().put("tracks", out).toString()
        } catch (e: Exception) {
            Log.e(TAG, "Búsqueda falló", e)
            error("Error de red buscando en Spotify")
        }
    }

    @Synchronized
    private fun getToken(): String? {
        val now = System.currentTimeMillis()
        if (token != null && now < tokenExpiresAt - 30_000) return token
        return try {
            val creds = "${Config.SPOTIFY_CLIENT_ID}:${Config.SPOTIFY_CLIENT_SECRET}"
            val basic = Base64.encodeToString(creds.toByteArray(), Base64.NO_WRAP)
            val conn = URL(TOKEN_URL).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Authorization", "Basic $basic")
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            conn.outputStream.use { it.write("grant_type=client_credentials".toByteArray()) }
            val body = conn.inputStream.bufferedReader().use(BufferedReader::readText)
            conn.disconnect()
            val json = JSONObject(body)
            token = json.getString("access_token")
            tokenExpiresAt = now + json.getLong("expires_in") * 1000
            token
        } catch (e: Exception) {
            Log.e(TAG, "Token falló", e)
            null
        }
    }

    private fun error(msg: String) = JSONObject().put("error", msg).toString()
}
