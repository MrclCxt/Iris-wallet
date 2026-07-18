import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/bolt11.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/max_width_container.dart';
import '../../core/currency_format.dart';
import 'merchant_product_edit_screen.dart';
import 'package:share_plus/share_plus.dart';

class MerchantProductQrScreen extends StatefulWidget {
  final Product product;
  const MerchantProductQrScreen({super.key, required this.product});

  @override
  State<MerchantProductQrScreen> createState() => _MerchantProductQrScreenState();
}

class _MerchantProductQrScreenState extends State<MerchantProductQrScreen> {
  String? _invoiceData;
  bool _isLoading = true;
  bool _isPaid = false;
  String? _watchingPaymentHash;
  StreamSubscription<ReceivedPayment>? _paymentSub;

  bool _invoiceRequested = false;

  @override
  void initState() {
    super.initState();
    // Detecção real do recebimento via eventos do nó LDK da loja
    _paymentSub = context.read<WalletService>().paymentsReceived.listen((payment) {
      if (!mounted || _isPaid) return;
      if (!payment.isMerchant) return;
      if (_watchingPaymentHash == null || payment.paymentHashHex == _watchingPaymentHash) {
        setState(() => _isPaid = true);
      }
    });
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A cobrança é sempre uma fatura Lightning (moeda do app = satoshi);
    // o toggle SATS/R$ muda apenas a exibição do valor.
    if (!_invoiceRequested) {
      _invoiceRequested = true;
      _generateInvoice();
    }
  }

  Future<void> _generateInvoice() async {
    // Need to use post-frame callback since we need context for ExchangeRateService
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final exchangeRate = context.read<ExchangeRateService>();
      final int satsAmount = exchangeRate.brlToSats(widget.product.price);

      try {
        if (satsAmount <= 0) {
          throw Exception('Cotação BTC/BRL indisponível — aguarde a atualização do câmbio.');
        }
        final wallet = context.read<WalletService>();
        final payload = await wallet.createInvoice(
          satsAmount,
          'Venda: ${widget.product.name}',
          forMerchant: true,
        );
        try {
          _watchingPaymentHash = Bolt11.decode(payload).paymentHashHex;
        } catch (_) {
          _watchingPaymentHash = null;
        }

        if (mounted) {
          setState(() {
            _invoiceData = payload;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao gerar fatura: $e'), backgroundColor: IrisTheme.danger),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Usar a versão atualizada do produto vindo do provider
    final wallet = context.watch<WalletService>();
    final product = wallet.merchantProducts.firstWhere(
      (p) => p.id == widget.product.id,
      orElse: () => widget.product, // fallback caso excluido
    );

    // Se o produto foi excluido enquanto nesta tela (embora pop resolva, é bom checar)
    if (!wallet.merchantProducts.any((p) => p.id == widget.product.id)) {
      return const Scaffold(backgroundColor: IrisTheme.bg, body: SizedBox());
    }

    final exchangeRate = context.watch<ExchangeRateService>();
    final int satsAmount = exchangeRate.brlToSats(product.price);

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      body: MaxWidthContainer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: IrisTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text(product.emoji, style: const TextStyle(fontSize: 17))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (_invoiceData != null)
                    IconButton(
                      icon: const Icon(Icons.share, color: IrisTheme.primary),
                      onPressed: () {
                        Share.share(_invoiceData!);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: IrisTheme.primary),
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
                              child: MerchantProductEditScreen(product: product),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: IrisTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'R\$ ${CurrencyFormatter.formatBrl(product.price)}',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(color: IrisTheme.success, fontSize: 42),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${CurrencyFormatter.formatSats(satsAmount)} sats',
                      style: const TextStyle(fontSize: 15, color: IrisTheme.textSecondary, fontFamily: 'JetBrains Mono'),
                    ),
                    const SizedBox(height: 32),
                    
                    if (_isLoading)
                      const CircularProgressIndicator(color: IrisTheme.primary)
                    else if (_invoiceData != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: IrisTheme.primary.withOpacity(0.15),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            QrImageView(
                              data: _invoiceData!,
                              version: QrVersions.auto,
                              size: 240,
                              backgroundColor: Colors.white,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: IrisTheme.bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: IrisTheme.bdr),
                              ),
                              child: Text(
                                _invoiceData!,
                                style: const TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 12,
                                  color: IrisTheme.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(),
                    
                    const SizedBox(height: 24),
                    if (_isPaid) ...[
                      const Icon(Icons.check_circle, color: IrisTheme.success, size: 48),
                      const SizedBox(height: 8),
                      const Text(
                        'Pagamento recebido! ⚡',
                        style: TextStyle(color: IrisTheme.success, fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ] else ...[
                      const Text(
                        'Aguardando pagamento...',
                        style: TextStyle(color: IrisTheme.primary, fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(IrisTheme.primary)),
                    ],
                  ],
                ),
              ),
            ),
            
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('← Voltar', style: TextStyle(color: IrisTheme.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
