import 'dart:convert';
import 'dart:typed_data';
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

/// Um pagamento Lightning como o nó o registrou.
class PaymentRecord {
  final String id;
  final int amountSats;
  final bool isIncoming;

  /// pending | confirmed | failed — já traduzido do enum do LDK.
  final String status;
  final DateTime date;

  /// True quando o movimento é on-chain, não Lightning.
  ///
  /// O `listPayments()` do LDK devolve os DOIS tipos. Sem esta distinção o app
  /// rotulava tudo como Lightning — e mostrava "Recebido via Lightning" numa
  /// carteira que nunca teve canal aberto.
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

  /// Anunciado publicamente na rede — só canais anunciados são elegíveis para
  /// o roteamento de pagamentos de TERCEIROS (pathfinding de outros nós só
  /// considera o que é público).
  final bool isPublic;

  /// Identificador opaco do canal, no formato que o backend (embarcado ou
  /// daemon) espera de volta em [NodeApi.updateForwardingFee]. Não parsear.
  final String userChannelId;

  /// Taxa de roteamento QUE ESTE USUÁRIO cobra quando o próprio nó dele
  /// encaminha um pagamento de outra pessoa por este canal. É creditada pelo
  /// protocolo Lightning direto no saldo do nó — nunca passa pelo Iris.
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

/// Evento do nó já normalizado entre os dois backends.
class NodeEvent {
  final String
      type; // payment_received | payment_successful | payment_failed | other
  final String paymentHashHex;
  final int amountMsat;
  const NodeEvent(
      {required this.type, this.paymentHashHex = '', this.amountMsat = 0});
}

abstract class NodeApi {
  Future<void> start();
  Future<void> stop();

  /// Identidade pública deste nó (chave hex) — o que outro dispositivo
  /// precisa saber, junto com um endereço alcançável, para se conectar a
  /// ele e abrir um canal. Sem isto exibido em algum lugar, ninguém consegue
  /// mirar este nó de fora.
  Future<String> myNodeId();

  Future<String> createInvoice(
      {int? amountMsat, required String description, required int expirySecs});

  /// Offer BOLT12 de valor aberto — o QR Lightning REUTILIZÁVEL.
  ///
  /// A fatura BOLT11 é de uso único por desenho do protocolo (o payment_hash
  /// não pode repetir), então um QR BOLT11 impresso vira lixo após o primeiro
  /// pagamento. O offer BOLT12 foi feito exatamente para este caso: o mesmo
  /// código serve para infinitos pagamentos.
  ///
  /// Devolve null se o backend não suportar — o app cai na BOLT11.
  Future<String?> createOffer({required String description});

  /// Histórico de pagamentos Lightning que o PRÓPRIO nó guarda em disco.
  ///
  /// Serve para reconstruir o extrato quando o app perdeu o dele (versões
  /// antigas não persistiam nada) ou ao restaurar a carteira em outro
  /// aparelho: o LDK mantém esse registro no diretório do nó, então ele é uma
  /// fonte de verdade independente da nossa.
  Future<List<PaymentRecord>> listPayments();

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

