import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Criptografia de dados do app em repouso (histórico de transações).
///
/// Diferença importante para [SeedCrypto]: aqui a chave é derivada da SEMENTE
/// da carteira, não do PIN. Dois motivos:
///
///  - **Trocar o PIN não obriga a recifrar o histórico inteiro.** A seed é o
///    segredo estável da carteira; o PIN é só o que protege a seed em disco.
///  - **É barato.** A seed BIP39 já tem 128–256 bits de entropia, então basta
///    um HKDF (uma passada de HMAC) em vez das 200 mil iterações de PBKDF2 que
///    o PIN exige por ser de baixa entropia. Isso permite salvar a cada nova
///    transação sem travar a UI.
///
/// Cada conta recebe uma chave própria (via `info` do HKDF): o histórico de uma
/// carteira não pode ser decifrado com a chave de outra, mesmo no mesmo
/// aparelho e com a mesma semente.
///
/// Formato do blob: `vault1$<nonceB64>$<macB64>$<cipherB64>`
class VaultCrypto {
  static const String _prefix = 'vault1';
  static final _aead = AesGcm.with256bits();

  /// Salt fixo do app. Não precisa ser secreto nem aleatório por instalação:
  /// a entropia toda vem da semente. Serve para separar o domínio desta chave
  /// de qualquer outro uso futuro da mesma seed.
  static const String _salt = 'iris-wallet-vault-v1';

  static bool isEncrypted(String? v) =>
      v != null && v.startsWith('$_prefix\$');

  /// Deriva a chave de uma conta a partir da semente. Rápido de propósito —
  /// ver a explicação na doc da classe.
  static Future<SecretKey> deriveKey({
    required String seed,
    required String accountId,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(seed)),
      nonce: utf8.encode(_salt),
      info: utf8.encode('tx-history:$accountId'),
    );
  }

  static Future<String> encrypt(String plaintext, SecretKey key) async {
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return [
      _prefix,
      base64.encode(nonce),
      base64.encode(box.mac.bytes),
      base64.encode(box.cipherText),
    ].join('\$');
  }

  /// Devolve null se o blob for inválido ou a chave não conferir — histórico
  /// ilegível não é motivo para derrubar o app, só para começar vazio.
  static Future<String?> decrypt(String blob, SecretKey key) async {
    final p = blob.split('\$');
    if (p.length != 4 || p[0] != _prefix) return null;
    try {
      final clear = await _aead.decrypt(
        SecretBox(
          base64.decode(p[3]),
          nonce: base64.decode(p[1]),
          mac: Mac(base64.decode(p[2])),
        ),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      return null;
    }
  }
}
