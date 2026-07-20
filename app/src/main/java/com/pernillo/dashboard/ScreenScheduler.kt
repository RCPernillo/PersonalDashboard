package com.pernillo.dashboard

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Programa alarmas exactas en los cortes de tema (hora local de Guatemala):
 *   05:00 → LIGHT   ·   18:00 → DARK   ·   22:00 → BLACK-OFF
 *
 * Cada alarma relanza MainActivity con el tema como extra; la actividad ajusta
 * keepScreenOn/wakelock y avisa al JS (setTheme) — el JS también vigila el
 * reloj por su cuenta, así que esto es cinturón y tirantes.
 */
object ScreenScheduler {

    private const val TAG = "ScreenScheduler"
    private val ZONE: ZoneId = ZoneId.of(Config.TIME_ZONE)

    // (hora, tema que inicia a esa hora)
    private val BOUNDARIES = listOf(
        5 to "light",
        18 to "dark",
        22 to "off"
    )

    fun currentTheme(now: ZonedDateTime = ZonedDateTime.now(ZONE)): String {
        val h = now.hour
        return when {
            h in 5..17 -> "light"
            h in 18..21 -> "dark"
            else -> "off"
        }
    }

    fun scheduleNext(context: Context) {
        val now = ZonedDateTime.now(ZONE)
        // Próximo corte estrictamente en el futuro.
        val next = BOUNDARIES
            .map { (hour, theme) ->
                var t = now.with(LocalTime.of(hour, 0)).withSecond(0).withNano(0)
                if (!t.isAfter(now)) t = t.plusDays(1)
                t to theme
            }
            .minByOrNull { it.first }!!

        val (fireAt, theme) = next
        val intent = Intent(context, ThemeAlarmReceiver::class.java)
            .putExtra(MainActivity.EXTRA_THEME, theme)
        val pi = PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val millis = fireAt.toInstant().toEpochMilli()
        try {
            // canScheduleExactAlarms existe desde API 31; antes era implícito.
            if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
                Log.i(TAG, "Alarma exacta: $theme @ $fireAt")
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
                Log.w(TAG, "Sin permiso de alarma exacta; usando inexacta: $theme @ $fireAt")
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            Log.w(TAG, "SecurityException; alarma inexacta programada", e)
        }
    }
}

/**
 * Corte de tema: re-programa la siguiente alarma y aplica el tema.
 *
 * Se habla directo con la actividad viva (MainActivity.live): Android 10+
 * bloquea startActivity desde receivers en segundo plano. El startActivity
 * queda solo como plan B por si el sistema mató la app (en MIUI/HyperOS
 * funciona si se concede "ventanas emergentes en segundo plano", ver README).
 */
class ThemeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val theme = intent.getStringExtra(MainActivity.EXTRA_THEME) ?: return
        Log.i("ThemeAlarmReceiver", "Corte de tema: $theme")
        ScreenScheduler.scheduleNext(context)

        val activity = MainActivity.live?.get()
        if (activity != null) {
            activity.applyThemePowerState(theme) // enciende/apaga keep-awake
            activity.pushJs("window.setTheme && window.setTheme('$theme')")
        } else {
            Log.w("ThemeAlarmReceiver", "Actividad muerta; intentando relanzar")
            try {
                context.startActivity(
                    Intent(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        .putExtra(MainActivity.EXTRA_THEME, theme)
                )
            } catch (e: Exception) {
                Log.e("ThemeAlarmReceiver", "No se pudo relanzar la actividad", e)
            }
        }
    }
}

/**
 * Tras reiniciar la tablet: re-programa alarmas e intenta relanzar el
 * tablero. El relanzamiento automático desde boot está restringido en
 * Android 10+; funciona si la app es el launcher (HOME) o si MIUI/HyperOS
 * tiene concedido "ventanas emergentes en segundo plano" (ver README).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        Log.i("BootReceiver", "Arranque: re-programando tablero")
        ScreenScheduler.scheduleNext(context)
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            Log.w("BootReceiver", "Relanzamiento bloqueado; abrir a mano", e)
        }
    }
}