  /// Define a taxa de roteamento cobrada quando ESTE nó encaminha um
  /// pagamento de outra pessoa através de [userChannelId]. O ganho é do
  /// usuário: creditado pelo protocolo Lightning direto no saldo do nó dele,
  /// nunca retido pelo app.
  Future<void> updateForwardingFee({
    required String counterpartyNodeId,
    required String userChannelId,
    required int proportionalPpm,
    required int baseMsat,
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

  /// Backends Esplora da TESTNET4 (a testnet3 foi removida do projeto).
  ///
  /// Só o mempool.space serve testnet4 por HTTP API — o blockstream.info
  /// responde HTML nesse caminho, não JSON, então não entra na lista. Isso
  /// deixa um único provedor: se ele limitar por taxa, não há para onde cair.
  static const List<String> esploraCandidatos = [
    'https://mempool.space/testnet4/api',
    // Mirror oficial do mempool.space. Mais lento, mas serve de alternativa
    // real quando o principal engasga — a testnet4 não tem outro provedor
    // (o blockstream.info não expõe essa rede).
    'https://mempool.va1.mempool.space/testnet4/api',
  ];

  /// Devolve o primeiro backend que responder 200 rápido. Se nenhum responder,
  /// devolve o primeiro da lista para o LDK tentar mesmo assim e reportar o
  /// erro real, em vez de a gente inventar um.
  /// Último Esplora que respondeu bem. Guardado para quem precisa consultar a
  /// cadeia por fora do LDK (ex.: a vigia rápida de recebimentos em
  /// [WalletService]) usar exatamente o mesmo servidor do nó.
  static String? esploraEmUso;

  static Future<String> escolherEsplora() async {
    for (final base in esploraCandidatos) {
      try {
        // Testamos `/fee-estimates`, NÃO `/blocks/tip/height`.
        //
        // O tip é uma resposta minúscula e passava mesmo em servidor
        // degradado; o start do nó, porém, depende de `fee-estimates`, que é
        // bem maior. Resultado observado no celular: a checagem aprovava o
        // servidor e o nó morria em seguida com `feerateEstimationUpdateFailed`
        // (timeout de 30s do ldk_node), em ciclo infinito. Testar o endpoint
        // que realmente decide o start é o que torna a escolha honesta.
        final r = await http
            .get(Uri.parse('$base/fee-estimates'))
            .timeout(const Duration(seconds: 10));
        // 2xx (o mempool.space costuma devolver 203 via CDN, não só 200).
        if (r.statusCode >= 200 && r.statusCode < 300 && r.body.isNotEmpty) {
          debugPrint('Esplora escolhido: $base');
          esploraEmUso = base;
          return base;
        }
        debugPrint(
            'Esplora $base respondeu HTTP ${r.statusCode}; tentando outro.');
      } catch (e) {
        debugPrint('Esplora $base indisponível ($e); tentando outro.');
      }
    }
    debugPrint('Nenhum Esplora respondeu; usando ${esploraCandidatos.first}.');
    esploraEmUso ??= esploraCandidatos.first;
    return esploraCandidatos.first;
  }

  /// Tentativas de construir e iniciar o nó antes de desistir. Um Esplora
  /// pode passar no teste rápido de saúde (`escolherEsplora`, um GET simples)
  /// e mesmo assim falhar durante o start de verdade do LDK, que bate em
  /// mais endpoints (ex.: estimativa de taxa) — foi exatamente isso que
  /// aconteceu ao vivo num dispositivo real (`LdkNodeError.
  /// feerateEstimationUpdateFailed`). Sem retry, uma degradação transitória
  /// de rede derrubava o nó pro modo mock pelo resto da sessão. Mesma lógica
  /// já aplicada no daemon (`construir_e_iniciar` em `daemon/src/main.rs`).
  /// 2, não 3: cada tentativa pode custar o timeout do cache de taxas, e o
  /// usuário fica sem endereço de recebimento (QR "carregando") enquanto isso.
  /// Ir para o modo degradado mais cedo é melhor do que travar a tela — o
  /// sync periódico e a recuperação automática religam o nó depois.
  static const int _tentativasDeStart = 2;

  /// Permite abandonar as tentativas quando elas deixaram de importar — por
  /// exemplo, o usuário trocou de conta e este start é de uma semente antiga.
  /// Sem isto, o start novo ficava na fila atrás de um que ninguém mais quer.
  bool Function()? abortarSe;

  @override
  Future<void> start() async {
    Object? ultimoErro;

    // Percorremos os servidores DIRETAMENTE, sem checagem de saúde antes.
    //
    // A checagem era um GET a `/fee-estimates` — o mesmo endpoint que o nó
    // consulta logo depois. Numa rede com rate-limit apertado ela gastava a
    // cota e fazia a requisição do nó levar 429, ou seja, o teste derrubava
    // justamente o que ele deveria proteger. Pior: `escolherEsplora()` rodava
    // a cada tentativa, dobrando as requisições. O próprio start é o melhor
    // teste possível, e falhar nele já nos manda para o servidor seguinte.
    final candidatos = esploraUrl.isNotEmpty ? [esploraUrl] : esploraCandidatos;

    for (var tentativa = 1; tentativa <= _tentativasDeStart; tentativa++) {
      if (abortarSe?.call() ?? false) {
        debugPrint('Start do nó abandonado: outra carteira assumiu.');
        return;
      }
      // Tentativa 1 usa o primeiro candidato, tentativa 2 o segundo, e assim
      // por diante (voltando ao início se acabarem).
      final esplora = candidatos[(tentativa - 1) % candidatos.length];
      esploraEmUso = esplora;
      debugPrint('Iniciando nó com Esplora: $esplora');
      try {
        final builder = ldk.Builder()
          ..setEntropyBip39Mnemonic(
              mnemonic: ldk.Mnemonic(seedPhrase: mnemonic))
          // TESTNET4 NATIVA. Até o porte do ldk_node 0.3.0 -> 0.7.0 isto era
          // impossível: a 0.3.0 não conhecia testnet4 (depende do crate
          // bitcoin 0.30; a variante só existe a partir do 0.32), então o app
          // rodava em `testnet` (testnet3) enquanto os dados da cadeia vinham
          // da testnet4. On-chain funcionava — os endereços são idênticos
          // entre as duas redes — mas o ChainHash anunciado no Lightning era o
          // da testnet3, e por isso NENHUM nó real aceitava abrir canal.
          // Agora a rede anunciada e a cadeia consultada são a mesma.
          ..setNetwork(ldk.Network.testnet4)
          ..setStorageDirPath(storagePath)
          ..setListeningAddresses([
            ldk.SocketAddress.hostname(addr: '0.0.0.0', port: listeningPort)
          ])
          ..setEsploraServer(esplora);
        final node = await builder.build();
        await node.start();
        _node = node;
        return;
      } catch (e) {
        ultimoErro = e;
        debugPrint(
            'Tentativa $tentativa/$_tentativasDeStart de iniciar o nó falhou ($esplora): $e');
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

  @override
  Future<List<PaymentRecord>> listPayments() async {
    try {
      final pagamentos = await _n.listPayments();
      final out = <PaymentRecord>[];
      for (final p in pagamentos) {
        // Cada entrada é convertida isoladamente: um registro estranho no
        // armazenamento do LDK não pode impedir a leitura de todo o extrato.
        try {
          final msat = p.amountMsat;
          if (msat == null) continue; // fatura de valor aberto nunca paga
          out.add(PaymentRecord(
            id: p.id.field0.toString(),
            amountSats: (msat.toInt() / 1000).round(),
            isIncoming: p.direction == ldk.PaymentDirection.inbound,
            // O LDK mistura on-chain e Lightning na mesma lista; o `kind` é o
            // que separa os dois.
            isOnchain: p.kind is ldk.PaymentKind_Onchain,
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
      // BOLT12 no ldk_node 0.3.0 é recente e depende de canal utilizável;
      // sem ele o app segue com BOLT11 (uso único) em vez de ficar sem QR.
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
    await _n.connectOpenChannel(
      channelAmountSats: BigInt.from(amountSats),
      nodeId: ldk.PublicKey(hex: nodeId),
      socketAddress: ldk.SocketAddress.hostname(addr: host, port: port),
      announceChannel: true,
    );
  }

  @override
  Future<void> updateForwardingFee({
    required String counterpartyNodeId,
    required String userChannelId,
    required int proportionalPpm,
    required int baseMsat,
  }) async {
    // Preserva o resto da config do canal (cltv, dust exposure etc.) — só as
    // duas taxas de roteamento mudam.
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

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final r = await _client
        .post(_u(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
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
    // O daemon (iris-noded) ainda não expõe BOLT12; o app cai na BOLT11.
    return null;
  }

  @override
  Future<List<PaymentRecord>> listPayments() async => const [];

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
