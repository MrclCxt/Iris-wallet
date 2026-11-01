import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/node_backend.dart';
import 'package:iris_wallet/services/isolate_node_api.dart';
import 'package:iris_wallet/services/node_isolate_protocol.dart';

/// Nó falso que registra o que recebeu e devolve valores conhecidos — assim o
/// teste confere que args e resultados atravessam o protocolo sem perda.
class _NoFalso implements NodeApi {
  Map<String, dynamic>? ultimoArg;
  String? ultimoMetodo;

  @override
  Future<void> start() async => ultimoMetodo = 'start';
  @override
  Future<void> stop() async => ultimoMetodo = 'stop';
  @override
  Future<String> myNodeId() async => '02abc';

  @override
  Future<String> createInvoice(
      {int? amountMsat,
      required String description,
      required int expirySecs}) async {
    ultimoMetodo = 'createInvoice';
    ultimoArg = {
      'amountMsat': amountMsat,
      'description': description,
      'expirySecs': expirySecs
    };
    return 'lntb1invoice';
  }

  @override
  Future<String?> createOffer({required String description}) async => null;

  @override
  Future<List<PaymentRecord>> listPayments() async => [
        PaymentRecord(
          id: 'p1',
          amountSats: 1500,
          isIncoming: true,
          status: 'confirmed',
          date: DateTime.utc(2026, 10, 31, 12, 34, 56),
          isOnchain: true,
        ),
      ];

  @override
  Future<void> payInvoice(String invoice, {int? amountMsat}) async {
    ultimoMetodo = 'payInvoice';
    ultimoArg = {'invoice': invoice, 'amountMsat': amountMsat};
  }

  @override
  Future<NodeBalances> balances() async => const NodeBalances(
      lightningSats: 42, onchainTotalSats: 100, onchainSpendableSats: 90);

  @override
  Future<String> newOnchainAddress() async => 'tb1qaddr';

  @override
  Future<String> sendOnchain(
      {required String address, required int sats}) async {
    ultimoArg = {'address': address, 'sats': sats};
    return 'txid123';
  }

  @override
  Future<({String txid, String txHex, int feeSats})> signOnchain(
      {required String address,
      required int sats,
      double? satPorVbyte,
      bool registrar = true}) async {
    ultimoArg = {
      'address': address,
      'sats': sats,
      'satPorVbyte': satPorVbyte,
      'registrar': registrar
    };
    return (txid: 'tx', txHex: 'deadbeef', feeSats: 7);
  }

  @override
  Future<void> registrarTransacao(String txHex) async =>
      ultimoArg = {'txHex': txHex};

  @override
  Future<String> broadcastTx(String txHex) async {
    ultimoArg = {'txHex': txHex};
    return 'broadcasted';
  }

  @override
  Future<String> criarFaturaComHash(
      {required String hashHex,
      required int amountMsat,
      required String description,
      required int expirySecs}) async {
    ultimoArg = {
      'hashHex': hashHex,
      'amountMsat': amountMsat,
      'description': description,
      'expirySecs': expirySecs
    };
    return 'lntb_hold';
  }

  @override
  Future<void> resgatarTrava(
      {required String hashHex,
      required String segredoHex,
      required int amountMsat}) async {
    ultimoArg = {
      'hashHex': hashHex,
      'segredoHex': segredoHex,
      'amountMsat': amountMsat
    };
  }

  @override
  Future<void> recusarTrava(String hashHex) async =>
      ultimoArg = {'hashHex': hashHex};

  @override
  Future<List<ChannelSummary>> channels() async => const [
        ChannelSummary(
          capacitySats: 100000,
          inboundSats: 40000,
          outboundSats: 60000,
          isUsable: true,
          counterpartyNodeId: '03peer',
          isPublic: true,
          userChannelId: 'uc1',
          forwardingFeeProportionalPpm: 100,
          forwardingFeeBaseMsat: 1000,
        ),
      ];

  @override
  Future<void> openChannel(
      {required String nodeId,
      required String host,
      required int port,
      required int amountSats}) async {
    ultimoArg = {
      'nodeId': nodeId,
      'host': host,
      'port': port,
      'amountSats': amountSats
    };
  }

  @override
  Future<void> updateForwardingFee(
      {required String counterpartyNodeId,
      required String userChannelId,
      required int proportionalPpm,
      required int baseMsat}) async {
    ultimoArg = {
      'counterpartyNodeId': counterpartyNodeId,
      'userChannelId': userChannelId,
      'proportionalPpm': proportionalPpm,
      'baseMsat': baseMsat
    };
  }

  @override
  Future<void> sync() async => ultimoMetodo = 'sync';
  @override
  Future<void> fullScan() async => ultimoMetodo = 'fullScan';

  @override
  Future<NodeEvent?> nextEvent() async => const NodeEvent(
      type: 'payment_claimable',
      paymentHashHex: 'abcd',
      amountMsat: 5000,
      claimDeadline: 120);

