import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:ldk_node/ldk_node.dart' as ldk;

/// Abstração do backend do nó Lightning (arquitetura híbrida A+B):
///
/// - [EmbeddedNodeApi]: nó LDK embarcado no app via FFI (Rust compilado
///   localmente para Android/iOS/Windows/Linux/macOS). Padrão.
/// - [RemoteNodeApi]: cliente REST de um daemon local (`iris-noded`) rodando
///   em 127.0.0.1 — útil para PDV/desktop que fica ligado como serviço.
///
/// Nos dois modos o nó é do usuário e roda no dispositivo do usuário:
/// nenhuma chave ou dado sai da máquina.

class NodeBalances {
  final int lightningSats;
  final int onchainTotalSats;
  final int onchainSpendableSats;
  const NodeBalances({
    this.lightningSats = 0,
    this.onchainTotalSats = 0,
    this.onchainSpendableSats = 0,
  });
}

class ChannelSummary {
  final int capacitySats;
  final int inboundSats;
  final int outboundSats;
  final bool isUsable;
  final String counterpartyNodeId;
  const ChannelSummary({
    required this.capacitySats,
    required this.inboundSats,
    required this.outboundSats,
    required this.isUsable,
    required this.counterpartyNodeId,
  });
}

/// Evento do nó já normalizado entre os dois backends.
class NodeEvent {
  final String type; // payment_received | payment_successful | payment_failed | other
  final String paymentHashHex;
  final int amountMsat;
  const NodeEvent({required this.type, this.paymentHashHex = '', this.amountMsat = 0});
}

abstract class NodeApi {
  Future<void> start();
  Future<void> stop();
  Future<String> createInvoice({int? amountMsat, required String description, required int expirySecs});
  Future<void> payInvoice(String invoice, {int? amountMsat});
  Future<NodeBalances> balances();
  Future<String> newOnchainAddress();

  /// Envio puro pela rede Bitcoin (on-chain) — trilho para grandes valores.
  /// Retorna o txid.
  Future<String> sendOnchain({required String address, required int sats});
  Future<List<ChannelSummary>> channels();
  Future<void> openChannel({
    required String nodeId,
    required String host,
    required int port,
    required int amountSats,
  });
  Future<void> sync();
  Future<NodeEvent?> nextEvent();
  Future<void> eventHandled();
}

// ---------------------------------------------------------------------------
// Implementação embarcada (FFI / ldk_node) — nó dentro do próprio app
// ---------------------------------------------------------------------------

class EmbeddedNodeApi implements NodeApi {
  final String mnemonic;
  final String storagePath;
  final String esploraUrl;

  /// Porta P2P deste nó. Os perfis pessoal e lojista rodam no MESMO processo,
  /// então cada um precisa da sua porta — o padrão do ldk_node é 9735 para
  /// todos, o que fazia o segundo nó falhar ao subir (endereço em uso).
  final int listeningPort;

  ldk.Node? _node;

  EmbeddedNodeApi({
    required this.mnemonic,
    required this.storagePath,
    this.listeningPort = 9735,
    // Vazio = escolhe automaticamente entre os candidatos no start.
    this.esploraUrl = '',
  });

  /// Backends Esplora, em ordem de preferência.
  ///
  /// Os dois já falharam em momentos diferentes: o blockstream chegou a
  /// devolver HTTP 429 para uso não autenticado, e o mempool.space passou a
  /// responder 203 em ~15s (o que estoura o timeout de fee do LDK e derruba o
  /// start do nó). Fixar um só significa trocar de backend a cada incidente —
  /// por isso o nó testa e usa o que estiver de pé.
  static const List<String> esploraCandidatos = [
    'https://blockstream.info/testnet/api',
    'https://mempool.space/testnet/api',
  ];

