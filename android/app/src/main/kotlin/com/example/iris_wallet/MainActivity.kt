package com.example.iris_wallet

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
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

    // Segredo de hardware ("pepper") que entra na cifra da semente. A chave HMAC
    // vive no Android Keystore (TEE/StrongBox) e NÃO é exportável: nem com root
    // dá para tirá-la do aparelho. Assim, derivar a chave da semente exige o
    // próprio celular — um PIN de 6 dígitos deixa de ser quebrável por força
    // bruta fora dele, mesmo que o blob cifrado vaze.
    private val pepperAlias = "iris_pepper_v1"

    private fun pepperKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(pepperAlias, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }
        val gen = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore"
        )
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(
            pepperAlias, KeyProperties.PURPOSE_SIGN
        ).apply {
            if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                setIsStrongBoxBacked(true)
            }
        }.build()
        return try {
            gen.init(spec(true)); gen.generateKey()
        } catch (e: Exception) {
            // Aparelho sem StrongBox: cai no TEE normal, ainda não-exportável.
            gen.init(spec(false)); gen.generateKey()
        }
    }

    private fun pepper(pin: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(pepperKey())
        return Base64.encodeToString(mac.doFinal(pin.toByteArray()), Base64.NO_WRAP)
    }

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
                    // Segredo de hardware para a cifra da semente; null se o
                    // Keystore falhar (aí o app usa só o PIN, como no desktop).
                    "pepper" -> {
                        try {
                            result.success(pepper(call.arguments as String))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    // Chave privada na área de transferência: marcada como
                    // sensível (o Android 13+ esconde a prévia) e apagada em 60 s
                    // se ninguém copiou outra coisa por cima.
                    "copiarSensivel" -> {
                        val texto = call.arguments as String
                        val cb = getSystemService(ClipboardManager::class.java)
                        val clip = ClipData.newPlainText("Iris", texto)
                        clip.description.extras = PersistableBundle().apply {
                            putBoolean("android.content.extra.IS_SENSITIVE", true)
                        }
                        cb.setPrimaryClip(clip)
                        Handler(Looper.getMainLooper()).postDelayed({
                            val atual = cb.primaryClip?.getItemAt(0)?.text?.toString()
                            if (atual == texto) {
                                if (Build.VERSION.SDK_INT >= 28) cb.clearPrimaryClip()
                                else cb.setPrimaryClip(ClipData.newPlainText("", ""))
                            }
                        }, 60_000)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
