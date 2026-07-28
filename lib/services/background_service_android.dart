import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class BackgroundServiceAndroid {
  static const _channel = MethodChannel('app.iriswallet/device');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<void> start() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('startBackgroundService');
    } catch (_) {}
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
