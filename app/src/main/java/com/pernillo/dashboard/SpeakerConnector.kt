package com.pernillo.dashboard

import android.annotation.SuppressLint
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.util.Log

/**
 * Conexión A2DP a una bocina YA EMPAREJADA (el emparejamiento se hace una vez
 * a mano en Ajustes > Bluetooth; aquí solo re-conectamos).
 *
 * ⚠️ COMPONENTE MÁS FRÁGIL DEL PROYECTO — construir y probar AL FINAL.
 * BluetoothA2dp.connect(device) es API oculta: se invoca por reflexión y puede
 * fallar según la versión de HyperOS/MIUI. Si la reflexión falla, el fallback
 * honesto es reportar el estado y dejar que el usuario conecte desde Ajustes.
 * Log MUY verboso a propósito: `adb logcat -s SpeakerConnector` cuenta todo.
 */
object SpeakerConnector {

    private const val TAG = "SpeakerConnector"

    @SuppressLint("MissingPermission") // BLUETOOTH_CONNECT se pide en MainActivity
    fun connect(context: Context, onStatus: (String) -> Unit) {
        Log.i(TAG, "connectSpeaker(): buscando '${Config.SPEAKER_NAME}'")
        onStatus("Conectando bocina…")

        if (Config.SPEAKER_NAME == "NOMBRE_DE_LA_BOCINA") {
            Log.w(TAG, "Config.SPEAKER_NAME sin configurar")
            onStatus("Configura el nombre de la bocina (Config.kt)")
            return
        }

        val adapter: BluetoothAdapter? =
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "Bluetooth apagado o no disponible")
            onStatus("Bluetooth apagado")
            return
        }

        val device: BluetoothDevice? = try {
            adapter.bondedDevices.firstOrNull { it.name == Config.SPEAKER_NAME }
        } catch (e: SecurityException) {
            Log.e(TAG, "Sin permiso BLUETOOTH_CONNECT", e)
            onStatus("Falta permiso Bluetooth")
            return
        }
        if (device == null) {
            Log.e(TAG, "'${Config.SPEAKER_NAME}' no está emparejada. Emparejadas: " +
                    adapter.bondedDevices.joinToString { it.name ?: "?" })
            onStatus("Bocina no emparejada (hazlo una vez en Ajustes)")
            return
        }
        Log.i(TAG, "Dispositivo encontrado: ${device.name} [${device.address}]")

        val ok = adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                Log.i(TAG, "Proxy A2DP obtenido")
                val a2dp = proxy as BluetoothA2dp
                try {
                    if (a2dp.connectedDevices.any { it.address == device.address }) {
                        Log.i(TAG, "Ya estaba conectada")
                        onStatus("Bocina ya conectada ✓")
                        return
                    }
                    // connect(BluetoothDevice) es @hide → reflexión.
                    Log.i(TAG, "Invocando BluetoothA2dp.connect() por reflexión…")
                    val m = BluetoothA2dp::class.java
                        .getMethod("connect", BluetoothDevice::class.java)
                    val result = m.invoke(a2dp, device)
                    Log.i(TAG, "connect() devolvió: $result")
                    onStatus(
                        if (result == true) "Conectando a ${device.name}…"
                        else "El sistema rechazó la conexión (intenta desde Ajustes)"
                    )
                } catch (e: NoSuchMethodException) {
                    Log.e(TAG, "Reflexión falló: connect() no existe en esta ROM", e)
                    onStatus("Esta versión de Android bloquea la conexión directa")
                } catch (e: Exception) {
                    Log.e(TAG, "Fallo conectando A2DP", e)
                    onStatus("Error al conectar (ver logcat SpeakerConnector)")
                } finally {
                    adapter.closeProfileProxy(BluetoothProfile.A2DP, proxy)
                }
            }

            override fun onServiceDisconnected(profile: Int) {
                Log.w(TAG, "Proxy A2DP desconectado")
            }
        }, BluetoothProfile.A2DP)

        if (!ok) {
            Log.e(TAG, "getProfileProxy devolvió false")
            onStatus("No se pudo abrir el perfil A2DP")
        }
    }
}
