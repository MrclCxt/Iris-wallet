import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../core/bolt11.dart';
import '../../core/tx_policy.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import 'custom_charge_screen.dart';
import 'pix_deposit_screen.dart';

/// Método de recebimento. A moeda do app é sempre o satoshi — o toggle
/// SATS/R$ muda apenas a exibição, nunca o trilho da transação.
enum ReceiveMethod { lightning, onchain }

class ReceiveQrScreen extends StatefulWidget {
  final int satsAmount;
  final bool isMerchant;
  final bool isStandalone;

  const ReceiveQrScreen({
    super.key,
    required this.satsAmount,
    this.isMerchant = false,
    this.isStandalone = false,
  });

  @override
  State<ReceiveQrScreen> createState() => _ReceiveQrScreenState();
}

class _ReceiveQrScreenState extends State<ReceiveQrScreen> {
  int _secondsRemaining = 3600; // 60 minutes
  Timer? _timer;
  String? _invoiceData;
  bool _isLoading = true;
  bool _isPaid = false;
  int _paidAmountSats = 0;
  String? _watchingPaymentHash;
  StreamSubscription<ReceivedPayment>? _paymentSub;

  ReceiveMethod _method = ReceiveMethod.lightning;

  @override
  void initState() {
    super.initState();
    // Política de roteamento: grandes valores vão pela rede Bitcoin (on-chain)
    if (widget.satsAmount > 0 && TxPolicy.shouldUseOnchain(widget.satsAmount)) {
      _method = ReceiveMethod.onchain;
    }
    if (widget.satsAmount > 0) {
      _startTimer();
    } else {
      _isLoading = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _generatePayload());

    // Detecção real de recebimento: eventos do nó LDK (Lightning e on-chain)
    _paymentSub = context.read<WalletService>().paymentsReceived.listen((payment) {
      if (!mounted || _isPaid) return;
      if (payment.isMerchant != widget.isMerchant) return;
      final hashMatches = _watchingPaymentHash != null &&
          payment.paymentHashHex == _watchingPaymentHash;
      final onchainMatches = _method == ReceiveMethod.onchain && payment.isOnchain;
      final openInvoiceMatches =
          _method == ReceiveMethod.lightning && _watchingPaymentHash == null && !payment.isOnchain;
      if (hashMatches || onchainMatches || openInvoiceMatches) {
        setState(() {
          _isPaid = true;
          _paidAmountSats = payment.amountSats;
        });
        _timer?.cancel();
      }
    });
  }

