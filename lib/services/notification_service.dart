import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificações do sistema operacional para recebimentos.
///
/// Diferente do aviso dentro do app (SnackBar), estas aparecem na bandeja do
/// aparelho mesmo com o Iris em segundo plano — que é o ponto: o lojista não
/// fica olhando a tela esperando o pagamento cair.
///
/// Vale para qualquer conta: o nó é do dispositivo, então um recebimento é
/// notificado independentemente de qual perfil está aberto na tela.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _iniciado = false;

  /// Canal único de recebimentos. No Android o usuário pode silenciar só este
  /// canal sem desligar as outras notificações do app.
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

  /// Prepara o plugin e pede permissão. Seguro chamar mais de uma vez.
  /// Nunca lança: notificação é conveniência, não pode derrubar o boot do app.
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

  /// Registra o canal já na abertura do app. Se esperássemos o primeiro
  /// `show()`, o canal não existiria nos ajustes do Android e o usuário não
  /// teria como configurar som/silêncio antes do primeiro pagamento.
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
    // Android 13+ exige permissão explícita; abaixo disso a chamada é nula.
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

  /// Mostra uma notificação de recebimento.
  ///
  /// [id] separa notificações que devem coexistir na bandeja; reusar o mesmo
  /// id substitui a anterior — é o que faz a confirmação atualizar o aviso de
  /// "aguardando confirmação" em vez de empilhar um segundo.
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
