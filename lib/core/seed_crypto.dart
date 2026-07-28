import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Criptografia da seed BIP39 em repouso.
///
/// A seed nunca é gravada em texto puro. Ela é cifrada com AES-256-GCM usando
/// uma chave derivada do PIN do usuário via PBKDF2-HMAC-SHA256. Sem o PIN, o
/// conteúdo do armazenamento (mesmo extraído de um aparelho comprometido) não
/// revela a semente — o GCM ainda autentica a integridade (PIN errado = falha
/// de decifração, não texto lixo).
///
/// Formato do blob persistido (string única, campos separados por `$`):
///   enc1$<iterations>$<saltB64>$<nonceB64>$<macB64>$<cipherB64>
class SeedCrypto {
  static const String _prefix = 'enc1';

  /// PBKDF2 é puro-Dart e portável. Iterações altas encarecem o brute-force
  /// offline do PIN caso o ciphertext vaze. (Ajuste conforme o desempenho do
  /// alvo mais fraco.)
  static const int _iterations = 200000;
  static const int _saltBytes = 16;

  static final _aead = AesGcm.with256bits();

  /// True se [value] é um blob cifrado por este módulo.
  static bool isEncrypted(String? value) =>
      value != null && value.startsWith('$_prefix\$');

  /// Versões em ISOLATE das operações pesadas (PBKDF2 de 200k iterações).
  /// Rodar o KDF na thread principal congela a UI por centenas de ms — o
  /// usuário achava que o app travou ou que errou o PIN. Em um isolate, a UI
  /// segue respondendo (o indicador de "verificando" anima normalmente).
  static Future<String> decryptInBackground(String blob, String pin) =>
      Isolate.run(() => decrypt(blob, pin));

  static Future<String> encryptInBackground(String seed, String pin) =>
      Isolate.run(() => encrypt(seed, pin));

  static Future<SecretKey> _deriveKey(
      String pin, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt, // "nonce" do PBKDF2 = salt
    );
  }

  /// Cifra [seed] com uma chave derivada de [pin]. Retorna o blob persistível.
  static Future<String> encrypt(String seed, String pin) async {
    final rnd = SecretKeyData.random(length: _saltBytes).bytes;
    final salt = Uint8List.fromList(rnd);
    final key = await _deriveKey(pin, salt, _iterations);
    final nonce = AesGcm.with256bits().newNonce(); // 12 bytes aleatórios

    final box = await _aead.encrypt(
      utf8.encode(seed),
      secretKey: key,
      nonce: nonce,
    );

    return [
      _prefix,
      '$_iterations',
      base64.encode(salt),
      base64.encode(nonce),
      base64.encode(box.mac.bytes),
      base64.encode(box.cipherText),
    ].join('\$');
  }

  /// Decifra um blob produzido por [encrypt]. Lança [SeedDecryptException] se o
  /// PIN estiver errado ou o dado estiver corrompido/alterado.
  static Future<String> decrypt(String blob, String pin) async {
    final parts = blob.split('\$');
    if (parts.length != 6 || parts[0] != _prefix) {
      throw const SeedDecryptException('Formato de seed cifrada inválido.');
    }
    final iterations = int.tryParse(parts[1]) ?? _iterations;
    final salt = base64.decode(parts[2]);
    final nonce = base64.decode(parts[3]);
    final mac = base64.decode(parts[4]);
    final cipher = base64.decode(parts[5]);

    final key = await _deriveKey(pin, salt, iterations);
    try {
      final clear = await _aead.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      // MAC não confere: PIN errado ou dado adulterado.
      throw const SeedDecryptException('PIN incorreto.');
    }
  }
}

class SeedDecryptException implements Exception {
  final String message;
  const SeedDecryptException(this.message);
  @override
  String toString() => 'SeedDecryptException: $message';
}
