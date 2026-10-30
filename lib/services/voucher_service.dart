import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/rede.dart';
import '../core/varredura.dart';
import 'esplora_servidores.dart';
import 'node_backend.dart';
import 'taxa_rede.dart';
import 'wallet_service.dart';

/// Vouchers e carteiras de papel: resgatar (varrer uma chave avulsa para a
/// carteira) e emitir (o lojista cria uma chave nova, financia e imprime).
/// Tudo assinado no aparelho; nenhum servidor da Iris.
class VoucherService {
  final WalletService carteira;
  VoucherService(this.carteira);

  static const _cofre = FlutterSecureStorage();
  static const _chaveEmitidos = 'vouchers_emitidos_v1';

  /// Saldo que a chave tem agora (para mostrar antes de resgatar).
  Future<({ChaveAvulsa chave, List<Utxo> utxos, int total})> consultar(
      String wif) async {
    final chave = ChaveAvulsa.deWif(wif);
    if (chave.principal != Rede.principal) {
      throw const FormatException('Esta chave é de outra rede.');
    }
    final utxos = <Utxo>[];
    for (final script in chave.scripts) {
      final r = await _esplora('/scripthash/${scripthashEsplora(script)}/utxo');
      for (final u in jsonDecode(r) as List) {
        utxos.add(Utxo(u['txid'] as String, u['vout'] as int,
            (u['value'] as num).toInt(), script));
      }
    }
    return (
      chave: chave,
      utxos: utxos,
      total: utxos.fold<int>(0, (a, u) => a + u.valor),
    );
  }

  /// Varre tudo para a carteira pessoal. Devolve o txid.
  Future<String> resgatar(String wif) async {
    final c = await consultar(wif);
    if (c.utxos.isEmpty) {
      throw const FormatException('Esta chave não tem saldo (ou já foi resgatada).');
    }
    final destino = await carteira.getOnchainAddress();
    final hex = varrer(
      chave: c.chave,
      utxos: c.utxos,
      destino: scriptDeEndereco(destino, Rede.hrpEndereco),
      satsPorVbyte: await _taxa(),
    );
    return EmbeddedNodeApi.transmitirPorEsplora(hex);
  }

  /// Emite um voucher de [sats]: gera a chave, financia pela carteira e
  /// guarda a chave no cofre do aparelho (para reaver se não for resgatado).
  /// Quem tiver o papel tem o bitcoin — e quem emitiu também conhece a chave.
  ///
  /// [confirmar] recebe o envio já assinado (com a taxa exata) e decide se
  /// segue; devolver false cancela sem mover nada. Devolve null se cancelado.
  Future<ChaveAvulsa?> emitir(int sats,
      {required Future<bool> Function(EnvioPreparado envio) confirmar}) async {
    final chave = ChaveAvulsa.nova(principal: Rede.principal);
    final envio = await carteira.prepararEnvioOnchain(
        address: chave.enderecoSegwit(Rede.hrpEndereco), sats: sats);
    if (envio.taxa >= sats) {
      throw Exception(TaxaRede.alerta(taxa: envio.taxa, valor: sats));
    }
    if (!await confirmar(envio)) return null;
    final emitidos = await emitidosGuardados();
    emitidos.add({'wif': chave.wif, 'sats': sats, 'em': DateTime.now().toIso8601String()});
    // Guarda ANTES de mandar o dinheiro: se o app cair no meio, a chave não se perde.
    await _cofre.write(key: _chaveEmitidos, value: jsonEncode(emitidos));
    await carteira.confirmarEnvioOnchain(envio);
    return chave;
  }

  Future<List<Map<String, dynamic>>> emitidosGuardados() async {
    final bruto = await _cofre.read(key: _chaveEmitidos);
    if (bruto == null) return [];
    return (jsonDecode(bruto) as List).cast<Map<String, dynamic>>();
  }

  Future<double> _taxa() async {
    final t = await TaxaRede.consultar();
    if (t == null) {
      throw Exception('Não foi possível consultar a taxa da rede agora.');
    }
    return t.economico;
  }

  Future<String> _esplora(String caminho) async {
    final lista = <String>{
      if (EmbeddedNodeApi.esploraEmUso != null) EmbeddedNodeApi.esploraEmUso!,
      ...await EsploraServidores.candidatos(),
    };
    Object? erro;
    for (final base in lista) {
      try {
        final r = await http
            .get(Uri.parse('$base$caminho'))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode >= 200 && r.statusCode < 300) return r.body;
        erro = 'HTTP ${r.statusCode}';
      } catch (e) {
        erro = e;
      }
    }
    throw Exception('Servidores da rede indisponíveis ($erro).');
  }
}
