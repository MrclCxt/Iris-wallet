import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/chroma_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/account_avatar.dart';
import '../../widgets/tx_status.dart';
import '../../widgets/tx_details_sheet.dart';
import 'explore_wallets_screen.dart';

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
    final showSats = exchangeRate.isSatsDisplay;

    final balanceSats = wallet.consumerBalance + liquid.balanceSats;
    final balanceBrl = exchangeRate.satsToBrl(balanceSats);

    final balanceFontSize =
        MediaQuery.of(context).size.width >= 850 ? 68.0 : 44.0;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                const AccountAvatar(isMerchant: false, size: 36),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wallet.activeConsumer?.name ?? 'Minha carteira',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      const Text('Bitcoin · saldo em satoshis',
                          style: TextStyle(
                              fontSize: 11, color: IrisTheme.textSecondary)),
                    ],
                  ),
                ),
                const Spacer(),
                const CurrencyToggleBtn(),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: IrisTheme.primary,
              backgroundColor: IrisTheme.s2,
              onRefresh: () => wallet.atualizarAgora(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () =>
                                    wallet.setHideBalance(!wallet.hideBalance),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    wallet.hideBalance
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 14,
                                    color: IrisTheme.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => showExploreWalletsSheet(context,
                                isMerchant: false),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: ShaderMask(
                                shaderCallback: (bounds) => chroma
                                    .spectrumGradient
                                    .createShader(bounds.inflate(2)),
                                child: Text(
                                  wallet.hideBalance
                                      ? '••••••'
                                      : (showSats
                                          ? CurrencyFormatter.formatBtcOrSats(
                                              balanceSats)
                                          : 'R\$ ${CurrencyFormatter.formatBrlCompact(balanceBrl)}'),
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: balanceFontSize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            wallet.hideBalance
                                ? 'Toque para explorar carteiras'
                                : (showSats
                                    ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(balanceBrl)}'
                                    : '≈ ${CurrencyFormatter.formatBtcOrSats(balanceSats)}'),
                            style: const TextStyle(
                                fontSize: 12, color: IrisTheme.textSecondary),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '1 BTC = R\$ ${CurrencyFormatter.formatBrlCompact(exchangeRate.btcToBrlRate)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: IrisTheme.textTertiary,
                            ),
                          ),
                          if (wallet.saldoDesatualizado) ...[
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 9,
                                  height: 9,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    valueColor: AlwaysStoppedAnimation(
                                        IrisTheme.textTertiary),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Último saldo salvo · sincronizando',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        IrisTheme.textTertiary.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: chroma.buttonGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  if (widget.onNavigateTab != null) {
                                    widget.onNavigateTab!(1);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                                child: const Text('💸 Enviar',
                                    style: TextStyle(fontSize: 14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                if (widget.onNavigateTab != null) {
                                  widget.onNavigateTab!(2);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: IrisTheme.s2,
                                foregroundColor: IrisTheme.textPrimary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                side: const BorderSide(color: IrisTheme.bdr2),
                              ),
                              child: const Text('⬇ Receber',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: IrisTheme.bdr, height: 1),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (wallet.restaurandoCarteira)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: IrisTheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: IrisTheme.primary.withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                          IrisTheme.primary),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Procurando seu histórico na rede — o saldo '
                                      'pode levar alguns instantes para aparecer.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: IrisTheme.textSecondary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          PendingBanner(
                            pendingSats: wallet.consumerPendingOnchainSats,
                            hide: wallet.hideBalance,
                            format: CurrencyFormatter.formatBtcOrSats,
                          ),
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
                                child: Text('Nenhuma movimentação ainda.',
                                    style: TextStyle(
                                        color: IrisTheme.textSecondary)),
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
                                  for (int i = 0;
                                      i < wallet.consumerTransactions.length;
                                      i++) ...[
                                    if (i > 0)
                                      const Divider(
                                          color: IrisTheme.bdr, height: 20),
                                    InkWell(
                                      onTap: () => TxDetailsSheet.abrir(
                                        context,
                                        tx: wallet.consumerTransactions[i],
                                        showSats: exchangeRate.isSatsDisplay,
                                        brlRate: exchangeRate.btcToBrlRate,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: _buildTxRow(
                                          wallet.consumerTransactions[i].emoji,
                                          wallet.consumerTransactions[i].title,
                                          '${wallet.consumerTransactions[i].date.day.toString().padLeft(2, '0')}/${wallet.consumerTransactions[i].date.month.toString().padLeft(2, '0')}',
                                          wallet.consumerTransactions[i]
                                                  .isIncoming
                                              ? wallet.consumerTransactions[i]
                                                  .amountSats
                                              : -wallet.consumerTransactions[i]
                                                  .amountSats,
                                          exchangeRate.isSatsDisplay,
                                          exchangeRate,
                                          hide: wallet.hideBalance,
                                          status: wallet
                                              .consumerTransactions[i].status,
                                        ),
                                      ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDataTable(
      WalletService wallet, ExchangeRateService exchangeRate) {
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
                label: Text('Valor',
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
          rows: wallet.consumerTransactions.map((tx) {
            final isPos = tx.isIncoming;
            final color = isPos ? IrisTheme.success : IrisTheme.danger;
            final sats = isPos ? tx.amountSats : -tx.amountSats;
            final valStr = wallet.hideBalance
                ? '${isPos ? '+' : '-'}••••'
                : (exchangeRate.isSatsDisplay
                    ? '${isPos ? '+' : ''}${CurrencyFormatter.formatBtcOrSats(sats)}'
                    : '${isPos ? '+' : '-'}R\$ ${CurrencyFormatter.formatBrlCompact(exchangeRate.satsToBrl(sats.abs()))}');

            void abrirDetalhes() => TxDetailsSheet.abrir(
                  context,
                  tx: tx,
                  showSats: exchangeRate.isSatsDisplay,
                  brlRate: exchangeRate.btcToBrlRate,
                );

            return DataRow(
              onSelectChanged: (_) => abrirDetalhes(),
              cells: [
                DataCell(
                    Text(
                        '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: IrisTheme.textSecondary)),
                    onTap: abrirDetalhes),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tx.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(tx.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                )),
                DataCell(Text(isPos ? 'Depósito' : 'Pagamento',
                    style: TextStyle(
                        color: isPos
                            ? IrisTheme.textPrimary
                            : IrisTheme.textSecondary))),
                DataCell(Text(valStr,
                    style: TextStyle(
                        color: color,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold))),
                DataCell(TxStatusChip(status: tx.status)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTxRow(String emoji, String title, String time, int sats,
      bool showSats, ExchangeRateService exchangeRate,
      {bool hide = false, String status = 'confirmed'}) {
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
          child:
              Center(child: Text(emoji, style: const TextStyle(fontSize: 15))),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(time,
                      style: const TextStyle(
                          fontSize: 11,
                          color: IrisTheme.textSecondary,
                          fontFamily: 'monospace')),
                  if (status != 'confirmed') ...[
                    const SizedBox(width: 6),
                    Flexible(
                        child: TxStatusChip(status: status, compact: true)),
                  ],
                ],
              ),
            ],
          ),
        ),
        hide
            ? Text('${isPos ? '+' : '-'}••••',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    showSats
                        ? '${isPos ? '+' : '-'}${CurrencyFormatter.formatBtcOrSats(sats.abs())}'
                        : '${isPos ? '+' : '-'}R\$ ${CurrencyFormatter.formatBrlCompact(brl)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                  Text(
                    showSats
                        ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(brl)}'
                        : '≈ ${CurrencyFormatter.formatBtcOrSats(sats.abs())}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: IrisTheme.textTertiary,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
      ],
    );
  }
}
