import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/bolt11.dart';
import '../../core/tx_policy.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/pix_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../widgets/max_width_container.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../core/currency_format.dart';
import 'merchant_product_form_screen.dart';
import '../../widgets/product_thumb.dart';
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
  bool _isOnchainPayload = false;
  bool? _lastSatsMode; // trilho segue a moeda: R$ -> PIX, SATS -> LN/on-chain
  String? _watchingPaymentHash;
  StreamSubscription<ReceivedPayment>? _paymentSub;
  StreamSubscription<int>? _lbtcSub;
  Timer? _paidTimer;
  // A cobrança PIX fica em estado GLOBAL no PixService. Se esta tela criar uma
  // e não limpar, as abas de trilho somem na tela de Receber/Cobrar (ela some
  // quando há cobrança ativa) e só voltam reiniciando o app.
  PixService? _pix;
  bool _createdPixCharge = false;

  @override
  void initState() {
    super.initState();
    // Recebimento Lightning/on-chain via eventos do nó LDK da loja.
    _paymentSub = context.read<WalletService>().paymentsReceived.listen((payment) {
      if (!mounted || _isPaid) return;
      if (!payment.isMerchant) return;
      final hashMatch = _watchingPaymentHash != null &&
          payment.paymentHashHex == _watchingPaymentHash;
      final onchainMatch = _isOnchainPayload && payment.isOnchain;
      if (hashMatch || onchainMatch) _markPaid();
    });
    // Recebimento PIX (L-BTC/DEPIX chegando na Liquid).
    _lbtcSub = context.read<LiquidWalletService>().lbtcReceived.listen((sats) {
      if (!mounted || _isPaid || _lastSatsMode != false) return;
      _markPaid();
    });
  }

  void _markPaid() {
    setState(() => _isPaid = true);
    // Mostra "recebido" e fecha o modal do produto (volta à lista) após 4s.
    _paidTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    _lbtcSub?.cancel();
    _paidTimer?.cancel();
    // Limpa a cobrança PIX criada por esta tela para não vazar o estado global
    // (senão as abas de trilho somem em Receber/Cobrar até reiniciar o app).
    if (_createdPixCharge) _pix?.clearActiveCharge();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pix = context.read<PixService>();
    // O trilho de recebimento segue a moeda selecionada: alternar SATS <-> R$
    // regenera o QR — R$ vira cobrança PIX; SATS vira Lightning (ou on-chain
    // para valores grandes).
    final isSats = context.read<ExchangeRateService>().isSatsDisplay;
    if (_lastSatsMode != isSats) {
      _lastSatsMode = isSats;
      WidgetsBinding.instance.addPostFrameCallback((_) => _generatePayload());
    }
  }

  Future<void> _generatePayload() async {
    final rate = context.read<ExchangeRateService>();
    final wallet = context.read<WalletService>();
    final satsAmount = rate.brlToSats(widget.product.price);
    setState(() {
      _isLoading = true;
      _invoiceData = null;
    });
    try {
      if (rate.isSatsDisplay) {
        // Saiu do PIX: descarta a cobrança que esta tela havia criado, senão o
        // estado global segue "com cobrança ativa" e some com as abas depois.
        if (_createdPixCharge) {
          _pix?.clearActiveCharge();
          _createdPixCharge = false;
        }
        if (satsAmount <= 0) {
          throw Exception('Cotação BTC/BRL indisponível — aguarde a atualização do câmbio.');
        }
        if (TxPolicy.shouldUseOnchain(satsAmount)) {
          // Valor grande: recebimento pela rede Bitcoin on-chain.
          final addr = await wallet.getOnchainAddress(forMerchant: true);
          final btc = (satsAmount / 100000000).toStringAsFixed(8);
          _invoiceData = 'bitcoin:$addr?amount=$btc';
          _watchingPaymentHash = null;
          _isOnchainPayload = true;
        } else {
          final inv = await wallet.createInvoice(
            satsAmount, 'Venda: ${widget.product.name}', forMerchant: true);
          _invoiceData = inv;
          try {
            _watchingPaymentHash = Bolt11.decode(inv).paymentHashHex;
          } catch (_) {
            _watchingPaymentHash = null;
          }
          _isOnchainPayload = false;
        }
      } else {
        // Moeda em R$: recebimento por PIX (DEPIX -> Liquid -> sats).
        final pix = context.read<PixService>();
        await pix.startDeposit(widget.product.price);
        _createdPixCharge = true; // limpa no dispose / ao voltar para SATS
        _invoiceData = pix.activeCharge?.qrCopiaECola;
        _watchingPaymentHash = null;
        _isOnchainPayload = false;
        if (_invoiceData == null || _invoiceData!.isEmpty) {
          throw Exception('Falha ao gerar cobrança PIX.');
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _invoiceData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar cobrança: $e'), backgroundColor: IrisTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usar a versão atualizada do produto vindo do provider
    final wallet = context.watch<WalletService>();
    final product = wallet.merchantProducts.firstWhere(
      (p) => p.id == widget.product.id,
      orElse: () => widget.product, // fallback caso excluido
    );

    // Produto excluído enquanto esta tela estava aberta: fecha o diálogo. Antes
    // devolvia um Scaffold vazio e o resultado era uma tela preta travada.
    if (!wallet.merchantProducts.any((p) => p.id == widget.product.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
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
                  ProductThumb(product: product, tamanho: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const CurrencyToggleBtn(),
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
                            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 720),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: MerchantProductFormScreen(product: product),
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        exchangeRate.isSatsDisplay
                            ? CurrencyFormatter.formatBtcOrSats(satsAmount)
                            : 'R\$ ${CurrencyFormatter.formatBrlCompact(product.price)}',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(color: IrisTheme.success, fontSize: 42),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      exchangeRate.isSatsDisplay
                          ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(product.price)}'
                          : '≈ ${CurrencyFormatter.formatBtcOrSats(satsAmount)}',
                      style: const TextStyle(fontSize: 15, color: IrisTheme.textSecondary, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 32),
                    
                    if (_isLoading)
                      const CircularProgressIndicator(color: IrisTheme.primary)
                    else if (_invoiceData != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // QR limitado pela largura E pela altura da tela, para
                          // caber no modal em qualquer aparelho (sem overflow).
                          final screenH = MediaQuery.of(context).size.height;
                          final byWidth = constraints.maxWidth - 48;
                          final byHeight = screenH * 0.26;
                          final qrSize =
                              (byWidth < byHeight ? byWidth : byHeight).clamp(160.0, 240.0).toDouble();
                          return Container(
                            width: qrSize + 32,
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
                                  size: qrSize,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: IrisTheme.bg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: IrisTheme.bdr),
                                  ),
                                  child: Text(
                                    _invoiceData!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      height: 1.4,
                                      color: IrisTheme.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    else
                      const SizedBox(),
                    
                    const SizedBox(height: 12),
                    if (_isPaid) ...[
                      const Icon(Icons.check_circle, color: IrisTheme.success, size: 40),
                      const SizedBox(height: 6),
                      const Text(
                        'Pagamento recebido! ⚡',
                        style: TextStyle(color: IrisTheme.success, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ] else
                      // Sem spinner: o texto já indica a espera e o espaço é
                      // curto no modal (evita overflow em telas de celular).
                      const Text(
                        'Aguardando pagamento...',
                        style: TextStyle(color: IrisTheme.primary, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
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
                      if (_invoiceData != null)
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _invoiceData!));
                            // O Android 13+ já exibe o próprio aviso de cópia;
                            // mostrar o nosso duplicaria a notificação.
                            if (!Platform.isAndroid) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Código copiado!')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: IrisTheme.s1,
                            foregroundColor: IrisTheme.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: IrisTheme.bdr),
                          ),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copiar código'),
                        ),
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
