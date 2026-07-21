import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/chroma_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/area_switcher_btn.dart';
import '../../widgets/iris_widgets.dart';

class ConsumerDashboard extends StatefulWidget {
  final Function(int)? onNavigateTab;
  const ConsumerDashboard({super.key, this.onNavigateTab});

  @override
  State<ConsumerDashboard> createState() => _ConsumerDashboardState();
}

class _ConsumerDashboardState extends State<ConsumerDashboard> {
  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final liquid = context.watch<LiquidWalletService>();
    final exchangeRate = context.watch<ExchangeRateService>();
    final chroma = context.watch<ChromaService>();
    final _showSats = exchangeRate.isSatsDisplay;
    // Saldo unificado em satoshis: Lightning + Bitcoin on-chain + L-BTC (Liquid).
    // A moeda do app é o satoshi; o toggle apenas muda a exibição para BRL.
    final balanceSats = wallet.consumerBalance + liquid.balanceSats;
    final balanceBrl = exchangeRate.satsToBrl(balanceSats);

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                // Real IRIS logo
                const IrisLogo(size: 36),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Minha carteira', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    const Text('Bitcoin · saldo em satoshis', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                  ],
                ),
                const Spacer(),
                // Currency Toggle
                const CurrencyToggleBtn(),
                if (MediaQuery.of(context).size.width < 850) ...[
                  const SizedBox(width: 6),
                  const AreaSwitcherBtn(isCurrentlyConsumer: true, showText: false),
                ],
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Balance Area
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                    child: Column(
                      children: [
                        const Text(
                          'SALDO',
                          style: TextStyle(
                            fontSize: 10,
                            color: IrisTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ShaderMask(
                            // O shader é criado sobre um retângulo levemente
                            // inflado para garantir que TODO glifo (inclusive o
                            // rabo da vírgula e as bordas antialias) caia dentro
                            // da área do gradiente — senão parte fica branca.
                            // Sem `height: 1`: a caixa de linha apertada cortava
                            // a máscara abaixo da vírgula.
                            shaderCallback: (bounds) =>
                                chroma.spectrumGradient.createShader(bounds.inflate(2)),
                            child: Text(
                              _showSats
                                  ? CurrencyFormatter.formatBtcOrSats(balanceSats)
                                  : 'R\$ ${CurrencyFormatter.formatBrlCompact(balanceBrl)}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 44,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _showSats
                              ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(balanceBrl)}'
                              : '≈ ${CurrencyFormatter.formatBtcOrSats(balanceSats)}',
                          style: const TextStyle(fontSize: 12, color: IrisTheme.textSecondary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '1 BTC = R\$ ${CurrencyFormatter.formatBrl(exchangeRate.btcToBrlRate)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: IrisTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (widget.onNavigateTab != null) {
                                widget.onNavigateTab!(1); // Enviar
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: const Text('💸 Enviar', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (widget.onNavigateTab != null) {
                                widget.onNavigateTab!(2); // Receber
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: IrisTheme.s2,
                              foregroundColor: IrisTheme.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: const BorderSide(color: IrisTheme.bdr2),
                            ),
                            child: const Text('⬇ Receber', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 14),
                  const Divider(color: IrisTheme.bdr, height: 1),
                  const SizedBox(height: 14),

                  // History
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'ÚLTIMAS MOVIMENTAÇÕES',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: IrisTheme.textTertiary,
                            ),
                          ),
                        ),
                        if (wallet.consumerTransactions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('Nenhuma movimentação ainda.', style: TextStyle(color: IrisTheme.textSecondary)),
                            ),
                          )
                        else if (MediaQuery.of(context).size.width >= 850)
                          _buildDesktopDataTable(wallet, exchangeRate)
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: IrisTheme.s1,
                              border: Border.all(color: IrisTheme.bdr),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                for (int i = 0; i < wallet.consumerTransactions.length; i++) ...[
                                  if (i > 0) const Divider(color: IrisTheme.bdr, height: 20),
                                  _buildTxRow(
                                    wallet.consumerTransactions[i].emoji,
                                    wallet.consumerTransactions[i].title,
                                    '${wallet.consumerTransactions[i].date.day.toString().padLeft(2, '0')}/${wallet.consumerTransactions[i].date.month.toString().padLeft(2, '0')}',
                                    wallet.consumerTransactions[i].isIncoming ? wallet.consumerTransactions[i].amountSats : -wallet.consumerTransactions[i].amountSats,
                                    exchangeRate.isSatsDisplay,
                                    exchangeRate,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDataTable(WalletService wallet, ExchangeRateService exchangeRate) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        border: Border.all(color: IrisTheme.bdr),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(IrisTheme.s2),
          dataRowMinHeight: 60,
          dataRowMaxHeight: 60,
          columnSpacing: 24,
          horizontalMargin: 24,
          columns: const [
            DataColumn(label: Text('Data', style: TextStyle(fontWeight: FontWeight.bold, color: IrisTheme.textSecondary))),
            DataColumn(label: Text('Descrição', style: TextStyle(fontWeight: FontWeight.bold, color: IrisTheme.textSecondary))),
            DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold, color: IrisTheme.textSecondary))),
            DataColumn(label: Text('Valor', style: TextStyle(fontWeight: FontWeight.bold, color: IrisTheme.textSecondary)), numeric: true),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: IrisTheme.textSecondary))),
          ],
          rows: wallet.consumerTransactions.map((tx) {
            final isPos = tx.isIncoming;
            final color = isPos ? IrisTheme.success : IrisTheme.danger;
            final sats = isPos ? tx.amountSats : -tx.amountSats;
            final valStr = exchangeRate.isSatsDisplay
                ? '${isPos ? '+' : ''}${CurrencyFormatter.formatBtcOrSats(sats)}'
                : '${isPos ? '+' : '-'}R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(sats.abs()))}';

            return DataRow(
              cells: [
                DataCell(Text('${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: IrisTheme.textSecondary))),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tx.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(tx.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                )),
                DataCell(Text(isPos ? 'Depósito' : 'Pagamento', style: TextStyle(color: isPos ? IrisTheme.textPrimary : IrisTheme.textSecondary))),
                DataCell(Text(valStr, style: TextStyle(color: color, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                DataCell(Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: IrisTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: IrisTheme.success.withOpacity(0.3)),
                  ),
                  child: const Text('Concluído', style: TextStyle(color: IrisTheme.success, fontSize: 12, fontWeight: FontWeight.bold)),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }



  Widget _buildTxRow(String emoji, String title, String time, int sats, bool showSats, ExchangeRateService exchangeRate) {
    final isPos = sats >= 0;
    final color = isPos ? IrisTheme.success : IrisTheme.danger;
    final brl = exchangeRate.satsToBrl(sats.abs());
    
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: IrisTheme.s3,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 15))),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text(time, style: const TextStyle(fontSize: 11, color: IrisTheme.textSecondary, fontFamily: 'monospace')),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              showSats
                  ? '${isPos ? '+' : '-'}${CurrencyFormatter.formatBtcOrSats(sats.abs())}'
                  : '${isPos ? '+' : '-'}R\$ ${CurrencyFormatter.formatBrl(brl)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
            Text(
              showSats
                  ? '≈ R\$ ${CurrencyFormatter.formatBrl(brl)}'
                  : '≈ ${CurrencyFormatter.formatBtcOrSats(sats.abs())}',
              style: const TextStyle(fontSize: 10, color: IrisTheme.textTertiary, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }
}
