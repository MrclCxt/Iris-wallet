import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// O leitor de QR decide pelo formato se o código é um pagamento assinado
/// offline (para transmitir) ou outra coisa (fatura, Pix, endereço).
void main() {
  // Transação coinbase do bloco gênese (versão 1), um hex real e conhecido.
  const genese = '01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73ffffffff0100f2052a01000000434104678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac00000000';
  final segwit = '02000000${genese.substring(8)}';

  test('reconhece transação versão 1 e 2', () {
    expect(WalletService.ehTransacaoAssinada(genese), isTrue);
    expect(WalletService.ehTransacaoAssinada(segwit), isTrue);
    expect(WalletService.ehTransacaoAssinada(segwit.toUpperCase()), isTrue);
    expect(WalletService.ehTransacaoAssinada('  $segwit\n'), isTrue);
  });

  test('não confunde com outros códigos', () {
    expect(
        WalletService.ehTransacaoAssinada(
            '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000'),
        isFalse);
    expect(WalletService.ehTransacaoAssinada('lntb10u1p4w87h6dq5w3jhxar9'),
        isFalse);
    expect(
        WalletService.ehTransacaoAssinada(
            'tb1qknalcxsytxw8te4q7955932ft8cyeu3aljclg6'),
        isFalse);
    expect(WalletService.ehTransacaoAssinada('02000000'), isFalse);
    expect(WalletService.ehTransacaoAssinada('${segwit}0'), isFalse);
  });
}
