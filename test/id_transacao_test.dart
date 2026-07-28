import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// O mesmo txid circula pelo app em três grafias:
///
///   - lista de bytes crua, `[99,178,...]` (o `.toString()` do PaymentId);
///   - hex na ordem interna;
///   - hex invertido — a ordem de exibição convencional, que é a que
///     `node_backend._idDePagamento` produz hoje para on-chain.
///
/// Ordem de bytes é convenção de escrita, não identidade. Sem tratar as três
/// como a mesma transação, uma linha gravada por versão antiga e a linha vinda
/// do nó viram duas entradas no histórico — foi a duplicata que o usuário viu:
/// mesmo título, mesmo valor, só o status divergindo.
void main() {
  // txid real do caso reportado (3.049 sats).
  const hexExibicao =
      '63b3fd43e623b49aec440fa0113ce4a9f59ab404cffd70d637916e1c672d055a';

  String inverterHex(String hex) {
    final bytes = [
      for (var i = 0; i < hex.length; i += 2)
        hex.substring(i, i + 2),
    ];
    return bytes.reversed.join();
  }

  test('hex e seu inverso designam a MESMA transação', () {
    final interno = inverterHex(hexExibicao);
    expect(interno, isNot(hexExibicao), reason: 'as grafias devem diferir');

    expect(
      WalletService.idCanonico(hexExibicao),
      WalletService.idCanonico(interno),
    );
  });

  test('a chave é estável: canonizar duas vezes não muda nada', () {
    final uma = WalletService.idCanonico(hexExibicao);
    expect(WalletService.idCanonico(uma), uma);
  });

  test('lista de bytes casa com o hex correspondente', () {
    final bytes = [
      for (var i = 0; i < hexExibicao.length; i += 2)
        int.parse(hexExibicao.substring(i, i + 2), radix: 16)
    ];
    final comoLista = '[${bytes.join(', ')}]';

    expect(
      WalletService.idCanonico(comoLista),
      WalletService.idCanonico(hexExibicao),
    );
  });

  test('transações diferentes continuam diferentes', () {
    const outro =
        '0000000000000000000000000000000000000000000000000000000000000001';
    expect(
      WalletService.idCanonico(outro),
      isNot(WalletService.idCanonico(hexExibicao)),
    );
  });

  test('id que não é txid passa intacto (hash Lightning curto, id sintético)',
      () {
    expect(WalletService.idCanonico('onchain_123'), 'onchain_123');
    expect(WalletService.idCanonico(''), '');
  });
}
