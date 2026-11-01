// Proxy do nó para o lado da UI (fase 1 da re-arquitetura). Implementa a MESMA
// interface `NodeApi` que o `wallet_service` já usa, mas em vez de rodar o nó
// na engine da UI, repassa cada chamada por IPC para a isolate de fundo que
// hospeda o nó de verdade. Assim o `wallet_service` troca o backend sem saber
// de isolates — a costura é a própria interface `NodeApi`.
//
// O transporte (como os mapas atravessam) é abstrato de propósito: a fase 2
// liga isto ao foreground service (flutter_background_service ou serviço
// nativo) implementando `NodeTransport`. Este arquivo não depende de nenhum
// mecanismo de plataforma e é testável sozinho.

import 'node_backend.dart';
import 'node_isolate_protocol.dart';

/// Canal por onde um comando codificado vai e volta. Uma implementação concreta
/// (fase 2) manda o mapa para a isolate de fundo e devolve a resposta dela.
abstract class NodeTransport {
  /// Envia `req` ({'id', 'm', 'a'}) e completa com a resposta
  /// ({'id', 'ok', 'r'|'e'}). Deve preservar os tipos (int/bool/String/null,
  /// mapas e listas) — é o que os codecs do protocolo esperam.
  Future<Map<String, dynamic>> enviar(Map<String, dynamic> req);

  /// Libera o canal (fecha portas, cancela escutas). Opcional.
  Future<void> encerrar() async {}
}

class IsolateNodeApi implements NodeApi {
  IsolateNodeApi(this._transporte);

  final NodeTransport _transporte;
  int _proximoId = 0;

  Future<Object?> _cmd(String metodo, [Map<String, dynamic>? args]) async {
    final req = <String, dynamic>{
      'id': _proximoId++,
      'm': metodo,
      if (args != null) 'a': args,
    };
    final resp = await _transporte.enviar(req);
    if (resp['ok'] == true) return resp['r'];
    throw NodeIsolateException((resp['e'] as String?) ?? 'erro desconhecido');
  }

  @override
  Future<void> start() async => _cmd('start');

  @override
  Future<void> stop() async => _cmd('stop');

  @override
  Future<String> myNodeId() async => await _cmd('myNodeId') as String;

  @override
  Future<String> createInvoice(
          {int? amountMsat,
          required String description,
          required int expirySecs}) async =>
      await _cmd('createInvoice', {
        'amountMsat': amountMsat,
        'description': description,
        'expirySecs': expirySecs,
      }) as String;

  @override
  Future<String?> createOffer({required String description}) async =>
      await _cmd('createOffer', {'description': description}) as String?;

  @override
  Future<List<PaymentRecord>> listPayments() async {
    final r = await _cmd('listPayments') as List;
    return r
        .map((e) => pagamentoDeMapa((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> payInvoice(String invoice, {int? amountMsat}) async =>
      _cmd('payInvoice', {'invoice': invoice, 'amountMsat': amountMsat});

  @override
  Future<NodeBalances> balances() async =>
      saldosDeMapa((await _cmd('balances') as Map).cast<String, dynamic>());

  @override
  Future<String> newOnchainAddress() async =>
      await _cmd('newOnchainAddress') as String;

  @override
  Future<String> sendOnchain(
          {required String address, required int sats}) async =>
      await _cmd('sendOnchain', {'address': address, 'sats': sats}) as String;

  @override
  Future<({String txid, String txHex, int feeSats})> signOnchain(
      {required String address,
      required int sats,
      double? satPorVbyte,
      bool registrar = true}) async {
    final m = (await _cmd('signOnchain', {
      'address': address,
      'sats': sats,
      'satPorVbyte': satPorVbyte,
      'registrar': registrar,
    }) as Map)
        .cast<String, dynamic>();
    return (
      txid: m['txid'] as String,
      txHex: m['txHex'] as String,
      feeSats: m['feeSats'] as int,
    );
  }

  @override
  Future<void> registrarTransacao(String txHex) async =>
      _cmd('registrarTransacao', {'txHex': txHex});

  @override
  Future<String> broadcastTx(String txHex) async =>
      await _cmd('broadcastTx', {'txHex': txHex}) as String;

  @override
  Future<String> criarFaturaComHash(
          {required String hashHex,
          required int amountMsat,
          required String description,
          required int expirySecs}) async =>
      await _cmd('criarFaturaComHash', {
        'hashHex': hashHex,
        'amountMsat': amountMsat,
        'description': description,
        'expirySecs': expirySecs,
      }) as String;

  @override
  Future<void> resgatarTrava(
          {required String hashHex,
          required String segredoHex,
          required int amountMsat}) async =>
      _cmd('resgatarTrava', {
        'hashHex': hashHex,
        'segredoHex': segredoHex,
        'amountMsat': amountMsat,
      });

  @override
  Future<void> recusarTrava(String hashHex) async =>
      _cmd('recusarTrava', {'hashHex': hashHex});

  @override
  Future<List<ChannelSummary>> channels() async {
    final r = await _cmd('channels') as List;
    return r
        .map((e) => canalDeMapa((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> openChannel(
          {required String nodeId,
          required String host,
          required int port,
          required int amountSats}) async =>
      _cmd('openChannel', {
        'nodeId': nodeId,
        'host': host,
        'port': port,
        'amountSats': amountSats,
      });

  @override
  Future<void> closeChannel(
          {required String userChannelId,
          required String counterpartyNodeId,
          bool force = false}) async =>
      _cmd('closeChannel', {
        'userChannelId': userChannelId,
        'counterpartyNodeId': counterpartyNodeId,
        'force': force,
      });

  @override
  Future<void> updateForwardingFee(
          {required String counterpartyNodeId,
          required String userChannelId,
          required int proportionalPpm,
          required int baseMsat}) async =>
      _cmd('updateForwardingFee', {
        'counterpartyNodeId': counterpartyNodeId,
        'userChannelId': userChannelId,
        'proportionalPpm': proportionalPpm,
        'baseMsat': baseMsat,
      });

  @override
  Future<void> sync() async => _cmd('sync');

  @override
  Future<void> fullScan() async => _cmd('fullScan');

  @override
  Future<NodeEvent?> nextEvent() async {
    final r = await _cmd('nextEvent');
    return r == null ? null : eventoDeMapa((r as Map).cast<String, dynamic>());
  }

  @override
  Future<void> eventHandled() async => _cmd('eventHandled');
}

class NodeIsolateException implements Exception {
  final String message;
  NodeIsolateException(this.message);
  @override
  String toString() => 'NodeIsolateException: $message';
}
