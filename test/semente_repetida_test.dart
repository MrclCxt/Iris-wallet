import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/wallet_service.dart';

const _semente =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

void main() {
  AccountProfile conta(String nome, {String seed = '', String? seedFp}) =>
      AccountProfile(
          id: nome, name: nome, seed: seed, seedFp: seedFp, pinHash: 'x');

  test('reconhece semente de conta destrancada, mesmo com outra grafia', () {
    final contas = [conta('A', seed: _semente)];
    final achada = WalletService.contaComMesmaSemente(
        contas, '  ${_semente.toUpperCase().replaceAll(' ', '   ')} ');
    expect(achada?.name, 'A');
  });

  test('reconhece conta trancada pela impressão, que sobrevive à gravação', () {
    final fp = sha256.convert(utf8.encode(_semente)).toString().substring(0, 16);
    final gravada = AccountProfile.fromJson(conta('A', seedFp: fp).toJson());
    expect(gravada.seed, isEmpty);
    expect(WalletService.contaComMesmaSemente([gravada], _semente)?.name, 'A');
  });

  test('semente diferente passa', () {
    final contas = [conta('A', seed: _semente)];
    expect(
        WalletService.contaComMesmaSemente(
            contas, 'abandon abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon about'),
        isNull);
  });

  test('conta trancada de contas antigas, sem impressão, não bloqueia', () {
    expect(
        WalletService.contaComMesmaSemente([conta('A')], _semente), isNull);
  });
}
