import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import 'merchant_product_new_screen.dart';
import 'merchant_product_qr_screen.dart';

class MerchantProductsScreen extends StatefulWidget {
  const MerchantProductsScreen({super.key});

  @override
  State<MerchantProductsScreen> createState() => _MerchantProductsScreenState();
}

class _MerchantProductsScreenState extends State<MerchantProductsScreen> {

  @override
  Widget build(BuildContext context) {
    final products = context.watch<WalletService>().merchantProducts;
    final exchangeRate = context.watch<ExchangeRateService>();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                const Text('Produtos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.add, color: IrisTheme.primary),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: const EdgeInsets.all(16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 700),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: const MerchantProductNewScreen(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          Expanded(
            child: MediaQuery.of(context).size.width >= 850
                ? GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 350,
                      mainAxisExtent: 100,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return _buildProductItem(context, p, exchangeRate);
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return _buildProductItem(context, p, exchangeRate);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(BuildContext context, Product p, ExchangeRateService exchangeRate) {
    return InkWell(
      onTap: () {
        if (!p.isActive) return;
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: IrisTheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Row(
          children: [
            Text(p.emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    p.name, 
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exchangeRate.isSatsDisplay
                        ? '${CurrencyFormatter.formatSats(exchangeRate.brlToSats(p.price))} SATS'
                        : 'R\$ ${CurrencyFormatter.formatBrl(p.price)}',
                    style: const TextStyle(fontFamily: 'JetBrains Mono', color: IrisTheme.success),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Switch(
                  value: p.isActive,
                  activeColor: IrisTheme.primary,
                  onChanged: (val) {
                    p.isActive = val;
                    context.read<WalletService>().updateMerchantProduct(p);
                  },
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.isActive ? IrisTheme.primary.withOpacity(0.14) : IrisTheme.s3,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('⚡', style: TextStyle(fontSize: 16, color: p.isActive ? IrisTheme.primary : IrisTheme.textTertiary)),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.qr_code, color: IrisTheme.textTertiary, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
