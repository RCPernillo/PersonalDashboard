package com.pernillo.dashboard

/**
 * Configuración personal del tablero.
 *
 * TODO: pega aquí tus llaves antes de compilar. El README explica paso a paso
 * cómo obtener cada valor. Nada de esto llega a la capa web: el token de
 * Telegram y las llaves de Spotify viven solo en el lado nativo.
 */
object Config {

    // ─── Telegram ─────────────────────────────────────────────────────────
    // Token que entrega @BotFather al crear el bot.
    const val TELEGRAM_BOT_TOKEN = "PEGA_AQUI_EL_TOKEN_DEL_BOT"

    // Chat IDs autorizados: Roberto + esposa. Cualquier otro chat se ignora.
    // Cómo encontrar el tuyo: README § "Telegram".
    val TELEGRAM_CHAT_IDS: Set<Long> = setOf(
        111111111L, // TODO: chat ID de Roberto
        222222222L  // TODO: chat ID de la esposa
    )

    // ─── Spotify (client credentials, solo búsqueda) ──────────────────────
    const val SPOTIFY_CLIENT_ID = "PEGA_AQUI_EL_CLIENT_ID"
    const val SPOTIFY_CLIENT_SECRET = "PEGA_AQUI_EL_CLIENT_SECRET"

    // ─── Bocina Bluetooth ─────────────────────────────────────────────────
    // Nombre EXACTO con el que la bocina aparece en Ajustes > Bluetooth.
    // La bocina debe emparejarse una vez a mano; la app solo re-conecta.
    const val SPEAKER_NAME = "NOMBRE_DE_LA_BOCINA"

    // ─── Zona horaria del hogar ───────────────────────────────────────────
    const val TIME_ZONE = "America/Guatemala"
}
