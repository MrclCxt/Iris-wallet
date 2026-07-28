import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Ponte para o serviço em primeiro plano do Android (`IrisForegroundService`,
/// nativo/Kotlin). Ele não roda nenhum código Dart próprio — só impede o
/// Android de suspender/matar o processo quando o app é minimizado, para que
/// o nó Lightning já embarcado continue rodando (sincronizando, recebendo
/// pagamentos) em segundo plano. Não sobrevive a fechar o app dos recentes.
///
/// Sem efeito em outras plataformas (Android é o único SO móvel onde esse
/// mecanismo existe — iOS não permite; ver [[node-reliability-routing]]).
class BackgroundServiceAndroid {
  static const _channel = MethodChannel('app.iriswallet/device');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<void> start() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('startBackgroundService');
    } catch (_) {
      // Melhor esforço: se falhar, o nó continua funcionando normalmente
      // enquanto o app estiver em primeiro plano — só perde a garantia extra.
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stopBackgroundService');
    } catch (_) {}
  }

  static Future<bool> isRunning() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isBackgroundServiceRunning') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
