// Protocolo de IPC do nó Lightning entre a isolate da UI e a isolate de fundo
// (fase 1 da re-arquitetura: o nó passa a viver fora da engine da UI para
// sobreviver ao app ser fechado). Aqui mora SÓ a tradução de cada chamada do
// `NodeApi` para mapas serializáveis que atravessam isolates, e o despachante
// que executa o comando contra um `NodeApi` de verdade no outro lado.
//
// É puro Dart, sem plataforma: o mesmo protocolo serve seja qual for o
// mecanismo que hospeda o nó em segundo plano (foreground service, serviço
// nativo via canal, etc.). O encanamento de plataforma é a fase 2.

import 'node_backend.dart';

// ------------------------------------------------------------- codecs de tipo

Map<String, dynamic> pagamentoParaMapa(PaymentRecord p) => {
      'id': p.id,
      'amountSats': p.amountSats,
      'isIncoming': p.isIncoming,
      'status': p.status,
      'date': p.date.toIso8601String(),
      'isOnchain': p.isOnchain,
    };

PaymentRecord pagamentoDeMapa(Map<String, dynamic> m) => PaymentRecord(
      id: m['id'] as String,
      amountSats: m['amountSats'] as int,
      isIncoming: m['isIncoming'] as bool,
      status: m['status'] as String,
      date: DateTime.parse(m['date'] as String),
      isOnchain: (m['isOnchain'] as bool?) ?? false,
    );

Map<String, dynamic> saldosParaMapa(NodeBalances b) => {
      'lightningSats': b.lightningSats,
      'onchainTotalSats': b.onchainTotalSats,
      'onchainSpendableSats': b.onchainSpendableSats,
    };

NodeBalances saldosDeMapa(Map<String, dynamic> m) => NodeBalances(
      lightningSats: (m['lightningSats'] as int?) ?? 0,
      onchainTotalSats: (m['onchainTotalSats'] as int?) ?? 0,
      onchainSpendableSats: (m['onchainSpendableSats'] as int?) ?? 0,
    );

Map<String, dynamic> canalParaMapa(ChannelSummary c) => {
      'capacitySats': c.capacitySats,
      'inboundSats': c.inboundSats,
      'outboundSats': c.outboundSats,
      'isUsable': c.isUsable,
      'counterpartyNodeId': c.counterpartyNodeId,
      'isPublic': c.isPublic,
      'userChannelId': c.userChannelId,
      'forwardingFeeProportionalPpm': c.forwardingFeeProportionalPpm,
      'forwardingFeeBaseMsat': c.forwardingFeeBaseMsat,
    };

ChannelSummary canalDeMapa(Map<String, dynamic> m) => ChannelSummary(
      capacitySats: m['capacitySats'] as int,
      inboundSats: m['inboundSats'] as int,
      outboundSats: m['outboundSats'] as int,
      isUsable: m['isUsable'] as bool,
      counterpartyNodeId: m['counterpartyNodeId'] as String,
      isPublic: (m['isPublic'] as bool?) ?? false,
      userChannelId: (m['userChannelId'] as String?) ?? '',
      forwardingFeeProportionalPpm:
          (m['forwardingFeeProportionalPpm'] as int?) ?? 0,
      forwardingFeeBaseMsat: (m['forwardingFeeBaseMsat'] as int?) ?? 0,
    );

Map<String, dynamic> eventoParaMapa(NodeEvent e) => {
      'type': e.type,
      'paymentHashHex': e.paymentHashHex,
      'amountMsat': e.amountMsat,
      'claimDeadline': e.claimDeadline,
    };

NodeEvent eventoDeMapa(Map<String, dynamic> m) => NodeEvent(
      type: m['type'] as String,
      paymentHashHex: (m['paymentHashHex'] as String?) ?? '',
      amountMsat: (m['amountMsat'] as int?) ?? 0,
      claimDeadline: m['claimDeadline'] as int?,
    );

// --------------------------------------------------------------- despachante
//
// Executa UM comando contra o `NodeApi` real e devolve o resultado já
// codificado (primitivo, mapa, lista de mapas ou null). Roda no lado que tem
// o nó (host). Qualquer exceção é capturada por `executarComandoDoNo`.

