package com.example.iris_wallet

import android.content.Intent
import android.os.Build
import android.view.WindowManager
import java.io.File
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Sinais comuns de root. Não é prova (dá para esconder), por isso o app só
    // AVISA: num aparelho com root, outro app pode ler os dados da carteira.
    private fun pareceRoot(): Boolean {
        val caminhos = listOf(
            "/system/xbin/su", "/system/bin/su", "/sbin/su", "/su/bin/su",
            "/system/app/Superuser.apk", "/data/adb/magisk", "/system/bin/magisk",
            "/data/local/bin/su", "/data/local/xbin/su"
        )
        if (caminhos.any { File(it).exists() }) return true
        return Build.TAGS?.contains("test-keys") == true
    }

    private val channelName = "app.iriswallet/device"
    private var backgroundServiceRunning = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // O plugin de NFC só informa se o adaptador está LIGADO. Para decidir se
        // o campo de NFC deve sequer existir na tela precisamos saber se o
        // aparelho TEM o hardware — são coisas diferentes: um celular com o NFC
        // desligado continua sendo compatível.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasNfcHardware" ->
                        result.success(
                            packageManager.hasSystemFeature(PackageManager.FEATURE_NFC)
                        )
                    "openNfcSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NFC_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    // Mantém o processo vivo em segundo plano (o nó Lightning já
                    // embarcado continua rodando neste mesmo processo) — ver
                    // IrisForegroundService.
                    "startBackgroundService" -> {
                        startForegroundService(Intent(this, IrisForegroundService::class.java))
                        backgroundServiceRunning = true
                        result.success(true)
                    }
                    "stopBackgroundService" -> {
                        stopService(Intent(this, IrisForegroundService::class.java))
                        backgroundServiceRunning = false
                        result.success(true)
                    }
                    "isBackgroundServiceRunning" ->
                        result.success(backgroundServiceRunning)
                    // Telas que mostram a frase-semente: sem captura, sem
                    // gravação de tela e sem miniatura nos recentes.
                    "protegerTela" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    "pareceRoot" -> result.success(pareceRoot())
                    else -> result.notImplemented()
                }
            }
    }
}
