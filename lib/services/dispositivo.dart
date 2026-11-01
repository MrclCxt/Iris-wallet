import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Proteções que dependem da plataforma (Android).
class Dispositivo {
  static const _canal = MethodChannel('app.iriswallet/device');

  /// Liga/desliga o bloqueio de captura e gravação de tela (FLAG_SECURE).
  static Future<void> protegerTela(bool ligar) async {
    if (!Platform.isAndroid) return;
    try {
      await _canal.invokeMethod('protegerTela', ligar);
    } catch (_) {}
  }

  /// Copia segredo (chave privada): no Android vai marcado como sensível e
  /// some da área de transferência em 60 s. Nas outras plataformas, cópia
  /// comum.
  static Future<void> copiarSensivel(String texto) async {
    if (Platform.isAndroid) {
      try {
        await _canal.invokeMethod('copiarSensivel', texto);
        return;
      } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text: texto));
  }

  /// Segredo de hardware (HMAC do PIN por uma chave não-exportável do Keystore)
  /// misturado à cifra da semente. `null` fora do Android ou se o Keystore
  /// falhar — nesse caso a cifra usa só o PIN. Chamar sempre na isolate
  /// principal (usa canal de plataforma) e passar os bytes para a cifra.
  static Future<List<int>?> pepper(String pin) async {
    if (!Platform.isAndroid) return null;
    try {
      final b64 = await _canal.invokeMethod<String>('pepper', pin);
      return b64 == null ? null : base64.decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Sinais de root. Só serve para AVISAR; não é prova nem bloqueio.
  static Future<bool> pareceRoot() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _canal.invokeMethod<bool>('pareceRoot') ?? false;
    } catch (_) {
      return false;
    }
  }
}
