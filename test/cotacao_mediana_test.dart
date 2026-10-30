import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/cotacao.dart';

/// Contrato da cotação BTC/BRL: o preço que converte Real em sats na hora de
/// cobrar ou pagar vem do consenso de fontes independentes, nunca de uma só.
void main() {
  test('três fontes coerentes: usa a mediana', () {
    expect(cotacaoDeConsenso([414805, 416629, 416941]), 416629);
  });

  test('uma fonte adulterada em +10% é descartada', () {
    final c = cotacaoDeConsenso([414805, 416629, 458000]);
    expect(c, (414805 + 416629) / 2);
  });

  test('uma fonte fora do ar: as duas restantes bastam', () {
    expect(cotacaoDeConsenso([416629, 416941]), (416629 + 416941) / 2);
  });

  test('uma fonte sozinha não define o preço', () {
    expect(cotacaoDeConsenso([416629]), isNull);
    expect(cotacaoDeConsenso([]), isNull);
  });

  test('duas fontes que discordam: recusa em vez de escolher uma', () {
    expect(cotacaoDeConsenso([400000, 440000]), isNull);
  });

  test('valores inválidos não contam como fonte', () {
    expect(cotacaoDeConsenso([0, -1, double.nan, 416629]), isNull);
    expect(cotacaoDeConsenso([0, 416629, 416941]), (416629 + 416941) / 2);
  });
}
