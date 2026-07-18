import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/area_switcher_btn.dart';
import 'merchant_product_qr_screen.dart';
import '../consumer/custom_charge_screen.dart';

class MerchantDashboard extends StatefulWidget {
  final Function(int)? onNavigateTab;
  const MerchantDashboard({super.key, this.onNavigateTab});

  @override
  State<MerchantDashboard> createState() => _MerchantDashboardState();
}

class _MerchantDashboardState extends State<MerchantDashboard> {
  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final exchangeRate = context.watch<ExchangeRateService>();
    final txs = wallet.merchantTransactions;
    final todaySats = txs.where((t) => t.date.day == DateTime.now().day).fold(0, (sum, t) => sum + t.amountSats);
    final weekSats = txs.where((t) => DateTime.now().difference(t.date).inDays <= 7).fold(0, (sum, t) => sum + t.amountSats);
    final totalSats = wallet.merchantBalance;
    final todaySales = txs.where((t) => t.date.day == DateTime.now().day).length;
    final weekSales = txs.where((t) => DateTime.now().difference(t.date).inDays <= 7).length;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: BitpayTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Text('🏪', style: TextStyle(fontSize: 17))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallet.merchantName ?? 'Minha Loja',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      const Text('Lojista · ⚡ Ativo', style: TextStyle(fontSize: 11, color: BitpayTheme.textSecondary)),
                    ],
                  ),
                ),
                const CurrencyToggleBtn(),
                if (MediaQuery.of(context).size.width < 850) ...[
                  const SizedBox(width: 6),
                  const AreaSwitcherBtn(isCurrentlyConsumer: false, showText: true),
                ],
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // Row 1: Hoje / Semana
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Hoje',
                          exchangeRate.isSatsDisplay 
                              ? '+${CurrencyFormatter.formatSats(todaySats)} SATS'
                              : '+R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(todaySats))}',
                          exchangeRate.isSatsDisplay
                              ? '≈ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(todaySats))} · $todaySales vendas'
                              : '≈ ${CurrencyFormatter.formatSats(todaySats)} sats · $todaySales vendas',
                          BitpayTheme.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatCard(
                          'Semana',
                          exchangeRate.isSatsDisplay
                              ? '${CurrencyFormatter.formatSats(weekSats)} SATS'
                              : 'R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(weekSats))}',
                          exchangeRate.isSatsDisplay
                              ? '≈ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(weekSats))} · $weekSales vendas'
                              : '≈ ${CurrencyFormatter.formatSats(weekSats)} sats · $weekSales vendas',
                          BitpayTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 2: Saldo loja / Taxa paga
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Saldo loja',
                          exchangeRate.isSatsDisplay
                              ? '${CurrencyFormatter.formatSats(totalSats)} SATS'
                              : 'R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(totalSats))}',
                          exchangeRate.isSatsDisplay
                              ? '≈ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(totalSats))}'
                              : '≈ ${CurrencyFormatter.formatSats(totalSats)} sats',
                          BitpayTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatCard(
                          'Taxa paga',
                          exchangeRate.isSatsDisplay ? '0 SATS' : 'R\$ 0,00',
                          'vs R\$ 31 maquininha',
                          BitpayTheme.success,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Charge Now button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (wallet.cartTotal > 0) {
                          wallet.setPendingCharge(wallet.cartTotal);
                          wallet.clearCart();
                          if (widget.onNavigateTab != null) {
                            widget.onNavigateTab!(2);
                          }
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CustomChargeScreen(isMerchant: true),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        wallet.cartTotal > 0 
                            ? (exchangeRate.isSatsDisplay 
                                ? '⚡ Cobrar ${CurrencyFormatter.formatSats(exchangeRate.brlToSats(wallet.cartTotal))} SATS'
                                : '⚡ Cobrar R\$ ${CurrencyFormatter.formatBrl(wallet.cartTotal)}')
                            : '⚡ Cobrar valor específico',
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(color: BitpayTheme.bdr, height: 1),
                  const SizedBox(height: 24),
                  
                  // Produtos Ativos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Produtos ativos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      GestureDetector(
                        onTap: () {
                          if (widget.onNavigateTab != null) {
                            widget.onNavigateTab!(1);
                          }
                        },
                        child: const Text('Gerenciar →', style: TextStyle(fontSize: 12, color: BitpayTheme.primary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Dynamic Products row
                  if (wallet.merchantProducts.isEmpty)
                    const Text('Nenhum produto cadastrado.', style: TextStyle(color: BitpayTheme.textSecondary))
                  else
                    Column(
                      children: wallet.merchantProducts.where((p) => p.isActive).map((p) => _buildProductRow(p)).toList(),
                    ),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String unit, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BitpayTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BitpayTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: BitpayTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13, fontWeight: FontWeight.w700, color: valueColor)),
          const SizedBox(height: 2),
          Text(unit, style: const TextStyle(fontSize: 10, color: BitpayTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildProductRow(Product p) {
    final exchangeRate = context.watch<ExchangeRateService>();
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450, maxHeight: 700),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MerchantProductQrScreen(product: p),
              ),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BitpayTheme.s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BitpayTheme.bdr),
        ),
        child: Row(
          children: [
            Text(p.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    exchangeRate.isSatsDisplay
                        ? '${CurrencyFormatter.formatSats(exchangeRate.brlToSats(p.price))} SATS'
                        : 'R\$ ${CurrencyFormatter.formatBrl(p.price)}',
                    style: const TextStyle(fontSize: 11, color: BitpayTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BitpayTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
