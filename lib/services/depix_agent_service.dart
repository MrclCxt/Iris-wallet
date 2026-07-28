import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Onboarding automático de conta DePix via "agent accounts".
///
/// A identidade do agent é um par de chaves Ed25519 gerado e guardado SÓ no
/// dispositivo do usuário (a seed nunca sai daqui). Cada requisição aos
/// endpoints `/api/agents/*` é assinada — não há chave estática compartilhada,
/// e o Iris nunca detém a conta: quem a cria é o próprio usuário, com o `op_`
/// token que ele obteve conectando GitHub/Google no painel da DePix.
///
/// O resultado do registro é uma chave `sk_test_`/`sk_live_` que o
/// [DepixAppProvider] consome normalmente — este serviço só a provisiona.
class DepixAgentService {
  static const String host = 'api.depixapp.com';
  static const String baseUrl = 'https://api.depixapp.com';

  final FlutterSecureStorage _storage;
  final http.Client _client;

  ed.PrivateKey? _priv;
  ed.PublicKey? _pub;

  DepixAgentService({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  /// Garante que existe uma identidade de agent (gera na primeira vez e
  /// persiste a seed de 32 bytes no keystore nativo).
  Future<void> ensureIdentity() async {
    if (_priv != null && _pub != null) return;
    final seedHex = await _storage.read(key: 'depix_agent_seed');
    Uint8List seed;
    if (seedHex != null && seedHex.length == 64) {
      seed = _hexToBytes(seedHex);
    } else {
      final rnd = Random.secure();
      seed = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
      await _storage.write(key: 'depix_agent_seed', value: _bytesToHex(seed));
    }
    _priv = ed.newKeyFromSeed(seed);
    _pub = ed.public(_priv!);
  }

  /// Chave pública do agent (64 hex) — pode ser exibida ao usuário como a
  /// "impressão digital" da identidade dele.
  Future<String> publicKeyHex() async {
    await ensureIdentity();
    return _bytesToHex(_pub!.bytes);
  }

  /// Registra a conta de agent. [liquidAddress] é IMUTÁVEL após a criação —
  /// use um endereço da carteira Liquid não-custodial do próprio usuário, para
  /// que os depósitos DePix caiam direto no saldo dele.
  Future<AgentRegistration> register({
    required String name,
    required String operatorToken,
    required String operatorEmail,
    required String liquidAddress,
    String? username,
    String? callbackUrl,
  }) async {
    await ensureIdentity();
    const path = '/api/agents/register';
    final body = jsonEncode({
      'name': name,
      'operator_token': operatorToken,
      'operator_email': operatorEmail,
      'liquid_address': liquidAddress,
      if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
      if (callbackUrl != null && callbackUrl.trim().isNotEmpty)
        'default_callback_url': callbackUrl.trim(),
    });
    final r = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _signedHeaders('POST', path, body),
      body: body,
    );
    if (r.statusCode != 200 && r.statusCode != 201) _fail(r);
    return AgentRegistration.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Emite uma nova chave para o agent já registrado. `live: true` exige
  /// graduação (5 depósitos liquidados e maturados) — antes disso o servidor
  /// responde 403 `graduation_pending`.
  Future<AgentKey> createKey({
    bool live = false,
    List<String> scopes = const ['wallet_read', 'wallet_write'],
    String? label,
    int perTxLimitCents = 10000,
    int dailyLimitCents = 50000,
  }) async {
    await ensureIdentity();
    const path = '/api/agents/keys';
    final body = jsonEncode({
      'live': live,
      'scopes': scopes,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      'per_tx_limit_cents': perTxLimitCents,
      'daily_limit_cents': dailyLimitCents,
    });
    final r = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _signedHeaders('POST', path, body),
      body: body,
    );
    if (r.statusCode != 200 && r.statusCode != 201) _fail(r);
    return AgentKey.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  // --- Assinatura canônica (depix-agent-auth:v1) ---------------------------

  Map<String, String> _signedHeaders(String method, String path, String body) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final rnd = Random.secure();
    final nonce = _bytesToHex(
        Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256))));
    // SHA-256 do corpo BRUTO, em hex minúsculo.
    final bodyHash = crypto.sha256.convert(utf8.encode(body)).toString();
    final canonical = [
      'depix-agent-auth:v1',
      host,
      method.toUpperCase(),
      path, // sem query string
      ts,
      nonce,
      bodyHash,
    ].join('\n');
    final sig = ed.sign(_priv!, Uint8List.fromList(utf8.encode(canonical)));
    return {
      'Content-Type': 'application/json',
      'x-agent-public-key': _bytesToHex(_pub!.bytes),
      'x-agent-signature': _bytesToHex(sig),
      'x-agent-timestamp': ts,
      'x-agent-nonce': nonce,
    };
  }

  Never _fail(http.Response r) {
    String message = 'HTTP ${r.statusCode}';
    try {
      final data = jsonDecode(r.body);
      message = data['error']?['message']?.toString() ??
          data['message']?.toString() ??
          data['error']?.toString() ??
          message;
    } catch (_) {}
    throw Exception('DePix Agent: $message');
  }

  static String _bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

/// Chave emitida pela DePix (`sk_test_`/`sk_live_`), retornada em texto claro
/// UMA única vez.
class AgentKey {
  final String key;
  final String prefix; // 'sk_test_' | 'sk_live_'
  final bool isLive;
  final String scopes;
  final int? perTxLimitCents;
  final int? dailyLimitCents;
  final bool starter;

  AgentKey({
    required this.key,
    required this.prefix,
    required this.isLive,
    required this.scopes,
    this.perTxLimitCents,
    this.dailyLimitCents,
    this.starter = false,
  });

  factory AgentKey.fromJson(Map<String, dynamic> j) {
    final key = j['key']?.toString() ?? '';
    return AgentKey(
      key: key,
      prefix: j['prefix']?.toString() ??
          (key.startsWith('sk_live_') ? 'sk_live_' : 'sk_test_'),
      isLive: (j['is_live'] as bool?) ?? key.startsWith('sk_live_'),
      scopes: j['scopes']?.toString() ?? '',
      perTxLimitCents: (j['per_tx_limit_cents'] as num?)?.toInt(),
      dailyLimitCents: (j['daily_limit_cents'] as num?)?.toInt(),
      starter: (j['starter'] as bool?) ?? false,
    );
  }
}

/// Resposta do `POST /api/agents/register`.
class AgentRegistration {
  final String? username;
  final String? merchantId;
  final String? liquidAddress;
  final AgentKey? testKey;
  final AgentKey? liveStarterKey;

  AgentRegistration({
    this.username,
    this.merchantId,
    this.liquidAddress,
    this.testKey,
    this.liveStarterKey,
  });

  factory AgentRegistration.fromJson(Map<String, dynamic> j) {
    final agent = j['agent'] as Map<String, dynamic>?;
    final merchant = j['merchant'] as Map<String, dynamic>?;
    final keys = j['keys'] as Map<String, dynamic>?;
    AgentKey? parse(String slot) {
      final k = keys?[slot];
      if (k is Map<String, dynamic>) return AgentKey.fromJson(k);
      return null;
    }

    return AgentRegistration(
      username: agent?['username']?.toString(),
      merchantId: merchant?['id']?.toString(),
      liquidAddress: merchant?['liquid_address']?.toString(),
      testKey: parse('test'),
      liveStarterKey: parse('live_starter'),
    );
  }
}
