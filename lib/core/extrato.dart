import '../services/wallet_service.dart' show Transaction;

/// Fechamento de caixa de um dia: o que a maquininha entrega ao lojista e a
/// Iris precisa entregar igual — quanto entrou, em quantas vendas, quanto
/// valia em Real na hora de cada uma, e o que saiu.
class FechamentoDia {
  final DateTime dia;
  final int vendas;
  final int satsRecebidos;

  /// Soma do valor em Real NO MOMENTO de cada venda (só das que têm o valor
  /// registrado). Vendas sem esse dado ficam em [vendasSemCotacao].
  final double brlNaHora;
  final int vendasSemCotacao;
  final int satsEnviados;
  final int pendentes;

  const FechamentoDia({
    required this.dia,
    required this.vendas,
    required this.satsRecebidos,
    required this.brlNaHora,
    required this.vendasSemCotacao,
    required this.satsEnviados,
    required this.pendentes,
  });

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  factory FechamentoDia.de(List<Transaction> txs, DateTime dia) {
    var vendas = 0, sats = 0, semCotacao = 0, enviados = 0, pendentes = 0;
    var brl = 0.0;
    for (final t in txs) {
      final local = t.date.toLocal();
      if (!_mesmoDia(local, dia)) continue;
      if (t.status != 'confirmed') {
        if (t.isIncoming) pendentes++;
        continue;
      }
      if (t.isIncoming) {
        vendas++;
        sats += t.amountSats;
        if (t.brlNaHora != null) {
          brl += t.brlNaHora!;
        } else {
          semCotacao++;
        }
      } else {
        enviados += t.amountSats;
      }
    }
    return FechamentoDia(
      dia: dia,
      vendas: vendas,
      satsRecebidos: sats,
      brlNaHora: brl,
      vendasSemCotacao: semCotacao,
      satsEnviados: enviados,
      pendentes: pendentes,
    );
  }
}

/// Extrato em CSV (separador `;` e vírgula decimal, como o Excel em
/// português abre direto). Uma linha por movimentação.
String extratoCsv(List<Transaction> txs) {
  String campo(String s) =>
      s.contains(RegExp(r'[;"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  String dois(int n) => n.toString().padLeft(2, '0');
  String reais(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  final linhas = <String>[
    'data;hora;descricao;tipo;via;sats;valor_brl_na_hora;status;id',
  ];
  final ordenadas = [...txs]..sort((a, b) => a.date.compareTo(b.date));
  for (final t in ordenadas) {
    final d = t.date.toLocal();
    linhas.add([
      '${dois(d.day)}/${dois(d.month)}/${d.year}',
      '${dois(d.hour)}:${dois(d.minute)}',
      campo(t.title),
      t.isIncoming ? 'entrada' : 'saida',
      t.emoji == '⚡' ? 'Lightning' : 'on-chain',
      '${t.isIncoming ? '' : '-'}${t.amountSats}',
      t.brlNaHora == null ? '' : reais(t.brlNaHora!),
      t.status == 'confirmed' ? 'confirmada' : 'pendente',
      campo(t.id),
    ].join(';'));
  }
  return '${linhas.join('\r\n')}\r\n';
}
