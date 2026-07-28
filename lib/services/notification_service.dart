import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _iniciado = false;

  static const AndroidNotificationDetails _androidRecebimento =
      AndroidNotificationDetails(
    'iris_recebimentos',
    'Recebimentos',
    channelDescription: 'Avisa quando um pagamento chega na sua carteira',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  static const DarwinNotificationDetails _appleRecebimento =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  static Future<void> init() async {
    if (_iniciado) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
        windows: WindowsInitializationSettings(
          appName: 'Iris Wallet',
          appUserModelId: 'app.iriswallet',
          guid: '6d5f7c1e-4a2b-4f8c-9c3d-1e7b8a2f4c60',
        ),
      );
      await _plugin.initialize(settings);
      await _criarCanalAndroid();
      await _pedirPermissao();
      _iniciado = true;
    } catch (e) {
      debugPrint('Notificações indisponíveis: $e');
    }
  }

  static Future<void> _criarCanalAndroid() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'iris_recebimentos',
      'Recebimentos',
      description: 'Avisa quando um pagamento chega na sua carteira',
      importance: Importance.high,
    ));
  }

  static Future<void> _pedirPermissao() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macos?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> mostrarRecebimento({
    required int id,
    required String titulo,
    required String corpo,
  }) async {
    if (!_iniciado) await init();
    if (!_iniciado) return;
    try {
      await _plugin.show(
        id,
        titulo,
        corpo,
        const NotificationDetails(
          android: _androidRecebimento,
          iOS: _appleRecebimento,
          macOS: _appleRecebimento,
        ),
      );
    } catch (e) {
      debugPrint('Falha ao notificar recebimento: $e');
    }
  }
}
