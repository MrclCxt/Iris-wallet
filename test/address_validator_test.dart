import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/address_validator.dart';

void main() {
  group('endereços válidos da testnet', () {
    test('aceita P2WPKH real da carteira do usuário', () {
      final r = AddressValidator.validarTestnet(
          'tb1qknalcxsytxw8te4q7955932ft8cyeu3aljclg6');
      expect(r.valido, isTrue);
      expect(r.tipo, contains('SegWit'));
    });

    test('aceita outro P2WPKH real', () {
      expect(
          AddressValidator.validarTestnet(
                  'tb1qdyzkzm27kl6n9y7zujwqqkd7cln365gtphwq4j')
              .valido,
          isTrue);
    });

    test('aceita maiúsculas e espaços nas pontas', () {
      expect(
          AddressValidator.validarTestnet(
                  '  TB1QKNALCXSYTXW8TE4Q7955932FT8CYEU3ALJCLG6  ')
              .valido,
          isTrue);
    });

    test('aceita Taproot (bech32m)', () {
      final r = AddressValidator.validarTestnet(
          'tb1pe860mcf3zfrp3g60mt9htj0nparzgg52fnxc9d49wh4wdevasw9qed4zhc');
      expect(r.valido, isTrue);
      expect(r.tipo, contains('Taproot'));
    });
  });

  group('bloqueios que evitam perda de fundos', () {
    test('recusa endereço de mainnet bech32', () {
      final r = AddressValidator.validarTestnet(
          'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq');
      expect(r.valido, isFalse);
      expect(r.motivo, contains('rede principal'));
    });

    test('recusa endereço de mainnet legado', () {
      final r =
          AddressValidator.validarTestnet('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa');
      expect(r.valido, isFalse);
      expect(r.motivo, contains('rede principal'));
    });

    test('recusa regtest', () {
      expect(
          AddressValidator.validarTestnet(
                  'bcrt1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080')
              .valido,
          isFalse);
    });

    test('recusa fatura Lightning colada no campo on-chain', () {
      final r = AddressValidator.validarTestnet('lntb100n1pjxyz');
      expect(r.valido, isFalse);
      expect(r.motivo, contains('Lightning'));
    });
  });

  group('erros de digitação', () {
    test('pega um caractere trocado (checksum falha)', () {
      final r = AddressValidator.validarTestnet(
          'tb1qknalcxsytxw8te4q7955932ft8cyeu3aljclg7');
      expect(r.valido, isFalse);
      expect(r.motivo, contains('integridade'));
    });

    test('pega caractere fora do alfabeto bech32', () {
      final r = AddressValidator.validarTestnet(
          'tb1qbnalcxsytxw8te4q7955932ft8cyeu3aljclg6');
      expect(r.valido, isFalse);
      expect(r.motivo, isNotNull);
    });

    test('recusa endereço truncado', () {
      expect(AddressValidator.validarTestnet('tb1qknalcx').valido, isFalse);
    });

    test('recusa vazio', () {
      expect(AddressValidator.validarTestnet('').valido, isFalse);
      expect(AddressValidator.validarTestnet('   ').valido, isFalse);
    });

    test('recusa endereço com espaço no meio', () {
      final r = AddressValidator.validarTestnet(
          'tb1qknalcxsytxw8te4 q7955932ft8cyeu3aljclg6');
      expect(r.valido, isFalse);
      expect(r.motivo, contains('espaços'));
    });

    test('recusa texto qualquer', () {
      expect(AddressValidator.validarTestnet('meu endereco').valido, isFalse);
      expect(AddressValidator.validarTestnet('12345').valido, isFalse);
    });
  });
}