  Future<void> _generatePayload() async {
    setState(() => _isLoading = true);
    try {
      String payload = '';
      final wallet = context.read<WalletService>();

      if (_method == ReceiveMethod.lightning) {
        if (widget.satsAmount > 0) {
          payload = await wallet.createInvoice(
            widget.satsAmount,
            widget.isMerchant ? 'Cobrança da loja' : 'Receber Lightning',
            forMerchant: widget.isMerchant,
          );
        } else {
          payload = (widget.isMerchant
                  ? wallet.merchantFixedInvoice
                  : wallet.mainWalletFixedInvoice) ??
              'Carregando...';
        }
        if (Bolt11.looksLikeInvoice(payload)) {
          try {
            _watchingPaymentHash = Bolt11.decode(payload).paymentHashHex;
          } catch (_) {
            _watchingPaymentHash = null;
          }
        } else {
          _watchingPaymentHash = null;
        }
      } else {
        // Recebimento puro pela rede Bitcoin (on-chain, testnet)
        final address = await wallet.getOnchainAddress(forMerchant: widget.isMerchant);
        _watchingPaymentHash = null;
        if (widget.satsAmount > 0) {
          final btc = (widget.satsAmount / 100000000).toStringAsFixed(8);
          payload = 'bitcoin:$address?amount=$btc';
        } else {
          payload = address;
        }
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
          SnackBar(content: Text('Erro ao gerar recebimento: $e'), backgroundColor: IrisTheme.danger),
        );
      }
    }
  }

  void _switchMethod(ReceiveMethod method) {
    if (_method == method) return;
    setState(() {
      _method = method;
      _invoiceData = null;
    });
    _generatePayload();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _paymentSub?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    if (_method == ReceiveMethod.onchain || widget.satsAmount == 0) {
      return '∞ (Sem expiração)';
    }
    final minutes = (_secondsRemaining / 60).floor();
    final seconds = _secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final showSats = exchangeRate.isSatsDisplay;
    final brlAmount = exchangeRate.satsToBrl(widget.satsAmount);

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: widget.isStandalone,
        leading: widget.isStandalone ? IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ) : null,
        title: const Text(
          'Receber Bitcoin',
          style: TextStyle(
            color: IrisTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: CurrencyToggleBtn(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Seletor do trilho de recebimento (sempre em sats)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: IrisTheme.s2,
                  border: Border.all(color: IrisTheme.bdr2),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMethodBtn('⚡ Lightning', ReceiveMethod.lightning),
                    _buildMethodBtn('₿ On-chain', ReceiveMethod.onchain),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_method == ReceiveMethod.onchain)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: IrisTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Endereço Bitcoin testnet — confirmação em ~10 min por bloco',
                    style: TextStyle(color: IrisTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: IrisTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Fatura Lightning gerada — liquidação instantânea',
                    style: TextStyle(
                      color: IrisTheme.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              if (_invoiceData != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: _invoiceData!,
                        version: QrVersions.auto,
                        size: 240.0,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
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
                ),

              const SizedBox(height: 24),

              if (widget.satsAmount > 0) ...[
                Text(
                  showSats
                      ? '${CurrencyFormatter.formatSats(widget.satsAmount)} SATS'
                      : 'R\$ ${CurrencyFormatter.formatBrl(brlAmount)}',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: IrisTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  showSats
                      ? '≈ R\$ ${CurrencyFormatter.formatBrl(brlAmount)}'
                      : '≈ ${CurrencyFormatter.formatSats(widget.satsAmount)} sats',
                  style: const TextStyle(
                    fontSize: 14,
                    color: IrisTheme.textSecondary,
                  ),
                ),
              ] else ...[
                const Text(
                  'VALOR ABERTO',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: IrisTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'O pagador definirá o valor',
                  style: TextStyle(
                    fontSize: 14,
                    color: IrisTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomChargeScreen(isMerchant: widget.isMerchant),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: IrisTheme.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Ou defina um valor específico', style: TextStyle(color: IrisTheme.primary)),
                ),
              ],

              if (_isPaid)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: IrisTheme.success, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Pagamento recebido! ⚡ ${CurrencyFormatter.formatSats(_paidAmountSats)} sats',
                          style: const TextStyle(color: IrisTheme.success, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(color: IrisTheme.primary)),
                )
              else if (_invoiceData != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_tethering, color: IrisTheme.primary, size: 32),
                        const SizedBox(height: 12),
                        const Text('Aguardando pagamento...', style: TextStyle(color: IrisTheme.textSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox(height: 24),

              if (!_isPaid)
              Text(
                'Expira em $_formattedTime',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 14,
                  color: _secondsRemaining < 60 ? IrisTheme.danger : IrisTheme.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final invToCopy = _invoiceData;
                        if (invToCopy != null) {
                          Clipboard.setData(ClipboardData(text: invToCopy));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código copiado!')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: IrisTheme.s1,
                        foregroundColor: IrisTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: IrisTheme.bdr),
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (_invoiceData != null) {
                            Share.share(_invoiceData!);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.share, size: 18, color: Colors.black),
                        label: const Text('Compartilhar'),
                      ),
                    ),
                  ),
                ],
              ),

              if (!widget.isMerchant) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const PixDepositScreen()),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: IrisTheme.success),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Text('🇧🇷', style: TextStyle(fontSize: 16)),
                    label: const Text(
                      'PIX — receber ou enviar Reais',
                      style: TextStyle(color: IrisTheme.success, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildMethodBtn(String label, ReceiveMethod method) {
    final isOn = _method == method;
    return GestureDetector(
      onTap: () => _switchMethod(method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: isOn ? IrisTheme.brandGradient : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isOn ? Colors.white : IrisTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
