import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Guarda as fotos dos produtos em arquivo, separadas por loja.
///
/// Por que não dentro do produto (base64 no SharedPreferences): o catálogo
/// inteiro é gravado de uma vez, e uma foto tem centenas de KB. Isso
/// atravessaria o canal de método a cada salvamento e travaria o app. Em
/// arquivo, o catálogo continua sendo um JSON pequeno com o nome do arquivo.
///
/// Por que uma pasta por loja: contas são separadas. Com pasta única, a
/// limpeza de órfãs da loja ativa apagava as fotos das outras lojas, porque
/// nenhum produto dela as referenciava.
///
/// O produto guarda só o NOME do arquivo — nunca o caminho absoluto, que muda
/// entre instalações no Android e deixaria toda foto quebrada após atualizar.
class ProductImageStore {
  static String? _raiz;
  static String? _lojaAtual;

  /// Chamado uma vez no start do app, antes do primeiro build.
  static Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/product_images');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _raiz = dir.path;
    } catch (e) {
      debugPrint('ProductImageStore: falha ao preparar a pasta: $e');
    }
  }

  /// Aponta o armazenamento para a loja ativa. Sem loja, nada é lido ou salvo.
  static void definirLoja(String? merchantId) {
    _lojaAtual = (merchantId == null || merchantId.isEmpty) ? null : merchantId;
  }

  static String? get _pasta {
    final raiz = _raiz;
    final loja = _lojaAtual;
    if (raiz == null || loja == null) return null;
    return '$raiz/$loja';
  }

  static bool get pronto => _pasta != null;

  /// Caminho completo a partir do nome guardado no produto.
  static String? caminhoDe(String? nomeArquivo) {
    final base = _pasta;
    if (base == null || nomeArquivo == null || nomeArquivo.isEmpty) return null;
    return '$base/$nomeArquivo';
  }

  static Future<Directory?> _garantirPasta() async {
    final base = _pasta;
    if (base == null) return null;
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Grava os bytes já enquadrados. Devolve o nome do arquivo, ou null se não
  /// conseguiu gravar.
  static Future<String?> salvar(Uint8List bytes, {String extensao = 'jpg'}) async {
    try {
      final dir = await _garantirPasta();
      if (dir == null) return null;
      final ext = extensao.replaceAll('.', '').toLowerCase();
      final nome = 'p_${DateTime.now().microsecondsSinceEpoch}.$ext';
      await File('${dir.path}/$nome').writeAsBytes(bytes, flush: true);
      return nome;
    } catch (e) {
      debugPrint('ProductImageStore: falha ao salvar: $e');
      return null;
    }
  }

  static Future<Uint8List?> lerBytes(String? nomeArquivo) async {
    final caminho = caminhoDe(nomeArquivo);
    if (caminho == null) return null;
    try {
      final arquivo = File(caminho);
      if (!await arquivo.exists()) return null;
      return await arquivo.readAsBytes();
    } catch (e) {
      debugPrint('ProductImageStore: falha ao ler: $e');
      return null;
    }
  }

  /// True se o arquivo realmente existe. A tela usa isto para não oferecer
  /// "trocar/remover" de uma foto que sumiu do disco.
  static bool existe(String? nomeArquivo) {
    final caminho = caminhoDe(nomeArquivo);
    if (caminho == null) return false;
    try {
      return File(caminho).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> remover(String? nomeArquivo) async {
    final caminho = caminhoDe(nomeArquivo);
    if (caminho == null) return;
    try {
      final arquivo = File(caminho);
      if (await arquivo.exists()) await arquivo.delete();
    } catch (e) {
      debugPrint('ProductImageStore: falha ao remover: $e');
    }
  }

  /// Grava uma foto recebida na importação de catálogo.
  static Future<String?> salvarBase64(String base64, {String extensao = 'jpg'}) async {
    try {
      return await salvar(base64Decode(base64), extensao: extensao);
    } catch (e) {
      debugPrint('ProductImageStore: base64 inválido: $e');
      return null;
    }
  }

  /// Apaga fotos que nenhum produto DA LOJA ATUAL referencia. Só varre a pasta
  /// da loja ativa — nunca toca no material das outras.
  static Future<void> limparOrfaos(Set<String> emUso) async {
    final base = _pasta;
    if (base == null) return;
    try {
      final dir = Directory(base);
      if (!await dir.exists()) return;
      await for (final entidade in dir.list()) {
        if (entidade is! File) continue;
        final nome = entidade.uri.pathSegments.last;
        if (!emUso.contains(nome)) {
          await entidade.delete();
        }
      }
    } catch (e) {
      debugPrint('ProductImageStore: falha ao limpar órfãos: $e');
    }
  }

  /// Apaga a pasta inteira de uma loja removida.
  static Future<void> apagarLoja(String merchantId) async {
    final raiz = _raiz;
    if (raiz == null) return;
    try {
      final dir = Directory('$raiz/$merchantId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('ProductImageStore: falha ao apagar loja: $e');
    }
  }

  /// Move para a pasta da loja ativa as fotos que ficaram soltas na raiz —
  /// resquício da versão que usava pasta única. Só migra as que a loja atual
  /// realmente referencia, para não roubar foto de outra loja.
  static Future<void> migrarDaRaiz(Set<String> referenciadas) async {
    final raiz = _raiz;
    final base = _pasta;
    if (raiz == null || base == null || referenciadas.isEmpty) return;
    try {
      for (final nome in referenciadas) {
        final solta = File('$raiz/$nome');
        if (!await solta.exists()) continue;
        await _garantirPasta();
        await solta.rename('$base/$nome');
        debugPrint('ProductImageStore: foto $nome migrada para a loja atual.');
      }
    } catch (e) {
      debugPrint('ProductImageStore: falha ao migrar da raiz: $e');
    }
  }
}
