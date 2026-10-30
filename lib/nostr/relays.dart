import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'evento.dart';

/// Conjunto de relays Nostr. Nenhum relay é necessário sozinho: a mesma
/// consulta vai a todos, o resultado é a união (sem repetir id), e evento com
/// assinatura inválida é descartado — um relay não consegue forjar ordens.
class RelaysNostr {
  static const List<String> padrao = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://relay.nostr.band',
  ];

  static const String _chave = 'nostr_relays_proprios';

  static Future<List<String>> proprios() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_chave) ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> salvarProprios(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _chave, urls.map((u) => u.trim()).where((u) => u.isNotEmpty).toSet().toList());
  }

  static Future<List<String>> emUso() async =>
      <String>{...await proprios(), ...padrao}.toList();

  /// Busca eventos que casam com [filtro] (NIP-01) em todos os relays e
  /// devolve quando cada um mandar EOSE ou o tempo acabar.
  static Future<List<EventoNostr>> buscar(
    Map<String, dynamic> filtro, {
    List<String>? relays,
    Duration tempo = const Duration(seconds: 8),
  }) async {
    final lista = relays ?? await emUso();
    final vistos = <String, EventoNostr>{};
    await Future.wait(lista.map((url) => _buscarEm(url, filtro, tempo, vistos)));
    final out = vistos.values.toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return out;
  }

  static Future<void> _buscarEm(String url, Map<String, dynamic> filtro,
      Duration tempo, Map<String, EventoNostr> vistos) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(url).timeout(const Duration(seconds: 6));
      final sub = 'iris${DateTime.now().microsecondsSinceEpoch}';
      ws.add(jsonEncode(['REQ', sub, filtro]));
      final fim = Completer<void>();
      ws.listen((bruto) {
        try {
          final m = jsonDecode(bruto as String) as List;
          if (m[0] == 'EVENT' && m[1] == sub) {
            final e = EventoNostr.fromJson(m[2] as Map<String, dynamic>);
            if (e.valido) vistos[e.id] = e;
          } else if ((m[0] == 'EOSE' || m[0] == 'CLOSED') && m[1] == sub) {
            if (!fim.isCompleted) fim.complete();
          }
        } catch (_) {}
      }, onDone: () {
        if (!fim.isCompleted) fim.complete();
      }, onError: (_) {
        if (!fim.isCompleted) fim.complete();
      });
      await fim.future.timeout(tempo, onTimeout: () {});
      ws.add(jsonEncode(['CLOSE', sub]));
    } catch (e) {
      debugPrint('Relay $url indisponível: $e');
    } finally {
      await ws?.close();
    }
  }

  /// Publica [evento] em todos os relays; devolve quantos aceitaram (OK true).
  static Future<int> publicar(EventoNostr evento,
      {List<String>? relays}) async {
    final lista = relays ?? await emUso();
    final aceitos = await Future.wait(lista.map((url) async {
      WebSocket? ws;
      try {
        ws = await WebSocket.connect(url).timeout(const Duration(seconds: 6));
        final ok = Completer<bool>();
        ws.listen((bruto) {
          try {
            final m = jsonDecode(bruto as String) as List;
            if (m[0] == 'OK' && m[1] == evento.id && !ok.isCompleted) {
              ok.complete(m[2] == true);
            }
          } catch (_) {}
        }, onDone: () {
          if (!ok.isCompleted) ok.complete(false);
        }, onError: (_) {
          if (!ok.isCompleted) ok.complete(false);
        });
        ws.add(jsonEncode(['EVENT', evento.toJson()]));
        return await ok.future
            .timeout(const Duration(seconds: 8), onTimeout: () => false);
      } catch (_) {
        return false;
      } finally {
        await ws?.close();
      }
    }));
    return aceitos.where((a) => a).length;
  }
}
