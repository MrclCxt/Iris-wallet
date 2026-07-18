import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bolt11.dart';

/// Suporte a LNURL-pay (LUD-06) e Lightning Address (LUD-16).
///
/// Fluxo: decodifica o LNURL/endereço -> GET nos parâmetros de pagamento ->
/// GET no callback com o valor escolhido -> recebe a fatura BOLT11 real.
class LnurlException implements Exception {
  final String message;
  LnurlException(this.message);
  @override
  String toString() => 'LnurlException: $message';
}

class LnurlPayParams {
  final String callback;
  final int minSendableMsat;
  final int maxSendableMsat;
  final String metadata;
  final String domain;

  LnurlPayParams({
    required this.callback,
    required this.minSendableMsat,
    required this.maxSendableMsat,
    required this.metadata,
    required this.domain,
  });

  int get minSendableSats => minSendableMsat ~/ 1000;
  int get maxSendableSats => maxSendableMsat ~/ 1000;
  bool get isFixedAmount => minSendableMsat == maxSendableMsat;

  /// Descrição legível extraída do metadata JSON (campo text/plain).
  String get description {
    try {
      final List<dynamic> meta = jsonDecode(metadata);
      for (final entry in meta) {
        if (entry is List && entry.length >= 2 && entry[0] == 'text/plain') {
          return entry[1].toString();
        }
      }
    } catch (_) {}
    return domain;
  }
}

class Lnurl {
  /// Detecta se a entrada é um LNURL ou Lightning Address.
  static bool looksLikeLnurl(String input) {
    final s = _sanitize(input);
    if (s.toLowerCase().startsWith('lnurl1')) return true;
    if (RegExp(r'^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$', caseSensitive: false)
        .hasMatch(s)) {
      return true;
    }
    return false;
  }

  static String _sanitize(String input) {
    var s = input.trim();
    for (final prefix in ['lightning:', 'LIGHTNING:', 'lnurlp://']) {
      if (s.startsWith(prefix)) s = s.substring(prefix.length);
    }
    return s;
  }

  /// Resolve o LNURL/endereço para a URL do endpoint payRequest.
  static String resolveUrl(String input) {
    final s = _sanitize(input);
    if (s.toLowerCase().startsWith('lnurl1')) {
      final (hrp, bytes) = Bolt11.decodeBech32(s);
      if (hrp != 'lnurl') throw LnurlException('Prefixo LNURL inválido: $hrp');
      return utf8.decode(bytes);
    }
    final match = RegExp(r'^([a-z0-9._%+-]+)@([a-z0-9.-]+\.[a-z]{2,})$',
            caseSensitive: false)
        .firstMatch(s);
    if (match != null) {
      final user = match.group(1)!;
      final domain = match.group(2)!;
      return 'https://$domain/.well-known/lnurlp/$user';
    }
    throw LnurlException('Entrada não é LNURL nem Lightning Address');
  }

  /// Busca os parâmetros de pagamento (LUD-06).
  static Future<LnurlPayParams> fetchPayParams(String input,
      {http.Client? client}) async {
    final url = resolveUrl(input);
    final uri = Uri.parse(url);
    final c = client ?? http.Client();
    try {
      final response = await c.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw LnurlException('Servidor LNURL respondeu ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data['status'] == 'ERROR') {
        throw LnurlException(data['reason']?.toString() ?? 'Erro no LNURL');
      }
      if (data['tag'] != 'payRequest') {
        throw LnurlException('LNURL não é um payRequest (tag=${data['tag']})');
      }
      return LnurlPayParams(
        callback: data['callback'] as String,
        minSendableMsat: (data['minSendable'] as num).toInt(),
        maxSendableMsat: (data['maxSendable'] as num).toInt(),
        metadata: data['metadata']?.toString() ?? '[]',
        domain: uri.host,
      );
    } finally {
      if (client == null) c.close();
    }
  }

  /// Solicita a fatura BOLT11 final para o valor escolhido (em msats).
  static Future<String> requestInvoice(LnurlPayParams params, int amountMsat,
      {http.Client? client}) async {
    if (amountMsat < params.minSendableMsat ||
        amountMsat > params.maxSendableMsat) {
      throw LnurlException(
          'Valor fora do intervalo permitido (${params.minSendableSats}-${params.maxSendableSats} sats)');
    }
    final sep = params.callback.contains('?') ? '&' : '?';
    final uri = Uri.parse('${params.callback}${sep}amount=$amountMsat');
    final c = client ?? http.Client();
    try {
      final response = await c.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw LnurlException('Callback LNURL respondeu ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data['status'] == 'ERROR') {
        throw LnurlException(data['reason']?.toString() ?? 'Erro no callback');
      }
      final pr = data['pr'] as String?;
      if (pr == null || !Bolt11.looksLikeInvoice(pr)) {
        throw LnurlException('Callback não retornou fatura BOLT11 válida');
      }
      return pr;
    } finally {
      if (client == null) c.close();
    }
  }
}