  /// Devolve o primeiro backend que responder 200 rápido. Se nenhum responder,
  /// devolve o primeiro da lista para o LDK tentar mesmo assim e reportar o
  /// erro real, em vez de a gente inventar um.
  static Future<String> escolherEsplora() async {
    for (final base in esploraCandidatos) {
      try {
        final r = await http
            .get(Uri.parse('$base/blocks/tip/height'))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) {
          debugPrint('Esplora escolhido: $base');
          return base;
        }
        debugPrint('Esplora $base respondeu HTTP ${r.statusCode}; tentando outro.');
      } catch (e) {
        debugPrint('Esplora $base indisponível ($e); tentando outro.');
      }
    }
    debugPrint('Nenhum Esplora respondeu; usando ${esploraCandidatos.first}.');
    return esploraCandidatos.first;
  }

  @override
  Future<void> start() async {
    final esplora =
        esploraUrl.isNotEmpty ? esploraUrl : await escolherEsplora();
    final builder = ldk.Builder()
      ..setEntropyBip39Mnemonic(mnemonic: ldk.Mnemonic(seedPhrase: mnemonic))
      ..setNetwork(ldk.Network.testnet)
      ..setStorageDirPath(storagePath)
      ..setListeningAddresses(
          [ldk.SocketAddress.hostname(addr: '0.0.0.0', port: listeningPort)])
      ..setEsploraServer(esplora);
    _node = await builder.build();
    await _node!.start();
  }

  @override
  Future<void> stop() async {
    try {
      await _node?.stop();
    } catch (_) {}
    _node = null;
  }

  ldk.Node get _n {
    final n = _node;
    if (n == null) throw Exception('Nó não iniciado');
    return n;
  }

  @override
  Future<String> createInvoice({int? amountMsat, required String description, required int expirySecs}) async {
    final bolt11 = await _n.bolt11Payment();
    if (amountMsat == null) {
      final inv = await bolt11.receiveVariableAmount(
        expirySecs: expirySecs,
        description: description,
      );
      return inv.signedRawInvoice;
    }
    final inv = await bolt11.receive(
      amountMsat: BigInt.from(amountMsat),
      description: description,
      expirySecs: expirySecs,
    );
    return inv.signedRawInvoice;
  }

  @override
  Future<void> payInvoice(String invoice, {int? amountMsat}) async {
    final bolt11 = await _n.bolt11Payment();
    final inv = ldk.Bolt11Invoice(signedRawInvoice: invoice.trim());
    if (amountMsat != null) {
      await bolt11.sendUsingAmount(invoice: inv, amountMsat: BigInt.from(amountMsat));
    } else {
      await bolt11.send(invoice: inv);
    }
  }

  @override
  Future<NodeBalances> balances() async {
    final b = await _n.listBalances();
    return NodeBalances(
      lightningSats: b.totalLightningBalanceSats.toInt(),
      onchainTotalSats: b.totalOnchainBalanceSats.toInt(),
      onchainSpendableSats: b.spendableOnchainBalanceSats.toInt(),
    );
  }

  @override
  Future<String> newOnchainAddress() async {
    final onChain = await _n.onChainPayment();
    final address = await onChain.newAddress();
    return address.s;
  }

  @override
  Future<String> sendOnchain({required String address, required int sats}) async {
    final onChain = await _n.onChainPayment();
    final txid = await onChain.sendToAddress(
      address: ldk.Address(s: address),
      amountSats: BigInt.from(sats),
    );
    return txid.hash;
  }

  @override
  Future<List<ChannelSummary>> channels() async {
    final list = await _n.listChannels();
    return list
        .map((ch) => ChannelSummary(
              capacitySats: ch.channelValueSats.toInt(),
              inboundSats: (ch.inboundCapacityMsat ~/ BigInt.from(1000)).toInt(),
              outboundSats: (ch.outboundCapacityMsat ~/ BigInt.from(1000)).toInt(),
              isUsable: ch.isUsable,
              counterpartyNodeId: ch.counterpartyNodeId.hex,
            ))
        .toList();
  }

  @override
  Future<void> openChannel({
    required String nodeId,
    required String host,
    required int port,
    required int amountSats,
  }) async {
    await _n.connectOpenChannel(
      channelAmountSats: BigInt.from(amountSats),
      nodeId: ldk.PublicKey(hex: nodeId),
      socketAddress: ldk.SocketAddress.hostname(addr: host, port: port),
      announceChannel: true,
    );
  }

  @override
  Future<void> sync() => _n.syncWallets();

  static String _hashHex(ldk.PaymentHash h) =>
      h.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<NodeEvent?> nextEvent() async {
    final event = await _n.nextEvent();
    if (event == null) return null;
    return event.maybeWhen(
      paymentReceived: (id, hash, amountMsat) => NodeEvent(
        type: 'payment_received',
        paymentHashHex: _hashHex(hash),
        amountMsat: amountMsat.toInt(),
      ),
      paymentSuccessful: (id, hash, fee) => NodeEvent(
        type: 'payment_successful',
        paymentHashHex: _hashHex(hash),
      ),
      paymentFailed: (id, hash, reason) => NodeEvent(
        type: 'payment_failed',
        paymentHashHex: _hashHex(hash),
      ),
      orElse: () => const NodeEvent(type: 'other'),
    );
  }

  @override
  Future<void> eventHandled() => _n.eventHandled();
}

