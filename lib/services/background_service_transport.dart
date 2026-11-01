import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'isolate_node_api.dart';
import 'node_backend.dart';
import 'node_background.dart';
import 'node_isolate_protocol.dart';

/// Lado da UI da fase 2: controla o foreground service que hospeda o nó numa
/// isolate própria e faz a ponte de IPC. Um nó por aparelho (consumer OU
/// merchant ativo), então um único serviço basta.
class ServicoNoDeFundo {
  ServicoNoDeFundo._();
  static final ServicoNoDeFundo instancia = ServicoNoDeFundo._();

  final FlutterBackgroundService _servico = FlutterBackgroundService();
  bool _configurado = false;
  bool _escutando = false;

  // Id global do comando: duas instâncias de IsolateNodeApi (consumer/merchant)
  // não podem colidir, então quem numera é aqui, não o proxy.
  int _idGlobal = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendentes = {};
  final StreamController<NodeEvent> _eventosCtrl =
      StreamController<NodeEvent>.broadcast();

  /// Eventos do nó repassados pela isolate de fundo (payment_received etc.).
  Stream<NodeEvent> get eventos => _eventosCtrl.stream;

  Future<void> configurar() async {
    if (_configurado) return;
    // O canal PRECISA existir antes de o serviço ir a primeiro plano, senão o
    // Android recusa a notificação e derruba o processo
    // (CannotPostForegroundServiceNotificationException). Importância baixa:
    // notificação discreta, sem som, só para manter o serviço vivo.
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'iris_no_fundo',
      'Carteira ativa',
      description: 'Mantém o nó Lightning rodando em segundo plano',
      importance: Importance.low,
    ));
    await _servico.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStartNoDeFundo,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: 'iris_no_fundo',
        initialNotificationTitle: 'Iris — carteira ativa',
        initialNotificationContent: 'Iniciando nó Lightning…',
        foregroundServiceTypes: const [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
    _configurado = true;
  }

  void _garantirEscutas() {
    if (_escutando) return;
    _escutando = true;
    _servico.on('resp').listen((d) {
      if (d == null) return;
      final id = d['id'] as int?;
      final c = id == null ? null : _pendentes.remove(id);
      if (c != null && !c.isCompleted) c.complete(d.cast<String, dynamic>());
    });
    _servico.on('evento').listen((d) {
      if (d != null) {
        _eventosCtrl.add(eventoDeMapa(d.cast<String, dynamic>()));
      }
    });
  }

  /// Sobe o serviço (se preciso) e manda a isolate de fundo construir e iniciar
  /// o nó. Reenvia o `boot` algumas vezes porque a escuta na isolate pode não
  /// estar pronta no instante do start.
  Future<void> iniciarComNo({
    required String mnemonic,
    required String storagePath,
    required int listeningPort,
    String esploraUrl = '',
  }) async {
    await configurar();
    _garantirEscutas();
    if (!await _servico.isRunning()) {
      await _servico.startService();
    }

    final pronto = Completer<Map<String, dynamic>>();
    late StreamSubscription sub;
    sub = _servico.on('booted').listen((d) {
      if (!pronto.isCompleted) pronto.complete((d ?? const {}).cast());
    });

    void mandarBoot() => _servico.invoke('boot', {
          'mnemonic': mnemonic,
          'storagePath': storagePath,
          'listeningPort': listeningPort,
          'esploraUrl': esploraUrl,
        });

    try {
      for (var tentativa = 0; tentativa < 6; tentativa++) {
        mandarBoot();
        final r = await pronto.future
            .timeout(const Duration(seconds: 15))
            .catchError((_) => <String, dynamic>{'_timeout': true});
        if (r['_timeout'] != true) {
          if (r['ok'] == true) return;
          throw Exception(r['e'] ?? 'falha ao iniciar o nó de fundo');
        }
      }
      throw Exception('o nó de fundo não respondeu ao iniciar');
    } finally {
      await sub.cancel();
    }
  }

  /// Avisa a isolate de fundo se o app está em primeiro plano (decide de onde
  /// sai a notificação de recebimento).
  void informarPrimeiroPlano(bool emPrimeiroPlano) {
    if (_configurado) _servico.invoke('app_fg', {'fg': emPrimeiroPlano});
  }

  Future<void> parar() async {
    _servico.invoke('parar');
    for (final c in _pendentes.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('serviço de fundo parado'));
      }
    }
    _pendentes.clear();
  }

  Future<bool> estaRodando() => _servico.isRunning();

  /// Envia um comando ao nó e espera a resposta correlacionada por id.
  Future<Map<String, dynamic>> enviarComando(Map<String, dynamic> req) {
    _garantirEscutas();
    final id = _idGlobal++;
    req['id'] = id;
    final c = Completer<Map<String, dynamic>>();
    _pendentes[id] = c;
    _servico.invoke('cmd', req);
    return c.future.timeout(const Duration(seconds: 120), onTimeout: () {
      _pendentes.remove(id);
      debugPrint('Comando ${req['m']} do nó de fundo expirou.');
      return {'id': id, 'ok': false, 'e': 'tempo esgotado em ${req['m']}'};
    });
  }
}

/// Transporte do IsolateNodeApi sobre o serviço de fundo.
class TransporteServicoDeFundo extends NodeTransport {
  TransporteServicoDeFundo(this._svc);
  final ServicoNoDeFundo _svc;

  @override
  Future<Map<String, dynamic>> enviar(Map<String, dynamic> req) =>
      _svc.enviarComando(req);
}

/// Monta um NodeApi que roda o nó na isolate de fundo.
NodeApi criarNoDeFundo() =>
    IsolateNodeApi(TransporteServicoDeFundo(ServicoNoDeFundo.instancia));
