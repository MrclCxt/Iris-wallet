import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/address_validator.dart';

/// Validação de endereço do build da rede principal, onde um erro de
/// digitação é dinheiro de verdade perdido.
void main() {
  ResultadoEndereco v(String a) => AddressValidator.validarPrincipal(a);

  group('aceita', () {
    test('SegWit bc1q', () {
      final r = v('bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq');
      expect(r.valido, isTrue);
      expect(r.tipo, 'SegWit');
    });

    test('Taproot bc1p (vetor do BIP86)', () {
      final r = v(
          'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr');
      expect(r.valido, isTrue);
      expect(r.tipo, 'Taproot');
    });

    test('legado do bloco gênese', () {
      expect(v('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa').tipo, 'legado');
    });

    test('P2SH', () {
      expect(v('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy').tipo, 'script (P2SH)');
    });

    test('bech32 todo em maiúsculas', () {
      expect(v('BC1QAR0SRRR7XFKVY5L643LYDNW9RE59GTZZWF5MDQ').valido, isTrue);
    });
  });

  group('recusa', () {
    test('legado com um caractere trocado', () {
      expect(v('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb').valido, isFalse);
    });

    test('bech32 com um caractere trocado', () {
      expect(v('bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdx').valido, isFalse);
    });

    test('maiúsculas e minúsculas misturadas', () {
      expect(v('bc1qAR0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq').valido, isFalse);
    });

    test('endereço de testnet', () {
      expect(v('tb1qknalcxsytxw8te4q7955932ft8cyeu3aljclg6').valido, isFalse);
    });

    test('fatura Lightning no campo de endereço', () {
      expect(v('lnbc100n1pjxyz').valido, isFalse);
    });

    test('lixo', () {
      expect(v('meu endereco').valido, isFalse);
      expect(v('').valido, isFalse);
    });
  });
}
