# Tablero de pared · Xiaomi Pad 5

Tablero personal para la pared de la casa: una app Android mínima (Kotlin) con un
WebView que carga un tablero HTML/CSS/JS desde `assets/`. **Gratis, sin tienda de
apps, sin servidor, sin nube, sin anuncios.** Todos los datos viven en la tablet
(IndexedDB). Idioma: español. Zona horaria: America/Guatemala.

Estética Teenage Engineering / OP-1: crema de día, casi negro de noche, naranja
`#ff5500` y verde apagado `#6b7d5a` solo como puntuación, líneas de 1 px, reloj
de matriz de puntos, etiquetas de panel estilo hardware (`01 · RELOJ`, …).

> **Otros proyectos en este repo** · [`garmin/circles-ultra`](garmin/circles-ultra/README.md):
> una esfera de reloj Garmin (Connect IQ) al estilo Apple Watch Ultra, pensada
> para el **Forerunner 165** y optimizada para ahorrar batería, con colores de
> acento e iconos personalizables.

---

## 1 · Compilar, firmar e instalar (sideload)

### Requisitos
- [Android Studio](https://developer.android.com/studio) (gratuito) o solo el SDK + JDK 17.
- La tablet con **Opciones de desarrollador → Depuración USB** activada
  (Ajustes → Sobre la tablet → tocar 7 veces "Versión de MIUI/HyperOS").

### Antes de compilar
Edita `app/src/main/java/com/pernillo/dashboard/Config.kt` y pega:
token del bot de Telegram, los **dos** chat IDs, las llaves de Spotify y el
nombre exacto de la bocina Bluetooth (secciones 3–5 de este README).

### Compilar e instalar
```bash
# APK de debug (suficiente para uso personal; firmado con la llave de debug)
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

Para un APK de release firmado con tu propia llave (opcional):
```bash
keytool -genkey -v -keystore tablero.keystore -alias tablero \
        -keyalg RSA -keysize 2048 -validity 10000
./gradlew assembleRelease
# firmar y alinear con apksigner/zipalign, o configura signingConfigs en app/build.gradle.kts
```

También puedes copiar el APK a la tablet y abrirlo desde el explorador de
archivos (permite "instalar apps de origen desconocido" cuando lo pida).

### Ajustes recomendados en la tablet
- **Pantalla → Tiempo de espera: 1 minuto.** La app mantiene la pantalla
  encendida de 05:00 a 22:00; a las 22:00 suelta el keep-awake y el timeout del
  sistema apaga el panel (no se puede apagar la pantalla por código sin
  permisos de administrador de dispositivo).
- **Batería → Sin restricciones** para "Tablero" (la app también pide la
  exención al arrancar). En HyperOS/MIUI además: Ajustes → Apps → Tablero →
  Ahorro de batería → **Sin restricciones**, y bloquea la app en Recientes
  (arrastra hacia abajo → candado) para que MIUI no la mate.
- **Otros permisos (MIUI/HyperOS) → "Mostrar ventanas emergentes mientras se
  ejecuta en segundo plano": permitir.** Es el plan B para que la app pueda
  relanzarse sola tras un reinicio o si el sistema la mató antes del corte de
  las 05:00 (Android 10+ bloquea eso por defecto; MIUI lo permite con este
  permiso).
- **Batería → Protección de la batería** (HyperOS): actívala y deja la tablet
  siempre conectada. La app **no** intenta controlar umbrales de carga por
  código — eso requiere root/APIs del fabricante; usa la protección nativa.
- Opcional: fija la app como launcher (Ajustes → Apps → Apps predeterminadas →
  Inicio) para que la tablet arranque directo al tablero.

### Permisos que pedirá al arrancar
- **Dispositivos cercanos / Bluetooth** (`BLUETOOTH_CONNECT`): para reconectar
  la bocina. Acepta.
- **Exención de optimización de batería**: para que el long polling de
  Telegram y las alarmas de tema sobrevivan. Acepta.
- **Alarmas exactas**: en Android 14 (`USE_EXACT_ALARM`) se concede sola; si el
  sistema la pide (Ajustes → Apps → Acceso especial → Alarmas y recordatorios),
  actívala para que los cortes 05:00/18:00/22:00 sean puntuales.

---

## 2 · Los tres estados de pantalla

| Horario (Guatemala) | Estado | Qué pasa |
|---|---|---|
| 05:00–18:00 | **LIGHT** | Crema `#f2ede3`, texto carbón. Pantalla siempre encendida. |
| 18:00–22:00 | **DARK** | Base casi negra `#0f0f0f`, texto crema. Mismo layout, solo se invierten base y texto. |
| 22:00–05:00 | **BLACK-OFF** | Capa negra total, se suelta el wakelock y la pantalla se apaga sola. A las 05:00 la alarma la despierta en LIGHT. |

Los cortes los disparan alarmas exactas nativas *y* un vigilante JS cada
segundo (doble seguro). El cambio es un intercambio de variables CSS: sin
recarga, sin parpadeo.

**Nota OLED/energía:** el crema diurno mantiene casi todos los píxeles
encendidos — es una decisión estética, no óptima en batería. El ahorro real
está en el estado DARK de la noche (en paneles OLED los píxeles oscuros
consumen menos) y sobre todo en el BLACK-OFF de 22:00–05:00. La pantalla del
Pad 5 es IPS (retroiluminación), así que ahí el ahorro grande es el apagado
nocturno; el comentario OLED aplica si algún día migra a otra tablet.

---

## 3 · Telegram (long polling, sin webhook)

La tablet vive en la LAN sin IP pública, así que el shell nativo hace **long
polling** a `getUpdates` — no hay webhook ni servidor.

### Crear el bot
1. En Telegram habla con **@BotFather** → `/newbot` → nombre y usuario.
2. Copia el **token** (formato `123456789:AAF...`) en
   `Config.TELEGRAM_BOT_TOKEN`.

### Encontrar el chat ID de cada uno (Roberto y esposa)
1. Cada persona le escribe cualquier mensaje al bot nuevo (p. ej. "hola").
2. Abre en el navegador:
   `https://api.telegram.org/bot<TU_TOKEN>/getUpdates`
3. Busca `"chat":{"id":123456789,...}` — ese número es el chat ID de quien
   escribió. Repite con la otra persona.
4. Pega ambos números en `Config.TELEGRAM_CHAT_IDS`. **Cualquier otro chat se
   ignora por completo.**

### Comandos (español primero, alias en inglés)
| Comando | Alias | Hace |
|---|---|---|
| `/nota <texto>` | `/note` | Agrega una nota |
| `/compra <item>[, item, ...]` | `/shop` | Agrega compras (separa por comas) |
| `/recordar <AAAA-MM-DD> <título>` | `/reminder` | Evento con fecha |
| `/recordar <título> semanal\|mensual` | `/reminder` | Evento recurrente (ancla en hoy) |
| `/servicio <AAAA-MM-DD> <texto>` | — | Asignación del culto de ese domingo, p. ej. `/servicio 2026-08-23 Bevy canto, Roberto cámara y multimedia` |
| `/lista compra` · `/lista notas` · `/lista` | `/list` | El bot responde con la lista (o todo lo próximo) |
| `/hecho compra <item>` | `/done` | Marca el item que coincida como comprado |

Los mensajes **sin `/` inicial se ignoran**. El bot confirma cada alta con una
respuesta corta en español.

**Nota nocturna:** de 22:00 a 05:00 la pantalla está apagada y Android puede
congelar el proceso; Telegram retiene los updates 24 h, así que lo que se envíe
de noche se procesa al despertar a las 05:00.

---

## 4 · Spotify (deep link, sin SDK de reproducción)

La búsqueda usa el flujo **client credentials** (solo catálogo) desde Kotlin;
las llaves nunca tocan la capa web. Al tocar un resultado se abre el URI
`spotify:track:…` con un Intent → reproduce la **app oficial de Spotify** (que
debe estar instalada y con sesión iniciada) → suena por la bocina conectada.

1. Entra a <https://developer.spotify.com/dashboard> (cuenta gratuita sirve).
2. **Create app** → nombre cualquiera; Redirect URI no se usa (pon
   `http://localhost/` si es obligatorio).
3. Copia **Client ID** y **Client Secret** en `Config.SPOTIFY_CLIENT_ID` /
   `SPOTIFY_CLIENT_SECRET`.

Si tu cuenta de Spotify es gratuita, la app de Spotify meterá sus propios
anuncios — el tablero no agrega ninguno.

---

## 5 · Los dos stubs de hardware (pendientes de cablear)

### Luz (`toggleLight`) — **STUB, no controla nada**
`LightController.kt` simula el estado y lo marca `"stub": true` (la UI muestra
"SIMULADA"). `// TODO: marca del interruptor TBD`. El comentario del archivo
trae las tres rutas locales típicas:
- **Shelly** (recomendado): `GET http://IP/relay/0?turn=toggle` — HTTP local de fábrica.
- **Sonoff + Tasmota**: `GET http://IP/cm?cmnd=Power%20TOGGLE`.
- **Tuya/Smart Life**: protocolo local tipo tinytuya (device_id + local_key);
  más engorroso desde Kotlin — mejor elegir un switch con HTTP local nativo.

### Bocina (`connectSpeaker`) — el componente MÁS FRÁGIL; probar al final
- **Empareja la bocina una vez a mano** (Ajustes → Bluetooth). Verifica que
  aparece en la lista de dispositivos vinculados con el nombre exacto que
  pusiste en `Config.SPEAKER_NAME`.
- El botón "Conectar Bocina" busca ese nombre entre los vinculados y llama
  `BluetoothA2dp.connect()` **por reflexión** (es API oculta). En algunas ROMs
  HyperOS/MIUI el sistema la bloquea; el estado se reporta en pantalla y el
  log es muy verboso: `adb logcat -s SpeakerConnector`.
- Si la reflexión falla en tu ROM, el plan B honesto es conectar desde
  Ajustes → Bluetooth (un toque) y usar el tablero solo para búsqueda/play.

---

## 6 · Datos y edición

- Todo vive en **IndexedDB** dentro del WebView (origen estable vía
  `WebViewAssetLoader`). Sin backend, sin sincronización, nada sale del
  dispositivo (excepto los mensajes que el bot de Telegram responde).
- Almacenes: `events`, `meals` (4 menús fijos, Semana 1–4, rotación mensual),
  `notes`, `shopping`. Con datos de muestra al primer arranque.
- Todo se puede editar en la tablet: eventos con el botón `+` del panel
  `03 · MES` (alta/edición/borrado), menús con EDITAR, notas y compras en sus
  fólderes.
- Los domingos se marcan solos como día de culto (punto verde hueco); un
  domingo con asignación (`/servicio` o el editor) pasa a punto verde sólido y
  muestra el texto en `03 · MES`.

## 7 · Versículo diario

`assets/data/versiculos.json` trae 365 versículos (Reina-Valera 1960) elegidos
por día del año — sin red ni API; el 366 de los bisiestos reutiliza el 365.
Los textos fueron transcritos a mano: revisa/corrige el JSON si encuentras una
palabra fuera de lugar, es un archivo plano y editable.

## 8 · Estructura

```
app/src/main/java/com/pernillo/dashboard/
  MainActivity.kt      actividad única, WebView + inmersivo + keep-awake
  Config.kt            ← TUS LLAVES AQUÍ
  DashboardBridge.kt   puente JS↔nativo (@JavascriptInterface)
  TelegramPoller.kt    long polling + parser de comandos
  SpotifyClient.kt     token client-credentials + búsqueda
  LightController.kt   STUB de la luz (TODO marca TBD)
  SpeakerConnector.kt  conexión A2DP por reflexión (frágil, probar al final)
  ScreenScheduler.kt   alarmas 05:00/18:00/22:00 + receivers
app/src/main/assets/   el tablero web (HTML/CSS/JS + versículos)
```

## 9 · Orden de construcción sugerido (ya reflejado en el código)

1. Shell + zona de vistazo (reloj/calendario/mes/versículo + 3 temas). ✅
2. Fólderes del archivero + datos locales + edición en pantalla. ✅
3. Telegram con todos los comandos (español + alias). ✅
4. Luz: stub ✅ → cablear cuando haya interruptor (TODO).
5. Bluetooth (bocina) — implementado, **probar de último** en la ROM real.
