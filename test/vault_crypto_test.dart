import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/vault_crypto.dart';

void main() {
  const seed =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const outraSeed =
      'legal winner thank year wave sausage worth useful legal winner '
      'thank yellow';

  test('round-trip: recupera o histórico com a mesma seed e conta', () async {
    final key = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final claro = jsonEncode([
      {'id': 'tx1', 'amountSats': 1000},
      {'id': 'tx2', 'amountSats': 297431},
    ]);

    final blob = await VaultCrypto.encrypt(claro, key);
    expect(VaultCrypto.isEncrypted(blob), isTrue);
    // O conteúdo não pode vazar em claro dentro do blob.
    expect(blob.contains('297431'), isFalse);

    expect(await VaultCrypto.decrypt(blob, key), claro);
  });

  test('chave de OUTRA conta não decifra (isolamento entre carteiras)',
      () async {
    final k1 = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final k2 = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-2');

    final blob = await VaultCrypto.encrypt('extrato secreto', k1);
    expect(await VaultCrypto.decrypt(blob, k2), isNull);
  });

  test('seed diferente não decifra', () async {
    final k1 = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final k2 =
        await VaultCrypto.deriveKey(seed: outraSeed, accountId: 'conta-1');

    final blob = await VaultCrypto.encrypt('extrato secreto', k1);
    expect(await VaultCrypto.decrypt(blob, k2), isNull);
  });

  test('blob adulterado falha na autenticação (GCM)', () async {
    final key = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final blob = await VaultCrypto.encrypt('extrato secreto', key);

    final p = blob.split('\$');
    // Corrompe um byte do ciphertext mantendo o base64 válido.
    final cipher = base64.decode(p[3]);
    cipher[0] = cipher[0] ^ 0xff;
    p[3] = base64.encode(cipher);

    expect(await VaultCrypto.decrypt(p.join('\$'), key), isNull);
  });

  test('mesma entrada gera blobs diferentes (nonce novo a cada cifragem)',
      () async {
    final key = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final a = await VaultCrypto.encrypt('mesmo texto', key);
    final b = await VaultCrypto.encrypt('mesmo texto', key);
    expect(a, isNot(equals(b)));
    expect(await VaultCrypto.decrypt(a, key), 'mesmo texto');
    expect(await VaultCrypto.decrypt(b, key), 'mesmo texto');
  });

  test('derivação é determinística (mesma seed+conta = mesma chave)', () async {
    final k1 = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final k2 = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    final blob = await VaultCrypto.encrypt('persistiu', k1);
    // Simula reabrir o app: chave rederivada do zero decifra o que ficou.
    expect(await VaultCrypto.decrypt(blob, k2), 'persistiu');
  });

  test('lixo não cifrado devolve null em vez de explodir', () async {
    final key = await VaultCrypto.deriveKey(seed: seed, accountId: 'conta-1');
    expect(await VaultCrypto.decrypt('nao é um blob', key), isNull);
    expect(await VaultCrypto.decrypt('vault1\$so\$duas', key), isNull);
    expect(VaultCrypto.isEncrypted(null), isFalse);
  });
}
