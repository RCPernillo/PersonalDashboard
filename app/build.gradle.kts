import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// ── Secretos fuera de git ──────────────────────────────────────────────────
// Se leen de local.properties (excluido por .gitignore) y Gradle los inyecta
// en BuildConfig al compilar. Nunca se suben al repositorio. Si falta un valor,
// queda en "" y la función correspondiente (Telegram/Spotify/bocina) se
// desactiva sola. Ver README § "Antes de compilar — secretos".
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun secret(key: String): String = (localProps.getProperty(key) ?: "")
    .trim()
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")

android {
    namespace = "com.pernillo.dashboard"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.pernillo.dashboard"
        minSdk = 30            // Xiaomi Pad 5 ships Android 11+, hoy corre MIUI 14 / HyperOS
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        // Secretos inyectados desde local.properties (ver arriba).
        buildConfigField("String", "TELEGRAM_BOT_TOKEN",    "\"${secret("TELEGRAM_BOT_TOKEN")}\"")
        buildConfigField("String", "TELEGRAM_CHAT_IDS",     "\"${secret("TELEGRAM_CHAT_IDS")}\"")
        buildConfigField("String", "SPOTIFY_CLIENT_ID",     "\"${secret("SPOTIFY_CLIENT_ID")}\"")
        buildConfigField("String", "SPOTIFY_CLIENT_SECRET", "\"${secret("SPOTIFY_CLIENT_SECRET")}\"")
        buildConfigField("String", "SPEAKER_NAME",          "\"${secret("SPEAKER_NAME")}\"")
    }

    buildFeatures {
        buildConfig = true   // AGP 8: BuildConfig está apagado por defecto
    }

    buildTypes {
        release {
            // Sin ofuscación: el proyecto es personal y así el APK es depurable.
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    // WebViewAssetLoader: sirve assets/ bajo https://appassets.androidx.dev
    // para que IndexedDB tenga un origen seguro y estable.
    implementation("androidx.webkit:webkit:1.11.0")
}
