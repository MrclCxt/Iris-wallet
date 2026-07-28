import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class VaultCrypto {
  static const String _prefix = 'vault1';
  static final _aead = AesGcm.with256bits();

  static const String _salt = 'iris-wallet-vault-v1';

  static bool isEncrypted(String? v) => v != null && v.startsWith('$_prefix\$');

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