  @override
  Future<void> eventHandled() async => ultimoMetodo = 'eventHandled';
}

/// Transporte que exercita o caminho real: codifica o pedido como JSON (mesma
/// restrição de um salto entre isolates), executa o despachante contra o nó
/// falso e devolve a resposta também passada por JSON.
class _TransporteLocal extends NodeTransport {
  _TransporteLocal(this.no);
  final NodeApi no;

  @override
  Future<Map<String, dynamic>> enviar(Map<String, dynamic> req) async {
    final reqJson =
        (jsonDecode(jsonEncode(req)) as Map).cast<String, dynamic>();
    final resp = await executarComandoDoNo(no, reqJson);
    return (jsonDecode(jsonEncode(resp)) as Map).cast<String, dynamic>();
  }
}

void main() {
  late _NoFalso falso;
  late IsolateNodeApi api;

  setUp(() {
    falso = _NoFalso();
    api = IsolateNodeApi(_TransporteLocal(falso));
  });

  test('createInvoice leva args e traz o resultado', () async {
    final inv = await api.createInvoice(
        amountMsat: 2000, description: 'Loja', expirySecs: 3600);
    expect(inv, 'lntb1invoice');
    expect(falso.ultimoArg,
        {'amountMsat': 2000, 'description': 'Loja', 'expirySecs': 3600});
  });

  test('createOffer nulo sobrevive', () async {
    expect(await api.createOffer(description: 'x'), isNull);
  });

  test('listPayments preserva todos os campos (inclusive data)', () async {
    final l = await api.listPayments();
    expect(l, hasLength(1));
    expect(l.first.id, 'p1');
    expect(l.first.amountSats, 1500);
    expect(l.first.isIncoming, true);
    expect(l.first.status, 'confirmed');
    expect(l.first.isOnchain, true);
    expect(l.first.date, DateTime.utc(2026, 10, 31, 12, 34, 56));
  });

  test('balances round-trip', () async {
    final b = await api.balances();
    expect(b.lightningSats, 42);
    expect(b.onchainTotalSats, 100);
    expect(b.onchainSpendableSats, 90);
  });

  test('signOnchain: record ida e volta, com satPorVbyte nulo', () async {
    final r = await api.signOnchain(address: 'tb1q', sats: 1234);
    expect(r.txid, 'tx');
    expect(r.txHex, 'deadbeef');
    expect(r.feeSats, 7);
    expect(falso.ultimoArg, {
      'address': 'tb1q',
      'sats': 1234,
      'satPorVbyte': null,
      'registrar': true
    });
  });

  test('signOnchain com satPorVbyte double', () async {
    await api.signOnchain(
        address: 'a', sats: 1, satPorVbyte: 2.5, registrar: false);
    expect(falso.ultimoArg!['satPorVbyte'], 2.5);
    expect(falso.ultimoArg!['registrar'], false);
  });

  test('channels preserva campos', () async {
    final c = (await api.channels()).first;
    expect(c.capacitySats, 100000);
    expect(c.counterpartyNodeId, '03peer');
    expect(c.isPublic, true);
    expect(c.userChannelId, 'uc1');
    expect(c.forwardingFeeProportionalPpm, 100);
    expect(c.forwardingFeeBaseMsat, 1000);
  });

  test('criarFaturaComHash e resgatarTrava levam args', () async {
    final f = await api.criarFaturaComHash(
        hashHex: 'aa', amountMsat: 500, description: 'd', expirySecs: 60);
    expect(f, 'lntb_hold');
    await api.resgatarTrava(hashHex: 'aa', segredoHex: 'bb', amountMsat: 500);
    expect(falso.ultimoArg,
        {'hashHex': 'aa', 'segredoHex': 'bb', 'amountMsat': 500});
  });

  test('openChannel leva args', () async {
    await api.openChannel(
        nodeId: '03', host: '1.2.3.4', port: 9735, amountSats: 20000);
    expect(falso.ultimoArg,
        {'nodeId': '03', 'host': '1.2.3.4', 'port': 9735, 'amountSats': 20000});
  });

  test('nextEvent preserva tipo e claimDeadline', () async {
    final e = await api.nextEvent();
    expect(e, isNotNull);
    expect(e!.type, 'payment_claimable');
    expect(e.paymentHashHex, 'abcd');
    expect(e.amountMsat, 5000);
    expect(e.claimDeadline, 120);
  });

  test('erro do host vira exceção no cliente', () async {
    // Comando inexistente dispara ArgumentError no despachante, que deve
    // chegar como NodeIsolateException no proxy.
    final t = _TransporteLocal(falso);
    final resp = await t.enviar({'id': 0, 'm': 'nao_existe'});
    expect(resp['ok'], false);
    expect(resp['e'], contains('desconhecido'));
  });

  test('comandos sem retorno (void) completam', () async {
    await api.start();
    await api.sync();
    await api.fullScan();
    await api.eventHandled();
    expect(falso.ultimoMetodo, 'eventHandled');
  });
}
