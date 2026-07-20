plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.pernillo.dashboard"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.pernillo.dashboard"
        minSdk = 30            // Xiaomi Pad 5 ships Android 11+, hoy corre MIUI 14 / HyperOS
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
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
