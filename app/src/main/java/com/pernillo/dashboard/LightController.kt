package com.pernillo.dashboard

import android.util.Log
import org.json.JSONObject

/**
 * STUB de la luz de la sala. Estado simulado en memoria; NO controla hardware.
 *
 * // TODO: marca del interruptor TBD.
 * // Cuando se decida el interruptor, cablear aquí su API local (sin nube):
 * //
 * //  • Tuya/Smart Life: protocolo local tinytuya. Necesitas device_id,
 * //    local_key e IP fija. La forma más simple desde Kotlin es replicar el
 * //    protocolo 3.3 (AES-ECB con la local_key) o exponer un micro-servicio
 * //    tinytuya en otra máquina de la LAN... pero eso rompería "sin servidor";
 * //    mejor elegir un switch con HTTP local nativo:
 * //
 * //  • Shelly (recomendado, API HTTP local de fábrica):
 * //      GET http://IP_DEL_SHELLY/relay/0?turn=toggle
 * //      GET http://IP_DEL_SHELLY/relay/0  → {"ison":true,...}
 * //
 * //  • Sonoff con firmware Tasmota:
 * //      GET http://IP_DEL_SONOFF/cm?cmnd=Power%20TOGGLE  → {"POWER":"ON"}
 * //
 * // Al cablear: hacer la llamada HTTP en un thread (nunca en el del bridge),
 * // leer el estado real de la respuesta y devolverlo sin "stub":true.
 */
object LightController {

    private const val TAG = "LightController"
    private var mockOn = false // estado simulado, se pierde al cerrar la app

    fun toggle(): String {
        mockOn = !mockOn
        Log.i(TAG, "STUB: luz simulada → ${if (mockOn) "ENCENDIDA" else "APAGADA"} (sin hardware)")
        return JSONObject()
            .put("on", mockOn)
            .put("stub", true) // la UI lo muestra como SIMULADO
            .toString()
    }
}
