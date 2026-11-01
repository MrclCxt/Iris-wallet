import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Cifra da semente.
///
/// `enc1$` — chave derivada só do PIN (PBKDF2-SHA256, 200k). Usada no desktop,
/// onde não há Keystore de hardware, e em instalações antigas.
///
/// `enc2$` — chave derivada do PIN **mais um segredo do hardware** (um HMAC
/// calculado por uma chave não-exportável do Android Keystore/StrongBox; ver
/// [Dispositivo.pepper]). Sem o aparelho, não dá para derivar a chave: um PIN
/// de 6 dígitos deixa de ser quebrável por força bruta fora do celular, mesmo
/// que o blob cifrado vaze. A migração de `enc1`→`enc2` acontece no primeiro
/// desbloqueio após a atualização.
class SeedCrypto {
  static const String _prefixPin = 'enc1';
  static const String _prefixHw = 'enc2';

  static const int _iterations = 200000;
  static const int _saltBytes = 16;

  static final _aead = AesGcm.with256bits();

  static bool isEncrypted(String? value) =>
      value != null &&
      (value.startsWith('$_prefixPin\$') || value.startsWith('$_prefixHw\$'));

  /// `true` quando o blob exige o segredo do hardware (`enc2`).
  static bool exigeHardware(String? value) =>
      value != null && value.startsWith('$_prefixHw\$');

  static Future<String> decryptInBackground(String blob, String pin,
          {List<int>? pepper}) =>
      Isolate.run(() => decrypt(blob, pin, pepper: pepper));

  static Future<String> encryptInBackground(String seed, String pin,
          {List<int>? pepper}) =>
      Isolate.run(() => encrypt(seed, pin, pepper: pepper));

  // O PIN e o segredo do hardware entram juntos no PBKDF2. Sem o segundo,
  // derivar a chave fora do aparelho é impossível.
  static List<int> _segredo(String pin, List<int>? pepper) =>
      pepper == null ? utf8.encode(pin) : [...utf8.encode(pin), ...pepper];

  static Future<SecretKey> _deriveKey(
      String pin, List<int>? pepper, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(_segredo(pin, pepper)),
      nonce: salt,
    );
  }

  static Future<String> encrypt(String seed, String pin,
      {List<int>? pepper}) async {
    final rnd = SecretKeyData.random(length: _saltBytes).bytes;
    final salt = Uint8List.fromList(rnd);
    final key = await _deriveKey(pin, pepper, salt, _iterations);
    final nonce = AesGcm.with256bits().newNonce();

    final box = await _aead.encrypt(
      utf8.encode(seed),
      secretKey: key,
      nonce: nonce,
    );

    return [
      pepper == null ? _prefixPin : _prefixHw,
      '$_iterations',
      base64.encode(salt),
      base64.encode(nonce),
      base64.encode(box.mac.bytes),
      base64.encode(box.cipherText),
    ].join('\$');
  }

  static Future<String> decrypt(String blob, String pin,
      {List<int>? pepper}) async {
    final parts = blob.split('\$');
    if (parts.length != 6 ||
        (parts[0] != _prefixPin && parts[0] != _prefixHw)) {
      throw const SeedDecryptException('Formato de seed cifrada inválido.');
    }
    if (parts[0] == _prefixHw && pepper == null) {
      throw const SeedDecryptException(
          'Esta carteira exige o segredo do aparelho para abrir.');
    }
    // Um blob só-PIN (enc1) nunca usa o segredo do hardware, mesmo que ele
    // exista: senão a migração nunca conseguiria lê-lo para reescrever.
    final pepperDaCifra = parts[0] == _prefixHw ? pepper : null;
    final iterations = int.tryParse(parts[1]) ?? _iterations;
    final salt = base64.decode(parts[2]);
    final nonce = base64.decode(parts[3]);
    final mac = base64.decode(parts[4]);
    final cipher = base64.decode(parts[5]);

    final key = await _deriveKey(pin, pepperDaCifra, salt, iterations);
    try {
      final clear = await _aead.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
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
