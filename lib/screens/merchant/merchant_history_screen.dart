import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';

import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';

class MerchantHistoryScreen extends StatelessWidget {
  const MerchantHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final exchangeRate = context.watch<ExchangeRateService>();

    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text('Histórico', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          
          Expanded(
            child: wallet.merchantTransactions.isEmpty
                ? const Center(child: Text('Nenhuma venda registrada ainda.', style: TextStyle(color: BitpayTheme.textSecondary)))
                : MediaQuery.of(context).size.width >= 850
                    ? _buildDesktopDataTable(wallet, exchangeRate)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: wallet.merchantTransactions.length,
                        itemBuilder: (context, index) {
                          final tx = wallet.merchantTransactions[index];
                          return _buildTxItem(
                            tx.title,
                            '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')} - ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}',
                            tx.amountSats,
                            exchangeRate,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDataTable(WalletService wallet, ExchangeRateService exchangeRate) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: BitpayTheme.s1,
        border: Border.all(color: BitpayTheme.bdr),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(BitpayTheme.s2),
            dataRowMinHeight: 60,
            dataRowMaxHeight: 60,
            columnSpacing: 24,
            horizontalMargin: 24,
            columns: const [
              DataColumn(label: Text('Data', style: TextStyle(fontWeight: FontWeight.bold, color: BitpayTheme.textSecondary))),
              DataColumn(label: Text('Descrição', style: TextStyle(fontWeight: FontWeight.bold, color: BitpayTheme.textSecondary))),
              DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold, color: BitpayTheme.textSecondary))),
              DataColumn(label: Text('Valor (BRL)', style: TextStyle(fontWeight: FontWeight.bold, color: BitpayTheme.textSecondary)), numeric: true),
              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: BitpayTheme.textSecondary))),
            ],
            rows: wallet.merchantTransactions.map((tx) {
              final brl = exchangeRate.satsToBrl(tx.amountSats);
              
              return DataRow(
                cells: [
                  DataCell(Text('${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: BitpayTheme.textSecondary))),
                  DataCell(Text(tx.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(const Text('Venda', style: TextStyle(color: BitpayTheme.textSecondary))),
                  DataCell(Text('+R\$ ${CurrencyFormatter.formatBrl(brl)}', style: const TextStyle(color: BitpayTheme.success, fontFamily: 'JetBrains Mono', fontWeight: FontWeight.bold))),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: BitpayTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BitpayTheme.success.withOpacity(0.3)),
                    ),
                    child: const Text('Concluído', style: TextStyle(color: BitpayTheme.success, fontSize: 12, fontWeight: FontWeight.bold)),
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }



  Widget _buildTxItem(String title, String time, int sats, ExchangeRateService exchangeRate) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BitpayTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BitpayTheme.bdr),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: BitpayTheme.s2, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt_long, color: BitpayTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(time, style: const TextStyle(fontSize: 11, color: BitpayTheme.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(sats))}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BitpayTheme.success),
              ),
              const SizedBox(height: 2),
              Text(
                '+ ${CurrencyFormatter.formatSats(sats)} sats',
                style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, color: BitpayTheme.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