// ---------------------------------------------------------------------------
// Implementação remota (REST) — daemon local iris-noded em 127.0.0.1
// ---------------------------------------------------------------------------

class RemoteNodeApi implements NodeApi {
  final Uri baseUrl;
  final http.Client _client;

  RemoteNodeApi(String url, {http.Client? client})
      : baseUrl = Uri.parse(url),
        _client = client ?? http.Client();

  Uri _u(String path) => baseUrl.replace(path: path);

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await _client.get(_u(path)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception('Daemon respondeu ${r.statusCode} em $path: ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await _client
        .post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('Daemon respondeu ${r.statusCode} em $path: ${r.body}');
    }
    return r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<void> start() async {
    // O daemon já roda como processo próprio; apenas valida a conexão.
    final health = await _get('/health');
    if (health['status'] != 'ok') {
      throw Exception('Daemon local não está saudável: $health');
    }
  }

  @override
  Future<void> stop() async {
    _client.close();
  }

  @override
  Future<String> createInvoice({int? amountMsat, required String description, required int expirySecs}) async {
    final r = await _post('/invoice', {
      'amount_msat': amountMsat,
      'description': description,
      'expiry_secs': expirySecs,
    });
    return r['invoice'] as String;
  }

  @override
  Future<void> payInvoice(String invoice, {int? amountMsat}) async {
    await _post('/pay', {'invoice': invoice, 'amount_msat': amountMsat});
  }

  @override
  Future<NodeBalances> balances() async {
    final r = await _get('/balances');
    return NodeBalances(
      lightningSats: (r['lightning_sats'] as num?)?.toInt() ?? 0,
      onchainTotalSats: (r['onchain_total_sats'] as num?)?.toInt() ?? 0,
      onchainSpendableSats: (r['onchain_spendable_sats'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<String> newOnchainAddress() async {
    final r = await _get('/onchain_address');
    return r['address'] as String;
  }

  @override
  Future<String> sendOnchain({required String address, required int sats}) async {
    final r = await _post('/send_onchain', {'address': address, 'amount_sats': sats});
    return r['txid']?.toString() ?? '';
  }

  @override
  Future<List<ChannelSummary>> channels() async {
    final r = await _get('/channels');
    final list = (r['channels'] as List?) ?? [];
    return list
        .map((c) => ChannelSummary(
              capacitySats: (c['capacity_sats'] as num?)?.toInt() ?? 0,
              inboundSats: (c['inbound_sats'] as num?)?.toInt() ?? 0,
              outboundSats: (c['outbound_sats'] as num?)?.toInt() ?? 0,
              isUsable: c['usable'] == true,
              counterpartyNodeId: c['counterparty']?.toString() ?? '',
            ))
        .toList();
  }

  @override
  Future<void> openChannel({
    required String nodeId,
    required String host,
    required int port,
    required int amountSats,
  }) async {
    await _post('/open_channel', {
      'node_id': nodeId,
      'host': host,
      'port': port,
      'amount_sats': amountSats,
    });
  }

  @override
  Future<void> sync() async {
    await _post('/sync', {});
  }

  @override
  Future<NodeEvent?> nextEvent() async {
    final r = await _get('/event');
    final e = r['event'];
    if (e == null) return null;
    return NodeEvent(
      type: e['type']?.toString() ?? 'other',
      paymentHashHex: e['payment_hash']?.toString() ?? '',
      amountMsat: (e['amount_msat'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> eventHandled() async {
    await _post('/event_handled', {});
  }
}
