package com.example.iris_wallet

import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "app.iriswallet/device"

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
                    else -> result.notImplemented()
                }
            }
    }
}
