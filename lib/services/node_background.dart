import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'node_backend.dart';
import 'node_isolate_protocol.dart';
import 'notification_service.dart';

/// Entrypoint da isolate de fundo que hospeda o nó Lightning (fase 2 da
/// re-arquitetura). Roda dentro do foreground service do flutter_background_
/// service — uma ENGINE separada da UI, que sobrevive ao app ser fechado.
/// Aqui o nó nasce e vive; a UI fala com ele por IPC (ver IsolateNodeApi +
/// TransporteServicoDeFundo).
///
/// Precisa ser top-level e marcado como entry-point para a VM não eliminá-lo
/// no build release (tree-shaking).
@pragma('vm:entry-point')
Future<void> onStartNoDeFundo(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registra os plugins (path_provider, flutter_local_notifications, ldk_node)
  // nesta isolate — sem isto nada de plataforma funciona aqui.
  DartPluginRegistrant.ensureInitialized();

  EmbeddedNodeApi? no;
  var appEmPrimeiroPlano = true;
  var drenando = false;
  var iniciando = false;

  Future<void> notificar(String texto) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Iris — carteira ativa',
        content: texto,
      );
    }
  }

  // A UI avisa quando está (ou não) em primeiro plano. Com o app fechado ou
  // minimizado, a notificação de "venda recebida" sai DAQUI; com o app aberto,
  // quem notifica é a própria UI (evita notificação dupla).
  service.on('app_fg').listen((d) {
    appEmPrimeiroPlano = (d?['fg'] as bool?) ?? true;
  });

  void iniciarDreno() {
    if (drenando) return;
    drenando = true;
    () async {
      var idNotif = 7000;
      while (drenando && no != null) {
        try {
          final e = await no!.nextEvent();
          if (e == null) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          // Repassa o evento para a UI fazer a contabilidade (histórico cifrado,
          // atualização de saldo). Se a UI estiver morta, o pagamento já foi
          // reivindicado pelo ldk-node antes deste evento existir — a UI
          // reconcilia ao reabrir via listPayments.
          service.invoke('evento', eventoParaMapa(e));
          if (e.type == 'payment_received' && !appEmPrimeiroPlano) {
            final sats = e.amountMsat ~/ 1000;
            await NotificationService.mostrarRecebimento(
              id: idNotif++,
              titulo: 'Pagamento recebido',
              corpo: '+$sats sats',
            );
          }
          // Avança a fila de eventos do nó (mantém o nó saudável mesmo sem UI).
          await no!.eventHandled();
        } catch (_) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }();
  }

  service.on('boot').listen((d) async {
    if (no != null) {
      service.invoke('booted', {'ok': true});
      return;
    }
    // Reenvios de boot (a UI reenvia caso a escuta não estivesse pronta) não
    // podem disparar starts concorrentes no mesmo armazenamento.
    if (iniciando) return;
    iniciando = true;
    try {
      final novo = EmbeddedNodeApi(
        mnemonic: d!['mnemonic'] as String,
        storagePath: d['storagePath'] as String,
        listeningPort: (d['listeningPort'] as int?) ?? 9735,
        esploraUrl: (d['esploraUrl'] as String?) ?? '',
      );
      await novo.start();
      no = novo;
      await notificar('Nó Lightning em segundo plano');
      iniciarDreno();
      // Com o app aberto é a UI que dirige o sync (via IPC); com o app fechado
      // a UI morre, então o próprio host sincroniza de tempos em tempos para o
      // nó não ficar defasado. Só quando fora do primeiro plano, para não
      // duplicar o sync da UI.
      Timer.periodic(const Duration(seconds: 90), (t) async {
        final n = no;
        if (n == null) {
          t.cancel();
          return;
        }
        if (appEmPrimeiroPlano) return;
        try {
          await n.sync();
        } catch (_) {}
      });
      service.invoke('booted', {'ok': true});
    } catch (e) {
      service.invoke('booted', {'ok': false, 'e': e.toString()});
    } finally {
      iniciando = false;
    }
  });

  service.on('cmd').listen((d) async {
    final n = no;
    if (d == null) return;
    if (n == null) {
      service.invoke(
          'resp', {'id': d['id'], 'ok': false, 'e': 'nó ainda não iniciado'});
      return;
    }
    final resp = await executarComandoDoNo(n, d.cast<String, dynamic>());
    service.invoke('resp', resp);
  });

  service.on('parar').listen((d) async {
    drenando = false;
    try {
      await no?.stop();
    } catch (_) {}
    no = null;
    await service.stopSelf();
  });
}
