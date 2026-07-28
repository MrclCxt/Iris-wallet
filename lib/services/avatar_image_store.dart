import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Guarda a foto de avatar de cada conta (pessoal ou loja) em arquivo.
///
/// Nome determinístico por conta (`avatar_<id>.jpg`) — ao contrário das fotos
/// de produto, só existe UM avatar por conta, então não precisa de referência
/// guardada em `AccountProfile`: a presença do arquivo já diz se há foto.
class AvatarImageStore {
  static String? _raiz;

  static Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/avatars');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _raiz = dir.path;
    } catch (e) {
      debugPrint('AvatarImageStore: falha ao preparar a pasta: $e');
    }
  }

  static String? caminhoDe(String accountId) {
    final raiz = _raiz;
    if (raiz == null || accountId.isEmpty) return null;
    return '$raiz/avatar_$accountId.jpg';
  }

  static bool existe(String accountId) {
    final caminho = caminhoDe(accountId);
    if (caminho == null) return false;
    try {
      return File(caminho).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Grava os bytes já enquadrados (mesmo pipeline do editor de foto de
  /// produto: 1:1, JPEG). Sobrescreve a foto anterior desta conta.
  static Future<bool> salvar(String accountId, Uint8List bytes) async {
    final caminho = caminhoDe(accountId);
    if (caminho == null) return false;
    try {
      await File(caminho).writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      debugPrint('AvatarImageStore: falha ao salvar: $e');
      return false;
    }
  }

  static Future<bool> salvarBase64(String accountId, String base64) async {
    try {
      return await salvar(accountId, base64Decode(base64));
    } catch (e) {
      debugPrint('AvatarImageStore: base64 inválido: $e');
      return false;
    }
  }

  static Future<Uint8List?> lerBytes(String accountId) async {
    final caminho = caminhoDe(accountId);
    if (caminho == null) return null;
    try {
      final arquivo = File(caminho);
      if (!await arquivo.exists()) return null;
      return await arquivo.readAsBytes();
    } catch (e) {
      debugPrint('AvatarImageStore: falha ao ler: $e');
      return null;
    }
  }

  static Future<void> remover(String accountId) async {
    final caminho = caminhoDe(accountId);
    if (caminho == null) return;
    try {
      final arquivo = File(caminho);
      if (await arquivo.exists()) await arquivo.delete();
    } catch (e) {
      debugPrint('AvatarImageStore: falha ao remover: $e');
    }
  }

  /// Apaga o avatar de uma conta removida (chamado ao apagar carteira/loja).
  static Future<void> apagarConta(String accountId) => remover(accountId);
}
