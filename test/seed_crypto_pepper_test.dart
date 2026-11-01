import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/seed_crypto.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// A cifra `enc2`/`v3` mistura um segredo do hardware (pepper) ao PIN. Estes
/// testes provam que, sem o pepper certo, um PIN de 6 dígitos não abre a
/// semente nem bate no hash — mesmo o PIN estando correto. É o que impede a
/// força bruta fora do aparelho.
void main() {
  const semente =
      'friend lonely sort layer poet grab upset change busy mistake this hello';
  const pin = '153624';
  final pepper = utf8.encode('segredo-do-keystore-32-bytes-aqui!');
  final outroPepper = utf8.encode('outro-aparelho-outro-segredo-aqui!');

  group('SeedCrypto', () {
    test('enc1 (só PIN) abre com o PIN e marca que não exige hardware',
        () async {
      final blob = await SeedCrypto.encrypt(semente, pin);
      expect(blob.startsWith('enc1\$'), isTrue);
      expect(SeedCrypto.exigeHardware(blob), isFalse);
      expect(await SeedCrypto.decrypt(blob, pin), semente);
    });

    test('enc2 (PIN + pepper) exige o pepper certo', () async {
      final blob = await SeedCrypto.encrypt(semente, pin, pepper: pepper);
      expect(blob.startsWith('enc2\$'), isTrue);
      expect(SeedCrypto.exigeHardware(blob), isTrue);
      // Com o pepper certo: abre.
      expect(await SeedCrypto.decrypt(blob, pin, pepper: pepper), semente);
    });

    test('enc2 com o PIN certo mas SEM o pepper não abre', () async {
      final blob = await SeedCrypto.encrypt(semente, pin, pepper: pepper);
      // Sem pepper: recusa de cara (não dá nem para tentar força bruta offline).
      expect(() => SeedCrypto.decrypt(blob, pin),
          throwsA(isA<SeedDecryptException>()));
      // Com o pepper de OUTRO aparelho: PIN certo, mas a chave é outra.
      expect(() => SeedCrypto.decrypt(blob, pin, pepper: outroPepper),
          throwsA(isA<SeedDecryptException>()));
    });

    test('todos os 1.000.000 de PINs falham sem o pepper (amostra)', () async {
      final blob = await SeedCrypto.encrypt(semente, pin, pepper: pepper);
      for (final p in ['000000', '153624', '999999', '123456']) {
        expect(() => SeedCrypto.decrypt(blob, p), throwsA(anything),
            reason: 'nenhum PIN abre enc2 sem o pepper, nem o correto');
      }
    });
  });

  group('hashPin', () {
    test('v2 sem pepper, v3 com pepper', () {
      expect(WalletService.hashPin(pin).startsWith('v2\$'), isTrue);
      expect(WalletService.hashPin(pin, pepper).startsWith('v3\$'), isTrue);
    });

    test('hash v3 só confere com o pepper certo', () {
      final h = WalletService.hashPin(pin, pepper);
      expect(WalletService.verifyPin(pin, h, pepper), isTrue);
      expect(WalletService.verifyPin(pin, h), isFalse); // sem pepper
      expect(WalletService.verifyPin(pin, h, outroPepper), isFalse);
      expect(WalletService.verifyPin('000000', h, pepper), isFalse);
    });

    test('hash v2 antigo ainda confere (migração) e pede atualização', () {
      final h = WalletService.hashPin(pin); // v2
      expect(WalletService.verifyPin(pin, h), isTrue);
      // Quando há pepper disponível, um v2 deve ser refeito como v3.
      expect(WalletService.precisaRefazerHash(h, temPepper: true), isTrue);
      expect(WalletService.precisaRefazerHash(h, temPepper: false), isFalse);
    });
  });
}
