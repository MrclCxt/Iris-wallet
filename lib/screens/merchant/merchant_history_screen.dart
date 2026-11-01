import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/extrato.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';

import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/tx_status.dart';
import '../../widgets/tx_details_sheet.dart';

class MerchantHistoryScreen extends StatelessWidget {
  const MerchantHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final exchangeRate = context.watch<ExchangeRateService>();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Exportar extrato (CSV)',
                  icon: const Icon(Icons.ios_share, color: IrisTheme.textSecondary),
                  onPressed: wallet.merchantTransactions.isEmpty
                      ? null
                      : () => _exportar(context, wallet.merchantTransactions),
                ),
                const Text('Histórico',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const CurrencyToggleBtn(),
              ],
            ),
          ),
          if (wallet.merchantTransactions.isNotEmpty)
            _fechamento(FechamentoDia.de(wallet.merchantTransactions, DateTime.now())),
          Expanded(
            child: wallet.merchantTransactions.isEmpty
                ? const Center(
                    child: Text('Nenhuma venda registrada ainda.',
                        style: TextStyle(color: IrisTheme.textSecondary)))
                : MediaQuery.of(context).size.width >= 850
                    ? _buildDesktopDataTable(wallet, exchangeRate)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: wallet.merchantTransactions.length,
                        itemBuilder: (context, index) {
                          final tx = wallet.merchantTransactions[index];
                          return InkWell(
                            onTap: () => TxDetailsSheet.abrir(
                              context,
                              tx: tx,
                              showSats: exchangeRate.isSatsDisplay,
                              brlRate: exchangeRate.btcToBrlRate,
                              aoDescobrirStatus: (confirmada) =>
                                  wallet.aplicarStatusDaRede(tx.id,
                                      confirmada: confirmada,
                                      isMerchant: true),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: _buildTxItem(
                              tx.title,
                              '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')} - ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}',
                              tx.amountSats,
                              exchangeRate,
                              status: tx.status,
                              brlNaHora: tx.brlNaHora,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportar(BuildContext context, List<Transaction> txs) async {
    try {
      final dir = await getTemporaryDirectory();
      final agora = DateTime.now();
      final nome =
          'extrato-iris-${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}.csv';
      final arquivo = File('${dir.path}/$nome');
      // BOM para o Excel reconhecer UTF-8 (acentos) ao abrir direto.
      await arquivo.writeAsString(
          '${String.fromCharCode(0xFEFF)}${extratoCsv(txs)}');
      await Share.shareXFiles([XFile(arquivo.path, mimeType: 'text/csv')],
          subject: 'Extrato Iris');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível exportar: $e')));
      }
    }
  }

  Widget _fechamento(FechamentoDia f) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FECHAMENTO DE HOJE',
              style: TextStyle(
                  fontSize: 10,
                  color: IrisTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(
              '${f.vendas} ${f.vendas == 1 ? 'venda' : 'vendas'} · '
              '${CurrencyFormatter.formatBtcOrSats(f.satsRecebidos)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (f.vendas > f.vendasSemCotacao)
            Text(
                'R\$ ${CurrencyFormatter.formatBrl(f.brlNaHora)} no valor da hora de cada venda'
                '${f.vendasSemCotacao > 0 ? ' (${f.vendasSemCotacao} sem cotação)' : ''}',
                style: const TextStyle(
                    fontSize: 12, color: IrisTheme.textSecondary)),
          if (f.pendentes > 0)
            Text('${f.pendentes} aguardando confirmação',
                style: const TextStyle(fontSize: 12, color: IrisTheme.warning)),
        ],
      ),
    );
  }

  Widget _buildDesktopDataTable(
      WalletService wallet, ExchangeRateService exchangeRate) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        border: Border.all(color: IrisTheme.bdr),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(IrisTheme.s2),
            dataRowMinHeight: 60,
            dataRowMaxHeight: 60,
            columnSpacing: 24,
            horizontalMargin: 24,
            columns: const [
              DataColumn(
                  label: Text('Data',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: IrisTheme.textSecondary))),
              DataColumn(
                  label: Text('Descrição',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: IrisTheme.textSecondary))),
              DataColumn(
                  label: Text('Tipo',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: IrisTheme.textSecondary))),
              DataColumn(
                  label: Text('Valor (BRL)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: IrisTheme.textSecondary)),
                  numeric: true),
              DataColumn(
                  label: Text('Status',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: IrisTheme.textSecondary))),
            ],
            rows: wallet.merchantTransactions.map((tx) {
              final brl = tx.brlNaHora ?? exchangeRate.satsToBrl(tx.amountSats);

              return DataRow(
                cells: [
                  DataCell(Text(
                      '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: IrisTheme.textSecondary))),
                  DataCell(Text(tx.title,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
                  const DataCell(Text('Venda',
                      style: TextStyle(color: IrisTheme.textSecondary))),
                  DataCell(Text(
                      exchangeRate.isSatsDisplay
                          ? '+${CurrencyFormatter.formatBtcOrSats(tx.amountSats)}'
                          : '+R\$ ${CurrencyFormatter.formatBrlCompact(brl)}',
                      style: const TextStyle(
                          color: IrisTheme.success,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold))),
                  DataCell(TxStatusChip(status: tx.status, isIncoming: true)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTxItem(
      String title, String time, int sats, ExchangeRateService exchangeRate,
      {String status = 'confirmed', double? brlNaHora}) {
    final brl = brlNaHora ?? exchangeRate.satsToBrl(sats);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: IrisTheme.s2, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt_long,
                color: IrisTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(time,
                        style: const TextStyle(
                            fontSize: 11, color: IrisTheme.textSecondary)),
                    const SizedBox(width: 6),
                    // Sempre visível, inclusive "Confirmada" (venda liquidada).
                    Flexible(
                        child: TxStatusChip(
                            status: status, compact: true, isIncoming: true)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                exchangeRate.isSatsDisplay
                    ? '+ ${CurrencyFormatter.formatBtcOrSats(sats)}'
                    : '+ R\$ ${CurrencyFormatter.formatBrlCompact(brl)}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: IrisTheme.success),
              ),
              const SizedBox(height: 2),
              Text(
                exchangeRate.isSatsDisplay
                    ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(brl)}'
                    : '≈ ${CurrencyFormatter.formatBtcOrSats(sats)}',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: IrisTheme.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
