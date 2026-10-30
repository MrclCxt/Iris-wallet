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
