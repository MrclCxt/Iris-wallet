import 'dart:convert';
import 'dart:io';

/// Relay Nostr mínimo em memória (NIP-01: EVENT, REQ, CLOSE, EOSE, OK), para
/// os testes de troca não dependerem de relay público.
class RelayLocal {
  final HttpServer _servidor;
  final List<Map<String, dynamic>> _eventos = [];

  RelayLocal._(this._servidor) {
    _servidor.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = 400;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((bruto) => _tratar(ws, bruto as String));
    });
  }

  static Future<RelayLocal> iniciar() async =>
      RelayLocal._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String get url => 'ws://127.0.0.1:${_servidor.port}';

  Future<void> parar() => _servidor.close(force: true);

  void _tratar(WebSocket ws, String bruto) {
    final m = jsonDecode(bruto) as List;
    switch (m[0]) {
      case 'EVENT':
        final e = m[1] as Map<String, dynamic>;
        _eventos.add(e);
        ws.add(jsonEncode(['OK', e['id'], true, '']));
      case 'REQ':
        final sub = m[1];
        final filtro = m[2] as Map<String, dynamic>;
        final casam = _eventos.where((e) => _casa(e, filtro)).toList()
          ..sort((a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int));
        final limite = (filtro['limit'] as int?) ?? casam.length;
        for (final e in casam.take(limite)) {
          ws.add(jsonEncode(['EVENT', sub, e]));
        }
        ws.add(jsonEncode(['EOSE', sub]));
    }
  }

  static bool _casa(Map<String, dynamic> e, Map<String, dynamic> f) {
    if (f['kinds'] != null && !(f['kinds'] as List).contains(e['kind'])) return false;
    if (f['since'] != null && (e['created_at'] as int) < (f['since'] as int)) {
      return false;
    }
    for (final k in f.keys.where((k) => k.startsWith('#'))) {
      final nome = k.substring(1);
      final quer = (f[k] as List).cast<String>();
      final tem = (e['tags'] as List)
          .where((t) => (t as List).length > 1 && t[0] == nome)
          .map((t) => (t as List)[1] as String);
      if (!tem.any(quer.contains)) return false;
    }
    return true;
  }
}
