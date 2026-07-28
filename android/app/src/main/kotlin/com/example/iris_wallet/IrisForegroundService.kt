package com.example.iris_wallet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Serviço em primeiro plano cuja única função é impedir que o Android suspenda
 * ou mate o processo do app quando ele vai para segundo plano (Doze/App
 * Standby). Não roda nenhum código Dart próprio nem duplica o nó — o nó
 * Lightning já embarcado continua rodando no MESMO processo/isolate
 * principal; este serviço só mantém esse processo vivo.
 *
 * Efeito prático: com o app minimizado (não fechado), o nó continua
 * sincronizando e recebendo pagamentos. Fechar o app (deslizar para fora dos
 * recentes) ainda encerra o processo — para sobreviver a isso de verdade em
 * desktop, o caminho é o daemon (iris-noded) como serviço do sistema.
 */
class IrisForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "iris_wallet_node_channel"
        private const val NOTIFICATION_ID = 4242
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // START_STICKY: se o sistema matar o processo mesmo assim sob pressão
        // extrema de memória, pede para o Android tentar recriar o serviço.
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nó Lightning ativo",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Mantém o nó Lightning sincronizando em segundo plano."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = if (openAppIntent != null) {
            PendingIntent.getActivity(
                this, 0, openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val builder = Notification.Builder(this).let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) it.setChannelId(CHANNEL_ID) else it
        }
        builder
            .setContentTitle("Iris Wallet")
            .setContentText("Nó Lightning ativo em segundo plano")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(contentIntent)
        return builder.build()
    }
}
