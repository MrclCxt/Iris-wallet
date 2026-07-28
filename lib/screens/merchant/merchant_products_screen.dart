import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/product_thumb.dart';
import 'merchant_product_form_screen.dart';
import 'merchant_product_qr_screen.dart';
import 'merchant_catalog_transfer.dart';

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
                const CurrencyToggleBtn(),
                const Text('Produtos',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: IrisTheme.textSecondary),
                      color: IrisTheme.s2,
                      tooltip: 'Catálogo',
                      onSelected: (v) {
                        if (v == 'exportar') {
                          showCatalogExportSheet(context);
                        } else if (v == 'importar') {
                          showCatalogImportDialog(context);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'exportar',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.ios_share, size: 20),
                            title: Text('Exportar catálogo'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'importar',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.download, size: 20),
                            title: Text('Importar catálogo'),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: IrisTheme.primary),
                      onPressed: () => _openNewProduct(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? _buildEmptyState(context)
                : MediaQuery.of(context).size.width >= 850
                    ? GridView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
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

  void _openNewProduct(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 720),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: const MerchantProductFormScreen(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 48, color: IrisTheme.textTertiary),
            const SizedBox(height: 16),
            const Text(
              'Nenhum produto cadastrado',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cadastre os itens da sua loja para gerar cobranças com um toque.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: IrisTheme.textTertiary, height: 1.4),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _openNewProduct(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar produto'),
              style: OutlinedButton.styleFrom(
                foregroundColor: IrisTheme.primary,
                side: const BorderSide(color: IrisTheme.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => showCatalogImportDialog(context),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Importar de outro aparelho'),
              style: TextButton.styleFrom(
                  foregroundColor: IrisTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductItem(
      BuildContext context, Product p, ExchangeRateService exchangeRate) {
    return InkWell(
      onTap: () {
        if (!p.isActive) return;
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450, maxHeight: 780),
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
            ProductThumb(product: p),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.description,
                      style: const TextStyle(
                          fontSize: 11, color: IrisTheme.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    exchangeRate.isSatsDisplay
                        ? CurrencyFormatter.formatBtcOrSats(
                            exchangeRate.brlToSats(p.price))
                        : 'R\$ ${CurrencyFormatter.formatBrlCompact(p.price)}',
                    style: const TextStyle(
                        fontFamily: 'monospace', color: IrisTheme.success),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    color: p.isActive
                        ? IrisTheme.primary.withOpacity(0.14)
                        : IrisTheme.s3,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('⚡',
                      style: TextStyle(
                          fontSize: 16,
                          color: p.isActive
                              ? IrisTheme.primary
                              : IrisTheme.textTertiary)),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.qr_code,
                    color: IrisTheme.textTertiary, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
