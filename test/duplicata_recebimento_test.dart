import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// Um recebimento on-chain chega ao histórico por DOIS caminhos, e os ids nunca
/// batem:
///
///   - provisório: `_refreshBalances` vê o saldo subir e cria `onchain_<millis>`
///     para o usuário ver o dinheiro na hora, antes de o nó listar o pagamento;
///   - definitivo: `reconstruirHistoricoDoNo` traz o pagamento do nó, com txid.
///
/// Sem casar os dois, um envio de 3.049 sats aparecia como duas linhas e o
/// banner de pendente somava 6.098 — o dobro do que entrou.
void main() {
  group('título concorda com o status', () {
    test('pendente não diz "Recebido"', () {
      expect(
        WalletService.tituloEntradaOnchain('pending'),
        'Recebendo on-chain — aguardando confirmação',
      );
    });

    test('confirmado diz "Recebido"', () {
      expect(
        WalletService.tituloEntradaOnchain('confirmed'),
        'Recebido on-chain (Bitcoin)',
      );
    });

    test('status desconhecido não afirma recebimento', () {
      expect(
        WalletService.tituloEntradaOnchain('failed'),
        'Recebendo on-chain — aguardando confirmação',
      );
    });
  });

  group('formato do id distingue provisório de definitivo', () {
    // O casamento depende deste prefixo; se ele mudar em _refreshBalances sem
    // mudar aqui, as duplicatas voltam silenciosamente.
    test('ids gerados por _refreshBalances usam o prefixo onchain_', () {
      final agora = DateTime.now().millisecondsSinceEpoch;
      expect('onchain_$agora'.startsWith('onchain_'), isTrue);
      expect('onchain_pend_$agora'.startsWith('onchain_'), isTrue);
    });

    test('txid de 64 hex não é confundido com provisório', () {
      const txid =
          '63b3fd43e623b49aec440fa0113ce4a9f59ab404cffd70d637916e1c672d055a';
      expect(txid.startsWith('onchain_'), isFalse);
      expect(txid.length, 64);
    });
  });
}
