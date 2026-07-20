package com.pernillo.dashboard

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Long polling contra api.telegram.org/getUpdates (NO webhook: la tablet vive
 * en la LAN sin endpoint público).
 *
 * Solo se atienden los dos chat IDs de Config.TELEGRAM_CHAT_IDS. Los mensajes
 * sin '/' inicial se ignoran. Los comandos se parsean aquí y se empujan a la
 * página como JSON; el JS escribe en IndexedDB y confirma vía telegramReply().
 *
 * Nota (README): con la pantalla apagada de 22:00 a 05:00 Android puede
 * congelar el proceso; Telegram retiene updates 24 h, así que los mensajes de
 * la noche se procesan al despertar a las 05:00.
 */
class TelegramPoller(private val activity: MainActivity) {

    companion object {
        private const val TAG = "TelegramPoller"
        private const val API = "https://api.telegram.org/bot"
        private const val PREFS = "telegram"
        private const val KEY_OFFSET = "offset"
        private const val POLL_TIMEOUT_S = 25
    }

    private val running = AtomicBoolean(false)
    private var offset: Long = 0

    fun start() {
        if (Config.TELEGRAM_BOT_TOKEN.startsWith("PEGA_AQUI")) {
            Log.w(TAG, "Sin token de Telegram: el loop no arranca (ver README)")
            return
        }
        if (!running.compareAndSet(false, true)) return
        offset = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_OFFSET, 0)
        thread(name = "telegram-poller") { pollLoop() }
    }

    fun stop() { running.set(false) }

    private fun pollLoop() {
        Log.i(TAG, "Long polling iniciado (offset=$offset)")
        while (running.get()) {
            try {
                val url = "$API${Config.TELEGRAM_BOT_TOKEN}/getUpdates" +
                        "?timeout=$POLL_TIMEOUT_S&offset=$offset&allowed_updates=%5B%22message%22%5D"
                val body = httpGet(url, (POLL_TIMEOUT_S + 10) * 1000) ?: continue
                val root = JSONObject(body)
                if (!root.optBoolean("ok")) {
                    Log.e(TAG, "getUpdates no-ok: $body"); Thread.sleep(5000); continue
                }
                val updates = root.getJSONArray("result")
                for (i in 0 until updates.length()) {
                    val update = updates.getJSONObject(i)
                    offset = update.getLong("update_id") + 1
                    handleUpdate(update)
                }
                if (updates.length() > 0) persistOffset()
            } catch (e: InterruptedException) {
                break
            } catch (e: Exception) {
                Log.e(TAG, "Error en el loop; reintento en 10 s", e)
                try { Thread.sleep(10_000) } catch (_: InterruptedException) { break }
            }
        }
        Log.i(TAG, "Long polling detenido")
    }

    private fun persistOffset() {
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putLong(KEY_OFFSET, offset).apply()
    }

    private fun handleUpdate(update: JSONObject) {
        val msg = update.optJSONObject("message") ?: return
        val chatId = msg.optJSONObject("chat")?.optLong("id") ?: return
        val text = msg.optString("text").trim()

        if (chatId !in Config.TELEGRAM_CHAT_IDS) {
            Log.w(TAG, "Chat no autorizado ignorado: $chatId")
            return
        }
        if (!text.startsWith("/")) return // sin comando, se ignora

        Log.i(TAG, "Comando de $chatId: $text")
        val space = text.indexOf(' ')
        val cmd = (if (space < 0) text else text.substring(0, space))
            .lowercase().removePrefix("/").substringBefore('@')
        val rest = if (space < 0) "" else text.substring(space + 1).trim()

        when (cmd) {
            "nota", "note" -> cmdNota(chatId, rest)
            "compra", "shop" -> cmdCompra(chatId, rest)
            "recordar", "reminder" -> cmdRecordar(chatId, rest)
            "servicio" -> cmdServicio(chatId, rest)
            "lista", "list" -> cmdLista(chatId, rest)
            "hecho", "done" -> cmdHecho(chatId, rest)
            "start", "ayuda", "help" -> sendMessage(chatId, helpText())
            else -> sendMessage(chatId, "No conozco /$cmd. Manda /ayuda para ver los comandos.")
        }
    }

    // ── Comandos ──────────────────────────────────────────────────────────

    private fun cmdNota(chatId: Long, rest: String) {
        if (rest.isEmpty()) { sendMessage(chatId, "Uso: /nota <texto>"); return }
        push(action("addNote", chatId).put("text", rest))
    }

    private fun cmdCompra(chatId: Long, rest: String) {
        if (rest.isEmpty()) { sendMessage(chatId, "Uso: /compra <item>[, item, ...]"); return }
        val items = JSONArray()
        rest.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            .forEach { items.put(it) }
        if (items.length() == 0) { sendMessage(chatId, "Uso: /compra <item>[, item, ...]"); return }
        push(action("addShopping", chatId).put("items", items))
    }

    private fun cmdRecordar(chatId: Long, rest: String) {
        if (rest.isEmpty()) {
            sendMessage(chatId, "Uso: /recordar 2026-08-23 Cumpleaños Ana\n" +
                    "o bien: /recordar Sacar la basura semanal")
            return
        }
        val dateRe = Regex("^(\\d{4}-\\d{2}-\\d{2})\\s+(.+)$")
        val m = dateRe.find(rest)
        if (m != null) {
            val (date, title) = m.destructured
            if (!isValidDate(date)) {
                sendMessage(chatId, "Fecha inválida: $date (formato AAAA-MM-DD)"); return
            }
            push(action("addEvent", chatId)
                .put("date", date).put("title", title.trim()).put("recurrence", "none"))
            return
        }
        // Recurrente: la última palabra es semanal|mensual; ancla en hoy.
        val words = rest.split(Regex("\\s+"))
        val recWord = words.last().lowercase()
        val recurrence = when (recWord) {
            "semanal", "weekly" -> "weekly"
            "mensual", "monthly" -> "monthly"
            else -> null
        }
        if (recurrence == null || words.size < 2) {
            sendMessage(chatId, "No entendí. Uso:\n/recordar 2026-08-23 Cumpleaños Ana\n" +
                    "/recordar Sacar la basura semanal")
            return
        }
        val title = words.dropLast(1).joinToString(" ")
        push(action("addEvent", chatId)
            .put("title", title).put("recurrence", recurrence))
    }

    private fun cmdServicio(chatId: Long, rest: String) {
        val m = Regex("^(\\d{4}-\\d{2}-\\d{2})\\s+(.+)$").find(rest)
        if (m == null) {
            sendMessage(chatId, "Uso: /servicio 2026-08-23 Bevy canto, Roberto cámara y multimedia")
            return
        }
        val (date, texto) = m.destructured
        if (!isValidDate(date)) {
            sendMessage(chatId, "Fecha inválida: $date (formato AAAA-MM-DD)"); return
        }
        push(action("setService", chatId).put("date", date).put("text", texto.trim()))
    }

    private fun cmdLista(chatId: Long, rest: String) {
        val what = when (rest.trim().lowercase()) {
            "compra", "compras", "shop" -> "compra"
            "notas", "nota", "notes" -> "notas"
            "" -> "all" // todo lo próximo
            else -> { sendMessage(chatId, "Uso: /lista compra | /lista notas | /lista"); return }
        }
        push(action("list", chatId).put("what", what))
    }

    private fun cmdHecho(chatId: Long, rest: String) {
        val m = Regex("^(compra|shop)\\s+(.+)$", RegexOption.IGNORE_CASE).find(rest)
        if (m == null) { sendMessage(chatId, "Uso: /hecho compra <item>"); return }
        push(action("doneShopping", chatId).put("item", m.groupValues[2].trim()))
    }

    private fun helpText() = """
        Comandos del tablero:
        /nota <texto> — agregar nota
        /compra <item>[, item, ...] — agregar a la lista de compras
        /recordar <AAAA-MM-DD> <título> — evento con fecha
        /recordar <título> semanal|mensual — evento recurrente
        /servicio <AAAA-MM-DD> <texto> — asignación del culto de ese domingo
        /lista compra | /lista notas | /lista — ver listas
        /hecho compra <item> — marcar item comprado
    """.trimIndent()

    // ── Utilidades ────────────────────────────────────────────────────────

    private fun action(name: String, chatId: Long): JSONObject =
        JSONObject().put("action", name).put("chatId", chatId.toString())

    /** El JSON viaja al WebView; el JS escribe en IndexedDB y confirma. */
    private fun push(obj: JSONObject) = activity.pushTelegramAction(obj.toString())

    private fun isValidDate(s: String): Boolean = try {
        java.time.LocalDate.parse(s); true
    } catch (_: Exception) { false }

    fun sendMessage(chatId: Long, text: String) {
        thread(name = "telegram-send") {
            try {
                val url = "$API${Config.TELEGRAM_BOT_TOKEN}/sendMessage"
                val body = "chat_id=$chatId&text=" + URLEncoder.encode(text, "UTF-8")
                httpPost(url, body)
            } catch (e: Exception) {
                Log.e(TAG, "No se pudo responder a $chatId", e)
            }
        }
    }

    private fun httpGet(url: String, timeoutMs: Int): String? {
        val conn = URL(url).openConnection() as HttpURLConnection
        return try {
            conn.connectTimeout = 15_000
            conn.readTimeout = timeoutMs
            conn.inputStream.bufferedReader().use(BufferedReader::readText)
        } catch (e: Exception) {
            Log.e(TAG, "GET falló: ${e.message}")
            Thread.sleep(5000)
            null
        } finally {
            conn.disconnect()
        }
    }

    private fun httpPost(url: String, formBody: String): String? {
        val conn = URL(url).openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            conn.outputStream.use { it.write(formBody.toByteArray()) }
            conn.inputStream.bufferedReader().use(BufferedReader::readText)
        } finally {
            conn.disconnect()
        }
    }
}
