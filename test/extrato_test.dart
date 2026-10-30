import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/extrato.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// Fechamento de caixa e extrato do lojista: o valor em Real é o da HORA da
/// venda, e venda sem esse dado não vira número inventado.
void main() {
  final hoje = DateTime(2026, 10, 30);
  Transaction tx(String id, int sats,
          {bool entrada = true,
          String status = 'confirmed',
          double? brl,
          DateTime? quando,
          String titulo = 'Venda recebida'}) =>
      Transaction(
        id: id,
        title: titulo,
        emoji: '⚡',
        amountSats: sats,
        isIncoming: entrada,
        date: quando ?? hoje.add(const Duration(hours: 10)),
        status: status,
        brlNaHora: brl,
      );

  test('fechamento soma só o dia, só confirmadas, com o Real da hora', () {
    final f = FechamentoDia.de([
      tx('a', 1000, brl: 4.25),
      tx('b', 2000, brl: 8.50),
      tx('c', 500), // sem cotação na hora
      tx('d', 700, status: 'pending'),
      tx('e', 300, entrada: false),
      tx('f', 9999, brl: 40, quando: hoje.subtract(const Duration(days: 1))),
    ], hoje);
    expect(f.vendas, 3);
    expect(f.satsRecebidos, 3500);
    expect(f.brlNaHora, closeTo(12.75, 0.001));
    expect(f.vendasSemCotacao, 1);
    expect(f.pendentes, 1);
    expect(f.satsEnviados, 300);
  });

  test('CSV abre no Excel em português e escapa a descrição', () {
    final csv = extratoCsv([
      tx('b', 2000, brl: 8.5, titulo: 'Café; "grande"'),
      tx('a', 1000, quando: hoje.add(const Duration(hours: 8))),
    ]);
    final linhas = csv.trim().split('\r\n');
    expect(linhas.first, 'data;hora;descricao;tipo;via;sats;valor_brl_na_hora;status;id');
    expect(linhas[1], startsWith('30/10/2026;08:00;Venda recebida;entrada;Lightning;1000;;confirmada'));
    expect(linhas[2], contains('"Café; ""grande"""'));
    expect(linhas[2], contains(';8,50;'));
  });

  test('o valor em Real da hora sobrevive ao salvar e reabrir', () {
    final t = Transaction.fromJson(tx('x', 1000, brl: 4.25).toJson());
    expect(t.brlNaHora, 4.25);
    expect(Transaction.fromJson(tx('y', 1).toJson()).brlNaHora, isNull);
  });
}
