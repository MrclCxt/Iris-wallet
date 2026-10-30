import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/taxa_rede.dart';

/// O alerta de taxa: o que o usuário lê antes de confirmar um envio on-chain.
void main() {
  test('taxa maior que o valor bloqueia e sugere Lightning', () {
    expect(TaxaRede.alerta(taxa: 8250, valor: 5000), contains('maior que o valor'));
  });

  test('taxa acima de 10% avisa com a porcentagem', () {
    expect(TaxaRede.alerta(taxa: 1500, valor: 10000), contains('15%'));
  });

  test('taxa razoável não incomoda', () {
    expect(TaxaRede.alerta(taxa: 300, valor: 100000), isNull);
  });

  test('sat/vB vira sat/kWU arredondando para cima (nunca abaixo do pedido)', () {
    expect(TaxaRede.paraKwu(1), 250);
    expect(TaxaRede.paraKwu(0.1), 25);
    expect(TaxaRede.paraKwu(10.01), 2503);
  });
}
