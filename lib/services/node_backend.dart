import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:ldk_node/ldk_node.dart' as ldk;
import '../core/rede.dart';
import 'esplora_servidores.dart';

class PaymentRecord {
  final String id;
  final int amountSats;
  final bool isIncoming;

  final String status;
  final DateTime date;

  final bool isOnchain;

  const PaymentRecord({
    required this.id,
    required this.amountSats,
    required this.isIncoming,
    required this.status,
    required this.date,
    this.isOnchain = false,
  });
}

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

  final bool isPublic;

  final String userChannelId;

  final int forwardingFeeProportionalPpm;
  final int forwardingFeeBaseMsat;

  const ChannelSummary({
    required this.capacitySats,
    required this.inboundSats,
    required this.outboundSats,
    required this.isUsable,
    required this.counterpartyNodeId,
    this.isPublic = false,
    this.userChannelId = '',
    this.forwardingFeeProportionalPpm = 0,
    this.forwardingFeeBaseMsat = 0,
  });
}

class NodeEvent {
  final String type;
  final String paymentHashHex;
  final int amountMsat;

  /// Em `payment_claimable`: altura de bloco até a qual a trava vale.
  final int? claimDeadline;
  const NodeEvent(
      {required this.type,
      this.paymentHashHex = '',
      this.amountMsat = 0,
      this.claimDeadline});
}

abstract class NodeApi {
  Future<void> start();
  Future<void> stop();

  Future<String> myNodeId();

  Future<String> createInvoice(
      {int? amountMsat, required String description, required int expirySecs});

  Future<String?> createOffer({required String description});

  Future<List<PaymentRecord>> listPayments();

  Future<void> payInvoice(String invoice, {int? amountMsat});
  Future<NodeBalances> balances();
  Future<String> newOnchainAddress();

  Future<String> sendOnchain({required String address, required int sats});

  /// Assina sem transmitir. [satPorVbyte]: taxa escolhida pelo app (null =
  /// estimativa do nó). [registrar]: marca como pendente já (pagamento
  /// offline) ou deixa como prévia, para [registrarTransacao] após o OK.
  Future<({String txid, String txHex, int feeSats})> signOnchain(
      {required String address,
      required int sats,
      double? satPorVbyte,
      bool registrar = true});

  /// Marca como pendente uma transação assinada em prévia.
  Future<void> registrarTransacao(String txHex);

  /// Transmite uma transação já assinada, recebida de outro aparelho.
  Future<String> broadcastTx(String txHex);

  /// Garantia de troca: fatura para um hash cujo segredo só o outro lado tem.
  /// O pagamento chega como `payment_claimable` e fica travado até [resgatarTrava]
  /// (com o segredo) ou [recusarTrava] — ou o prazo vencer e voltar ao pagador.
  Future<String> criarFaturaComHash(
      {required String hashHex,
      required int amountMsat,
      required String description,
      required int expirySecs});
  Future<void> resgatarTrava(
      {required String hashHex,
      required String segredoHex,
      required int amountMsat});
  Future<void> recusarTrava(String hashHex);
  Future<List<ChannelSummary>> channels();
  Future<void> openChannel({
    required String nodeId,
    required String host,
    required int port,
    required int amountSats,
  });

  /// Fecha um canal, devolvendo o saldo para a carteira on-chain. [force]
  /// fecha unilateralmente (quando o parceiro está offline) — só vale no nó
  /// embarcado; no daemon o fechamento é sempre cooperativo.
  Future<void> closeChannel({
    required String userChannelId,
    required String counterpartyNodeId,
    bool force = false,
  });

  Future<void> updateForwardingFee({
    required String counterpartyNodeId,
    required String userChannelId,
    required int proportionalPpm,
    required int baseMsat,
  });
  Future<void> sync();
  Future<void> fullScan();
  Future<NodeEvent?> nextEvent();
  Future<void> eventHandled();
}

class EmbeddedNodeApi implements NodeApi {
  final String mnemonic;
  final String storagePath;
  final String esploraUrl;

  final int listeningPort;

  ldk.Node? _node;

  EmbeddedNodeApi({
    required this.mnemonic,
    required this.storagePath,
    this.listeningPort = 9735,
    this.esploraUrl = '',
  });

