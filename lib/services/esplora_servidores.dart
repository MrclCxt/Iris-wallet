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

  /// `null` quando o servidor está pronto; senão, o motivo em linguagem simples.
  static Future<String?> verificar(String base) async {
    try {
      final g = await http
          .get(Uri.parse('$base/block-height/0'))
          .timeout(const Duration(seconds: 10));
      // 2xx, não só 200: proxy de operadora móvel devolve 203 com o corpo
      // intacto (visto num Galaxy em 4G); o conteúdo é conferido abaixo.
      if (g.statusCode < 200 || g.statusCode > 299) {
        return 'não respondeu (HTTP ${g.statusCode})';
      }
      if (g.body.trim() != Rede.genesis) return 'está em outra rede';
      final f = await http
          .get(Uri.parse('$base/fee-estimates'))
          .timeout(const Duration(seconds: 10));
      if (f.statusCode < 200 || f.statusCode > 299 || !f.body.trimLeft().startsWith('{')) {
        return 'não informa taxas (HTTP ${f.statusCode})';
      }
      return null;
    } catch (e) {
      return 'fora do ar';
    }
  }

  /// Ordena os candidatos pondo primeiro o primeiro que passar na verificação,
  /// para o nó não gastar uma tentativa de partida num servidor morto.
  static Future<List<String>> emOrdemDeUso() async {
    final lista = await candidatos();
    for (var i = 0; i < lista.length; i++) {
      final motivo = await verificar(lista[i]);
      if (motivo == null) {
        debugPrint('Esplora escolhido: ${lista[i]}');
        return [...lista.sublist(i), ...lista.sublist(0, i)];
      }
      debugPrint('Esplora ${lista[i]} $motivo; tentando outro.');
    }
    debugPrint('Nenhum Esplora passou na verificação; tentando na ordem.');
    return lista;
  }
}
