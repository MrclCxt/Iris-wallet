import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/rede.dart';
import 'esplora_servidores.dart';
import 'node_backend.dart';

/// Taxa da rede consultada pelo app, não pelo nó: o nó, quando a estimativa
/// falha (proxy de operadora, servidor fora), cai num valor fixo de 20 sat/vB
/// — foi assim que um envio de 5.000 sats pagou 8.250 de taxa. Aqui a taxa
/// vem de vários servidores (mediana) e, sem nenhuma resposta, o envio é
/// recusado em vez de inventar um valor.
class TaxaRede {
  static String get _chaveCache => 'taxa_rede_${Rede.nome}';

  /// sat/vB para confirmar em ~6 blocos (econômico) e ~2 blocos (rápido).
  static Future<({double economico, double rapido})?> consultar() async {
    final servidores = <String>{
      if (EmbeddedNodeApi.esploraEmUso != null) EmbeddedNodeApi.esploraEmUso!,
      ...await EsploraServidores.candidatos(),
    }.take(3);
    final respostas = await Future.wait(servidores.map(_ler));
    final validas = respostas.whereType<Map<String, dynamic>>().toList();
    if (validas.isEmpty) return null;
    double mediana(String alvo, String reserva) {
      final v = [
        for (final r in validas)
          ((r[alvo] ?? r[reserva]) as num?)?.toDouble()
      ].whereType<double>().where((x) => x > 0).toList()
        ..sort();
      if (v.isEmpty) return 0;
      return v[v.length ~/ 2];
    }

    final economico = mediana('6', '3');
    final rapido = mediana('2', '1');
    if (economico <= 0) return null;
    final r = (economico: economico, rapido: rapido > 0 ? rapido : economico);
    try {
      await (await SharedPreferences.getInstance())
          .setDouble(_chaveCache, r.economico);
    } catch (_) {}
    return r;
  }

  /// Última taxa econômica que funcionou (para assinar sem internet).
  static Future<double?> ultimaConhecida() async {
    try {
      return (await SharedPreferences.getInstance()).getDouble(_chaveCache);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _ler(String base) async {
    try {
      final r = await http
          .get(Uri.parse('$base/fee-estimates'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode < 200 || r.statusCode > 299) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// sat/vB → sat/kWU (unidade que o nó recebe; aceita frações de sat/vB).
  static int paraKwu(double satPorVbyte) => (satPorVbyte * 250).ceil();

  /// Conselho para a tela: a taxa é aceitável, pesada ou maior que o valor.
  static String? alerta({required int taxa, required int valor}) {
    if (taxa >= valor) {
      return 'A taxa da rede ($taxa sats) é maior que o valor enviado. '
          'Use Lightning ou envie um valor maior.';
    }
    if (taxa * 10 > valor) {
      final pct = (taxa * 100 / valor).toStringAsFixed(0);
      return 'A taxa da rede é $pct% do valor. Para valores pequenos, '
          'Lightning sai quase de graça.';
    }
    return null;
  }
}
