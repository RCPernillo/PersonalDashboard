package com.pernillo.dashboard

/**
 * Configuración del tablero.
 *
 * Los SECRETOS (token de Telegram, llaves de Spotify, nombre de la bocina) NO
 * viven en este archivo ni en git. Se ponen en `local.properties` (que
 * .gitignore excluye) y Gradle los inyecta en BuildConfig al compilar; aquí
 * solo se leen. Así nunca se suben al repositorio.
 *
 * Pon tus valores en local.properties (ver README § "Antes de compilar"):
 *   TELEGRAM_BOT_TOKEN=123456789:AAF...
 *   TELEGRAM_CHAT_IDS=111111111,222222222
 *   SPOTIFY_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
 *   SPOTIFY_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
 *   SPEAKER_NAME=Nombre exacto de la bocina
 */
object Config {

    // ─── Telegram ─────────────────────────────────────────────────────────
    // Token que entrega @BotFather al crear el bot.
    val TELEGRAM_BOT_TOKEN: String = BuildConfig.TELEGRAM_BOT_TOKEN

    // Chat IDs autorizados: Roberto + esposa, separados por coma en
    // local.properties. Cualquier otro chat se ignora.
    val TELEGRAM_CHAT_IDS: Set<Long> = BuildConfig.TELEGRAM_CHAT_IDS
        .split(",")
        .mapNotNull { it.trim().toLongOrNull() }
        .toSet()

    // ─── Spotify (client credentials, solo búsqueda) ──────────────────────
    val SPOTIFY_CLIENT_ID: String = BuildConfig.SPOTIFY_CLIENT_ID
    val SPOTIFY_CLIENT_SECRET: String = BuildConfig.SPOTIFY_CLIENT_SECRET

    // ─── Bocina Bluetooth ─────────────────────────────────────────────────
    // Nombre EXACTO con el que la bocina aparece en Ajustes > Bluetooth.
    // La bocina debe emparejarse una vez a mano; la app solo re-conecta.
    val SPEAKER_NAME: String = BuildConfig.SPEAKER_NAME

    // ─── Zona horaria del hogar ───────────────────────────────────────────
    const val TIME_ZONE = "America/Guatemala"
}
