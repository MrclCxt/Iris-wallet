import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:iris_wallet/core/varredura.dart';
import 'package:iris_wallet/nostr/chaves.dart';

/// Voucher / carteira de papel: chaves avulsas recebem fundos na regtest e a
/// Iris varre tudo. A prova é o Bitcoin Core aceitar a transação (ele valida
/// cada assinatura por consenso). Roda dentro de scripts/regtest_canal.py.
///
/// IRIS_BITCOIND: http://usuario:senha@host:porta
/// IRIS_WIF_SEGWIT / IRIS_WIF_LEGADO: chaves de teste geradas pelo script.
void main() {
  final env = Platform.environment;
  final pronto = env['IRIS_BITCOIND'] != null;

  test('varre chave SegWit e chave legada, e o Bitcoin Core aceita', () async {
    final uri = Uri.parse(env['IRIS_BITCOIND']!);
    final auth = base64.encode(utf8.encode(uri.userInfo));
    Future<dynamic> rpc(String metodo, [List<dynamic> p = const [], String? carteira]) async {
      final r = await http.post(
        uri.replace(userInfo: '', path: carteira == null ? '/' : '/wallet/$carteira'),
        headers: {'Authorization': 'Basic $auth', 'Content-Type': 'application/json'},
        body: jsonEncode({'jsonrpc': '1.0', 'id': 'iris', 'method': metodo, 'params': p}),
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['error'] != null) throw Exception('$metodo: ${j['error']}');
      return j['result'];
    }

    final mina = await rpc('getnewaddress', [], 'mineradora') as String;
    final casos = {
      'wpkh': ChaveAvulsa.deWif(env['IRIS_WIF_SEGWIT']!),
      'pkh': ChaveAvulsa.deWif(env['IRIS_WIF_LEGADO']!),
    };
    final enderecos = <String, String>{};
    for (final e in casos.entries) {
      final desc = (await rpc('getdescriptorinfo',
          ['${e.key}(${paraHex(e.value.publica)})']))['descriptor'] as String;
      final addr = ((await rpc('deriveaddresses', [desc])) as List).first as String;
      enderecos[e.key] = addr;
      await rpc('sendtoaddress', [addr, 0.002], 'mineradora');
    }
    await rpc('generatetoaddress', [1, mina]);

    final destino = await rpc('getnewaddress', [], 'mineradora') as String;
    for (final e in casos.entries) {
      final scan = await rpc('scantxoutset', ['start', ['addr(${enderecos[e.key]})']]);
      final utxos = [
        for (final u in scan['unspents'] as List)
          Utxo(u['txid'] as String, u['vout'] as int,
              ((u['amount'] as num) * 1e8).round(), deHex(u['scriptPubKey'] as String)),
      ];
      expect(utxos, hasLength(1));
      final hex = varrer(
        chave: e.value,
        utxos: utxos,
        destino: scriptDeEndereco(destino, 'bcrt'),
        satsPorVbyte: 2,
      );
      final aceita = ((await rpc('testmempoolaccept', [
        [hex]
      ])) as List)
          .first as Map<String, dynamic>;
      expect(aceita['allowed'], isTrue,
          reason: '${e.key}: ${aceita['reject-reason']}');
      await rpc('sendrawtransaction', [hex]);
    }
    await rpc('generatetoaddress', [1, mina]);
    for (final e in casos.entries) {
      final resto = await rpc('scantxoutset', ['start', ['addr(${enderecos[e.key]})']]);
      expect(resto['unspents'], isEmpty, reason: '${e.key} ficou com saldo');
    }
  }, skip: pronto ? false : 'roda só dentro de scripts/regtest_canal.py');
}