Future<Object?> _chamar(
    NodeApi no, String metodo, Map<String, dynamic> a) async {
  switch (metodo) {
    case 'start':
      await no.start();
      return null;
    case 'stop':
      await no.stop();
      return null;
    case 'myNodeId':
      return no.myNodeId();
    case 'createInvoice':
      return no.createInvoice(
        amountMsat: a['amountMsat'] as int?,
        description: a['description'] as String,
        expirySecs: a['expirySecs'] as int,
      );
    case 'createOffer':
      return no.createOffer(description: a['description'] as String);
    case 'listPayments':
      final lista = await no.listPayments();
      return lista.map(pagamentoParaMapa).toList();
    case 'payInvoice':
      await no.payInvoice(a['invoice'] as String,
          amountMsat: a['amountMsat'] as int?);
      return null;
    case 'balances':
      return saldosParaMapa(await no.balances());
    case 'newOnchainAddress':
      return no.newOnchainAddress();
    case 'sendOnchain':
      return no.sendOnchain(
          address: a['address'] as String, sats: a['sats'] as int);
    case 'signOnchain':
      final r = await no.signOnchain(
        address: a['address'] as String,
        sats: a['sats'] as int,
        satPorVbyte: (a['satPorVbyte'] as num?)?.toDouble(),
        registrar: (a['registrar'] as bool?) ?? true,
      );
      return {'txid': r.txid, 'txHex': r.txHex, 'feeSats': r.feeSats};
    case 'registrarTransacao':
      await no.registrarTransacao(a['txHex'] as String);
      return null;
    case 'broadcastTx':
      return no.broadcastTx(a['txHex'] as String);
    case 'criarFaturaComHash':
      return no.criarFaturaComHash(
        hashHex: a['hashHex'] as String,
        amountMsat: a['amountMsat'] as int,
        description: a['description'] as String,
        expirySecs: a['expirySecs'] as int,
      );
    case 'resgatarTrava':
      await no.resgatarTrava(
        hashHex: a['hashHex'] as String,
        segredoHex: a['segredoHex'] as String,
        amountMsat: a['amountMsat'] as int,
      );
      return null;
    case 'recusarTrava':
      await no.recusarTrava(a['hashHex'] as String);
      return null;
    case 'channels':
      final lista = await no.channels();
      return lista.map(canalParaMapa).toList();
    case 'openChannel':
      await no.openChannel(
        nodeId: a['nodeId'] as String,
        host: a['host'] as String,
        port: a['port'] as int,
        amountSats: a['amountSats'] as int,
      );
      return null;
    case 'closeChannel':
      await no.closeChannel(
        userChannelId: a['userChannelId'] as String,
        counterpartyNodeId: a['counterpartyNodeId'] as String,
        force: a['force'] as bool? ?? false,
      );
      return null;
    case 'updateForwardingFee':
      await no.updateForwardingFee(
        counterpartyNodeId: a['counterpartyNodeId'] as String,
        userChannelId: a['userChannelId'] as String,
        proportionalPpm: a['proportionalPpm'] as int,
        baseMsat: a['baseMsat'] as int,
      );
      return null;
    case 'sync':
      await no.sync();
      return null;
    case 'fullScan':
      await no.fullScan();
      return null;
    case 'nextEvent':
      final e = await no.nextEvent();
      return e == null ? null : eventoParaMapa(e);
    case 'eventHandled':
      await no.eventHandled();
      return null;
    default:
      throw ArgumentError('Comando de nó desconhecido: $metodo');
  }
}

/// Executa `req` ({'id', 'm', 'a'}) contra [no] e devolve a resposta
/// serializável ({'id', 'ok', 'r'|'e'}). Nunca lança: erros viram {'ok': false}.
Future<Map<String, dynamic>> executarComandoDoNo(
    NodeApi no, Map<String, dynamic> req) async {
  final id = req['id'];
  try {
    final a = (req['a'] as Map?)?.cast<String, dynamic>() ?? const {};
    final r = await _chamar(no, req['m'] as String, a);
    return {'id': id, 'ok': true, 'r': r};
  } catch (e) {
    return {'id': id, 'ok': false, 'e': e.toString()};
  }
}
