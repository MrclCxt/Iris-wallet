import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/seed_crypto.dart';

void main() {
  const seed =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const pin = '135790';

  test('round-trip: decifra de volta a mesma seed com o PIN certo', () async {
    final blob = await SeedCrypto.encrypt(seed, pin);
    expect(SeedCrypto.isEncrypted(blob), isTrue);
    expect(blob.contains(seed), isFalse); // seed não aparece em claro no blob
    final back = await SeedCrypto.decrypt(blob, pin);
    expect(back, seed);
  });

  test('PIN errado falha (não retorna lixo)', () async {
    final blob = await SeedCrypto.encrypt(seed, pin);
    expect(
      () => SeedCrypto.decrypt(blob, '000000'),
      throwsA(isA<SeedDecryptException>()),
    );
  });

  test('blob adulterado falha na autenticação', () async {
    final blob = await SeedCrypto.encrypt(seed, pin);
    // corrompe o último caractere do ciphertext
    final tampered = blob.substring(0, blob.length - 2) +
        (blob.endsWith('A') ? 'B' : 'A') +
        blob.substring(blob.length - 1);
    expect(
      () => SeedCrypto.decrypt(tampered, pin),
      throwsA(isA<SeedDecryptException>()),
    );
  });

  test('cada cifragem usa salt/nonce novos (blobs diferentes)', () async {
    final a = await SeedCrypto.encrypt(seed, pin);
    final b = await SeedCrypto.encrypt(seed, pin);
    expect(a, isNot(equals(b)));
  });

  test('isEncrypted distingue texto puro de blob', () {
    expect(SeedCrypto.isEncrypted(seed), isFalse);
    expect(SeedCrypto.isEncrypted(null), isFalse);
    expect(SeedCrypto.isEncrypted('enc1\$x'), isTrue);
  });
}
