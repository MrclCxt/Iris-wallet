import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// O hash do PIN não pode ser o atalho para a semente: mesmo custo da cifra
/// dela (200 mil iterações), sal novo a cada vez, e hashes antigos refeitos.
void main() {
  test('hash novo usa 200 mil iterações e sal aleatório', () async {
    final a = await WalletService.hashPinAsync('123456');
    final b = await WalletService.hashPinAsync('123456');
    expect(a.split('\$')[1], '200000');
    expect(a, isNot(b), reason: 'sal novo a cada hash');
  });

  test('confere o PIN certo e recusa o errado', () async {
    final h = await WalletService.hashPinAsync('123456');
    expect(await WalletService.verifyPinAsync('123456', h), isTrue);
    expect(await WalletService.verifyPinAsync('123457', h), isFalse);
  });

  test('hash antigo é detectado para ser refeito', () async {
    final legado = sha256.convert(utf8.encode('123456')).toString();
    expect(WalletService.precisaRefazerHash(legado), isTrue);
    expect(WalletService.precisaRefazerHash('v2\$20000\$00\$00'), isTrue);
    expect(WalletService.precisaRefazerHash(await WalletService.hashPinAsync('1')),
        isFalse);
    // O legado continua abrindo, para poder ser refeito no próximo acesso.
    expect(WalletService.verifyPin('123456', legado), isTrue);
  });
}
