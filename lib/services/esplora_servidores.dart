import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/rede.dart';

/// Servidores Esplora de onde o nó lê a blockchain. O padrão mistura
/// operadores independentes; quem quiser põe o próprio servidor na frente.
/// Nenhum entra na lista sem provar que está na mesma rede que o app.
class EsploraServidores {
  static const List<String> padrao = Rede.esploraPadrao;

  static const String _chave = Rede.chaveEsploraProprios;

  // Último Esplora que realmente funcionou. Quando todos falham a verificação
  // (comum na testnet4, onde os servidores dão 429/timeout em rajadas), vale
  // mais tentar primeiro o que respondeu da última vez do que a ordem fixa.
  static const String _chaveUltimoBom = 'esplora_ultimo_bom_${Rede.nome}';

  static Future<String?> ultimoBom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final u = prefs.getString(_chaveUltimoBom);
      return (u != null && u.isNotEmpty) ? u : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _marcarBom(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chaveUltimoBom, url);
    } catch (_) {}
  }

  static String normalizar(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static bool formatoValido(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static Future<List<String>> personalizados() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_chave) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> salvarPersonalizados(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_chave, urls.map(normalizar).toSet().toList());
  }

  static Future<List<String>> candidatos() async {
    final lista = <String>[...await personalizados(), ...padrao];
    return lista.map(normalizar).toSet().toList();
  }

  /// Estado de um servidor: pronto, apenas ocupado (429 — passageiro, não vale
  /// insistir agora) ou fora do ar.
  static Future<({bool ok, bool limitado, String? motivo})> _checar(
      String base) async {
    try {
      final g = await http
          .get(Uri.parse('$base/block-height/0'))
          .timeout(const Duration(seconds: 15));
      if (g.statusCode == 429) {
        return (ok: false, limitado: true, motivo: 'ocupado (limite de requisições)');
      }
      // 2xx, não só 200: proxy de operadora móvel devolve 203 com o corpo
      // intacto (visto num Galaxy em 4G); o conteúdo é conferido abaixo.
      if (g.statusCode < 200 || g.statusCode > 299) {
        return (ok: false, limitado: false, motivo: 'não respondeu (HTTP ${g.statusCode})');
      }
      if (g.body.trim() != Rede.genesis) {
        return (ok: false, limitado: false, motivo: 'está em outra rede');
      }
      final f = await http
          .get(Uri.parse('$base/fee-estimates'))
          .timeout(const Duration(seconds: 15));
      if (f.statusCode == 429) {
        return (ok: false, limitado: true, motivo: 'ocupado (limite de requisições)');
      }
      if (f.statusCode < 200 || f.statusCode > 299 || !f.body.trimLeft().startsWith('{')) {
        return (ok: false, limitado: false, motivo: 'não informa taxas (HTTP ${f.statusCode})');
      }
      return (ok: true, limitado: false, motivo: null);
    } catch (e) {
      return (ok: false, limitado: false, motivo: 'fora do ar');
    }
  }

  /// `null` quando o servidor está pronto; senão, o motivo em linguagem simples.
  static Future<String?> verificar(String base) async {
    final r = await _checar(base);
    return r.ok ? null : r.motivo;
  }

  /// Ordena os candidatos pondo primeiro o que passar na verificação, para o nó
  /// não gastar uma tentativa de partida num servidor morto. Começa pelo último
  /// que funcionou. Faz 2 rodadas (os 429/timeout da testnet4 são passageiros)
  /// e não reinsiste num servidor que respondeu 429 — isso só pioraria o limite.
  static Future<List<String>> emOrdemDeUso() async {
    final base = await candidatos();
    final ultimo = await ultimoBom();
    final lista = <String>[
      if (ultimo != null && base.contains(ultimo)) ultimo,
      ...base.where((u) => u != ultimo),
    ];

    final limitados = <String>{};
    for (var rodada = 1; rodada <= 2; rodada++) {
      for (var i = 0; i < lista.length; i++) {
        if (limitados.contains(lista[i])) continue;
        final r = await _checar(lista[i]);
        if (r.ok) {
          debugPrint('Esplora escolhido: ${lista[i]}');
          await _marcarBom(lista[i]);
          return [...lista.sublist(i), ...lista.sublist(0, i)];
        }
        if (r.limitado) limitados.add(lista[i]);
        debugPrint('Esplora ${lista[i]} ${r.motivo}; tentando outro.');
      }
      if (rodada < 2 && limitados.length < lista.length) {
        await Future.delayed(const Duration(seconds: 4));
      }
    }
    debugPrint('Nenhum Esplora passou; tentando na ordem (último bom na frente).');
    return lista;
  }
}