  static String? esploraEmUso;

  static const int _tentativasDeStart = 3;

  bool Function()? abortarSe;

  // Alguns ambientes recusam o bind de escuta P2P em 0.0.0.0 (visto na isolate
  // de fundo no Android e no daemon no Windows): o ldk-node devolve
  // `invalidSocketAddress`/"network address is invalid" e o nó não sobe. Nesse
  // caso subimos SEM endereço de escuta — o nó ainda recebe por canais
  // existentes, paga e abre canais de saída; só não aceita conexões de entrada.
  static bool _ehErroDeEndereco(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('invalidsocketaddress') ||
        m.contains('socket address') ||
        m.contains('network address') ||
        m.contains('listening');
  }

  @override
  Future<void> start() async {
    Object? ultimoErro;

    final candidatos = esploraUrl.isNotEmpty
        ? [esploraUrl]
        : await EsploraServidores.emOrdemDeUso();

    var semEscuta = false;
    for (var tentativa = 1; tentativa <= _tentativasDeStart; tentativa++) {
      if (abortarSe?.call() ?? false) {
        debugPrint('Start do nó abandonado: outra carteira assumiu.');
        return;
      }

      final esplora = candidatos[(tentativa - 1) % candidatos.length];
      esploraEmUso = esplora;
      debugPrint(
          'Iniciando nó com Esplora: $esplora${semEscuta ? ' (sem escuta P2P)' : ''}');
      try {
        final builder = ldk.Builder()
          ..setEntropyBip39Mnemonic(
              mnemonic: ldk.Mnemonic(seedPhrase: mnemonic))
          ..setNetwork(Rede.principal
              ? ldk.Network.bitcoin
              : (Rede.ehSignet
                  ? ldk.Network.signet
                  : ldk.Network.testnet4))
          ..setStorageDirPath(storagePath);
        if (!semEscuta) {
          builder.setListeningAddresses([
            ldk.SocketAddress.hostname(addr: '0.0.0.0', port: listeningPort)
          ]);
        }
        builder.setEsploraServer(esplora);
        final node = await builder.build();
        await node.start();
        _node = node;
        return;
      } catch (e) {
        ultimoErro = e;
        debugPrint(
            'Tentativa $tentativa/$_tentativasDeStart de iniciar o nó falhou ($esplora): $e');
        // Se foi o endereço de escuta, desliga a escuta e tenta de novo já.
        if (!semEscuta && _ehErroDeEndereco(e)) {
          semEscuta = true;
          debugPrint('Escuta P2P recusada; repetindo sem endereço de escuta.');
          continue;
        }
        if (tentativa < _tentativasDeStart) {
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }
    throw Exception(
        'Falha ao iniciar o nó após $_tentativasDeStart tentativas: $ultimoErro');
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
  Future<String> myNodeId() async {
    final pk = await _n.nodeId();
    return pk.hex;
  }

  @override
  Future<String> createInvoice(
      {int? amountMsat,
      required String description,
      required int expirySecs}) async {
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

  static String idDePagamentoParaTeste(dynamic campo, bool ehOnchain) =>
      _idDePagamento(campo, ehOnchain);

  static String _idDePagamento(dynamic campo, bool ehOnchain) {
    List<int>? bytes;

    if (campo is List<int>) {
      bytes = campo;
    } else {
      final texto = campo.toString();

      if (texto.startsWith('[') && texto.endsWith(']')) {
        try {
          bytes = texto
              .substring(1, texto.length - 1)
              .split(',')
              .map((s) => int.parse(s.trim()))
              .toList();
        } catch (_) {}
      } else if (texto.length == 64 &&
          RegExp(r'^[0-9a-fA-F]+$').hasMatch(texto)) {
        bytes = [
          for (var i = 0; i < 64; i += 2)
            int.parse(texto.substring(i, i + 2), radix: 16)
        ];
      }

      if (bytes == null) return texto;
    }

    if (bytes.length != 32) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    final ordem = ehOnchain ? bytes.reversed : bytes;
    return ordem.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Future<List<PaymentRecord>> listPayments() async {
    try {
      final pagamentos = await _n.listPayments();
      final out = <PaymentRecord>[];
      for (final p in pagamentos) {
        try {
          final msat = p.amountMsat;
          if (msat == null) continue;
          final ehOnchain = p.kind is ldk.PaymentKind_Onchain;
          out.add(PaymentRecord(
            id: _idDePagamento(p.id.field0, ehOnchain),
            amountSats: (msat.toInt() / 1000).round(),
            isIncoming: p.direction == ldk.PaymentDirection.inbound,
            isOnchain: ehOnchain,
            status: switch (p.status) {
              ldk.PaymentStatus.succeeded => 'confirmed',
              ldk.PaymentStatus.failed => 'failed',
              _ => 'pending',
            },
            date: DateTime.fromMillisecondsSinceEpoch(
                p.latestUpdateTimestamp.toInt() * 1000),
          ));
        } catch (e) {
          debugPrint('Entrada do extrato ignorada (conversão falhou): $e');
        }
      }
      return out;
    } catch (e) {
      debugPrint('Não foi possível ler o histórico do nó: $e');
      return [];
    }
  }

  @override
  Future<String?> createOffer({required String description}) async {
    try {
      final bolt12 = await _n.bolt12Payment();
      final offer =
          await bolt12.receiveVariableAmount(description: description);
      return offer.s;
    } catch (e) {
      debugPrint('Offer BOLT12 indisponível: $e');
      return null;
    }
  }

  @override
  Future<void> payInvoice(String invoice, {int? amountMsat}) async {
    final bolt11 = await _n.bolt11Payment();
    final inv = ldk.Bolt11Invoice(signedRawInvoice: invoice.trim());
    if (amountMsat != null) {
      await bolt11.sendUsingAmount(
          invoice: inv, amountMsat: BigInt.from(amountMsat));
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
  Future<String> sendOnchain(
      {required String address, required int sats}) async {
    final onChain = await _n.onChainPayment();
    final txid = await onChain.sendToAddress(
      address: ldk.Address(s: address),
      amountSats: BigInt.from(sats),
    );
    return txid.hash;
  }

  @override
  Future<({String txid, String txHex, int feeSats})> signOnchain(
      {required String address,
      required int sats,
      double? satPorVbyte,
      bool registrar = true}) async {
    final onChain = await _n.onChainPayment();
    final tx = await onChain.signToAddress(
      address: ldk.Address(s: address),
      amountSats: BigInt.from(sats),
      feeRateSatPerKwu: satPorVbyte == null
          ? null
          : BigInt.from((satPorVbyte * 250).ceil()),
      registrar: registrar,
    );
    return (txid: tx.txid, txHex: tx.txHex, feeSats: tx.feeSats.toInt());
  }

  @override
  Future<void> registrarTransacao(String txHex) async {
    final onChain = await _n.onChainPayment();
    await onChain.registerTransaction(txHex: txHex);
  }

  @override
  Future<String> broadcastTx(String txHex) => transmitirPorEsplora(txHex);

  static ldk.U8Array32 _arr32(String hex) => ldk.U8Array32(_hexToBytes(hex));

  @override
  Future<String> criarFaturaComHash(
      {required String hashHex,
      required int amountMsat,
      required String description,
      required int expirySecs}) async {
    final bolt11 = await _n.bolt11Payment();
    final inv = await bolt11.receiveForHash(
      paymentHash: ldk.PaymentHash(data: _arr32(hashHex)),
      amountMsat: BigInt.from(amountMsat),
      description: description,
      expirySecs: expirySecs,
    );
    return inv.signedRawInvoice;
  }

  @override
  Future<void> resgatarTrava(
      {required String hashHex,
      required String segredoHex,
      required int amountMsat}) async {
    final bolt11 = await _n.bolt11Payment();
    await bolt11.claimForHash(
      paymentHash: ldk.PaymentHash(data: _arr32(hashHex)),
      claimableAmountMsat: BigInt.from(amountMsat),
      preimage: ldk.PaymentPreimage(data: _arr32(segredoHex)),
    );
  }

  @override
  Future<void> recusarTrava(String hashHex) async {
    final bolt11 = await _n.bolt11Payment();
    await bolt11.failForHash(
        paymentHash: ldk.PaymentHash(data: _arr32(hashHex)));
  }

  /// Tenta o servidor em uso e depois os demais: quem transmite um pagamento
  /// recebido offline pode estar com a rede instável.
  static Future<String> transmitirPorEsplora(String txHex) async {
    final lista = <String>{
      if (esploraEmUso != null) esploraEmUso!,
      ...await EsploraServidores.candidatos(),
    };
    Object? ultimoErro;
    for (final base in lista) {
      try {
        final r = await http
            .post(Uri.parse('$base/tx'), body: txHex.trim())
            .timeout(const Duration(seconds: 30));
        if (r.statusCode >= 200 && r.statusCode < 300) return r.body.trim();
        ultimoErro = r.body;
        if (r.statusCode == 400) break;
      } catch (e) {
        ultimoErro = e;
      }
    }
    throw Exception('A rede recusou a transação: $ultimoErro');
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  Future<List<ChannelSummary>> channels() async {
    final list = await _n.listChannels();
    return list
        .map((ch) => ChannelSummary(
              capacitySats: ch.channelValueSats.toInt(),
              inboundSats:
                  (ch.inboundCapacityMsat ~/ BigInt.from(1000)).toInt(),
              outboundSats:
                  (ch.outboundCapacityMsat ~/ BigInt.from(1000)).toInt(),
              isUsable: ch.isUsable,
              counterpartyNodeId: ch.counterpartyNodeId.hex,
              isPublic: ch.isPublic,
              userChannelId: _bytesToHex(ch.userChannelId.data),
              forwardingFeeProportionalPpm:
                  ch.config.forwardingFeeProportionalMillionths,
              forwardingFeeBaseMsat: ch.config.forwardingFeeBaseMsat,
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
    // Canal PRIVADO (não anunciado). Duas razões, uma prática e uma correta:
    //
    // 1. `announceChannel: true` cai em `open_announced_channel`, que exige
    //    `may_announce_channel`: endereços de escuta E um *node alias*. O alias
    //    não está exposto na API Dart do ldk_node, então a chamada falhava
    //    sempre com `Failed to create channel` — antes mesmo de tentar conectar.
    //
    // 2. Anunciar é publicar o canal para a rede toda rotear. Uma carteira num
    //    celular ou num PC atrás de NAT não é nó de encaminhamento, e o que
    //    seria anunciado é um IP de rede local, inútil para terceiros.
    //
    // Canal privado recebe pagamento normalmente: faturas BOLT11 carregam route
    // hints e o BOLT12 usa caminhos cegos.
    await _n.connectOpenChannel(
      channelAmountSats: BigInt.from(amountSats),
      nodeId: ldk.PublicKey(hex: nodeId),
      socketAddress: ldk.SocketAddress.hostname(addr: host, port: port),
      announceChannel: false,
    );
  }

  @override
  Future<void> closeChannel({
    required String userChannelId,
    required String counterpartyNodeId,
    bool force = false,
  }) async {
    final uid = ldk.UserChannelId(data: _hexToBytes(userChannelId));
    final peer = ldk.PublicKey(hex: counterpartyNodeId);
    // Cooperativo quando os dois lados estão online (taxa menor, confirma
    // rápido). Forçado é a saída quando o parceiro sumiu — o saldo só volta
    // depois do atraso de segurança do canal.
    if (force) {
      await _n.forceCloseChannel(
          userChannelId: uid, counterpartyNodeId: peer);
    } else {
      await _n.closeChannel(userChannelId: uid, counterpartyNodeId: peer);
    }
  }

  @override
  Future<void> updateForwardingFee({
    required String counterpartyNodeId,
    required String userChannelId,
    required int proportionalPpm,
    required int baseMsat,
  }) async {
    final atual = (await _n.listChannels()).firstWhere(
      (ch) => _bytesToHex(ch.userChannelId.data) == userChannelId,
      orElse: () => throw Exception('Canal não encontrado.'),
    );
    final novaConfig = ldk.ChannelConfig(
      forwardingFeeProportionalMillionths: proportionalPpm,
      forwardingFeeBaseMsat: baseMsat,
      cltvExpiryDelta: atual.config.cltvExpiryDelta,
      maxDustHtlcExposure: atual.config.maxDustHtlcExposure,
      forceCloseAvoidanceMaxFeeSatoshis:
          atual.config.forceCloseAvoidanceMaxFeeSatoshis,
      acceptUnderpayingHtlcs: atual.config.acceptUnderpayingHtlcs,
    );
    await _n.updateChannelConfig(
      counterpartyNodeId: ldk.PublicKey(hex: counterpartyNodeId),
      userChannelId: ldk.UserChannelId(data: _hexToBytes(userChannelId)),
      channelConfig: novaConfig,
    );
  }

  @override
  Future<void> sync() => _n.syncWallets();

  @override
  Future<void> fullScan() => _n.fullScanWallets();

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
      paymentClaimable: (id, hash, amountMsat, deadline) => NodeEvent(
        type: 'payment_claimable',
        paymentHashHex: _hashHex(hash),
        amountMsat: amountMsat.toInt(),
        claimDeadline: deadline,
      ),
      orElse: () => const NodeEvent(type: 'other'),
    );
  }

  @override
  Future<void> eventHandled() => _n.eventHandled();
}

class RemoteNodeApi implements NodeApi {
  final Uri baseUrl;
  final http.Client _client;

  /// Token da API do daemon. Sem ele, o daemon recusa tudo (401): é o que
  /// impede um site aberto no navegador de mandar o daemon pagar.
  String? _token;
  final bool _tokenFixo;

  RemoteNodeApi(String url, {http.Client? client, String? token})
      : baseUrl = Uri.parse(url),
        _client = client ?? http.Client(),
        _token = token,
        _tokenFixo = token != null;

  /// Onde o iris-noded grava o token (só o usuário lê).
  static String? caminhoTokenPadrao() {
    final env = Platform.environment;
    final base = env['APPDATA'] ??
        env['XDG_CONFIG_HOME'] ??
        (env['HOME'] != null ? '${env['HOME']}/.config' : null);
    return base == null ? null : '$base/iris-noded/api_token';
  }

  Future<void> _lerToken() async {
    if (_tokenFixo) return;
    final caminho = caminhoTokenPadrao();
    if (caminho == null) return;
    try {
      _token = (await File(caminho).readAsString()).trim();
    } catch (_) {}
  }

  Map<String, String> get _cabecalhos => {
        if (_token != null) 'X-Iris-Token': _token!,
      };

  Uri _u(String path) => baseUrl.replace(path: path);

  Future<http.Response> _comToken(Future<http.Response> Function() pedido) async {
    if (_token == null) await _lerToken();
    var r = await pedido();
    if (r.statusCode == 401 && !_tokenFixo) {
      // O daemon gera token novo a cada partida: relê e tenta uma vez.
      await _lerToken();
      r = await pedido();
    }
    return r;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await _comToken(() => _client
        .get(_u(path), headers: _cabecalhos)
        .timeout(const Duration(seconds: 30)));
    if (r.statusCode != 200) {
      throw Exception('Daemon respondeu ${r.statusCode} em $path: ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final r = await _comToken(() => _client
        .post(_u(path),
            headers: {'Content-Type': 'application/json', ..._cabecalhos},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60)));
    if (r.statusCode != 200) {
      throw Exception('Daemon respondeu ${r.statusCode} em $path: ${r.body}');
    }
    return r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<void> start() async {
    final health = await _get('/health');
    if (health['status'] != 'ok') {
      throw Exception('Daemon local não está saudável: $health');
    }
    if (health['network'] != Rede.nome) {
      throw Exception('Daemon local está em outra rede ou desatualizado '
          '(${health['network'] ?? 'sem rede informada'}); atualize o iris-noded.');
    }
  }

  @override
  Future<void> stop() async {
    _client.close();
  }

  @override
  Future<String> myNodeId() async {
    final r = await _get('/node_id');
    return r['node_id']?.toString() ?? '';
  }

  @override
  Future<String> createInvoice(
      {int? amountMsat,
      required String description,
      required int expirySecs}) async {
    final r = await _post('/invoice', {
      'amount_msat': amountMsat,
      'description': description,
      'expiry_secs': expirySecs,
    });
    return r['invoice'] as String;
  }

  @override
  Future<String?> createOffer({required String description}) async {
    try {
      final r = await _post('/offer', {'description': description});
      return r['offer'] as String?;
    } catch (e) {
      debugPrint('Offer BOLT12 indisponível no daemon: $e');
      return null;
    }
  }

  @override
  Future<List<PaymentRecord>> listPayments() async {
    try {
      final r = await _get('/payments');
      return [
        for (final p in (r['payments'] as List? ?? const []))
          PaymentRecord(
            id: p['id'].toString(),
            amountSats: (p['amount_sats'] as num).toInt(),
            isIncoming: p['incoming'] == true,
            isOnchain: p['onchain'] == true,
            status: p['status']?.toString() ?? 'pending',
            date: DateTime.fromMillisecondsSinceEpoch(
                (p['timestamp'] as num).toInt() * 1000),
          ),
      ];
    } catch (e) {
      debugPrint('Não foi possível ler o histórico do daemon: $e');
      return [];
    }
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
  Future<String> sendOnchain(
      {required String address, required int sats}) async {
    final r =
        await _post('/send_onchain', {'address': address, 'amount_sats': sats});
    return r['txid']?.toString() ?? '';
  }

  @override
  Future<({String txid, String txHex, int feeSats})> signOnchain(
      {required String address,
      required int sats,
      double? satPorVbyte,
      bool registrar = true}) async {
    final r = await _post('/sign_onchain', {
      'address': address,
      'amount_sats': sats,
      if (satPorVbyte != null) 'fee_rate_sat_per_kwu': (satPorVbyte * 250).ceil(),
      'registrar': registrar,
    });
    return (
      txid: r['txid'] as String,
      txHex: r['tx_hex'] as String,
      feeSats: (r['fee_sats'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> registrarTransacao(String txHex) async {
    await _post('/register_tx', {'tx_hex': txHex});
  }

  @override
  Future<String> broadcastTx(String txHex) async {
    final r = await _post('/broadcast', {'tx_hex': txHex.trim()});
    return r['txid']?.toString() ?? '';
  }

  @override
  Future<String> criarFaturaComHash(
      {required String hashHex,
      required int amountMsat,
      required String description,
      required int expirySecs}) async {
    final r = await _post('/hold_invoice', {
      'payment_hash': hashHex,
      'amount_msat': amountMsat,
      'description': description,
      'expiry_secs': expirySecs,
    });
    return r['invoice'] as String;
  }

  @override
  Future<void> resgatarTrava(
      {required String hashHex,
      required String segredoHex,
      required int amountMsat}) async {
    await _post('/claim', {
      'payment_hash': hashHex,
      'preimage': segredoHex,
      'amount_msat': amountMsat,
    });
  }

  @override
  Future<void> recusarTrava(String hashHex) async {
    await _post('/fail', {'payment_hash': hashHex});
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
              isPublic: c['public'] == true,
              userChannelId: c['user_channel_id']?.toString() ?? '',
              forwardingFeeProportionalPpm:
                  (c['forwarding_fee_proportional_ppm'] as num?)?.toInt() ?? 0,
              forwardingFeeBaseMsat:
                  (c['forwarding_fee_base_msat'] as num?)?.toInt() ?? 0,
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
  Future<void> closeChannel({
    required String userChannelId,
    required String counterpartyNodeId,
    bool force = false,
  }) async {
    // O daemon só tem fechamento cooperativo; [force] é ignorado aqui.
    await _post('/close_channel', {
      'user_channel_id': userChannelId,
      'counterparty_node_id': counterpartyNodeId,
    });
  }

  @override
  Future<void> updateForwardingFee({
    required String counterpartyNodeId,
    required String userChannelId,
    required int proportionalPpm,
    required int baseMsat,
  }) async {
    await _post('/set_forwarding_fee', {
      'counterparty_node_id': counterpartyNodeId,
      'user_channel_id': userChannelId,
      'forwarding_fee_proportional_ppm': proportionalPpm,
      'forwarding_fee_base_msat': baseMsat,
    });
  }

  @override
  Future<void> sync() async {
    await _post('/sync', {});
  }

  @override
  Future<void> fullScan() async {
    await _post('/full_scan', {});
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
      claimDeadline: (e['claim_deadline'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> eventHandled() async {
    await _post('/event_handled', {});
  }
}
