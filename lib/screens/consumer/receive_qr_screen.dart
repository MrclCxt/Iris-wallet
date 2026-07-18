import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import 'custom_charge_screen.dart';

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

  bool? _lastSatsMode;

  @override
  void initState() {
    super.initState();
    if (widget.satsAmount > 0) {
      _startTimer();
      // Invoice generation is now handled in didChangeDependencies
    } else {
      // It's the fixed zero-amount invoice
      _isLoading = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentSatsMode = context.watch<ExchangeRateService>().isSatsDisplay;
    if (_lastSatsMode != currentSatsMode) {
      _lastSatsMode = currentSatsMode;
      setState(() => _isLoading = true);
      _generateInvoice();
    }
  }

  Future<void> _generateInvoice() async {
    final exchangeRate = context.read<ExchangeRateService>();
    final isSatsMode = exchangeRate.isSatsDisplay;
    final amountBrl = exchangeRate.satsToBrl(widget.satsAmount);
    
    try {
      String payload = '';
      if (isSatsMode) {
        final wallet = context.read<WalletService>();
        if (widget.satsAmount > 0) {
          payload = await wallet.createInvoice(
            widget.satsAmount,
            "Receber Lightning",
          );
        } else {
          payload = wallet.mainWalletFixedInvoice ?? 'Carregando...';
        }
      } else {
        final liquidWallet = context.read<LiquidWalletService>();
        final address = await liquidWallet.getReceiveAddress();
        // Liquid URI format with asset parameter for DEPIX (BRL)
        if (widget.satsAmount > 0) {
          payload = 'liquid:$address?amount=$amountBrl&asset=depix';
        } else {
          payload = 'liquid:$address?asset=depix';
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
          SnackBar(content: Text('Erro ao gerar recebimento: $e'), backgroundColor: BitpayTheme.danger),
        );
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
        // optionally navigate back or show expired state
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    if (widget.satsAmount == 0) return '∞ (Sem expiração)';
    final minutes = (_secondsRemaining / 60).floor();
    final seconds = _secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final brlAmount = exchangeRate.satsToBrl(widget.satsAmount);

    return Scaffold(
      backgroundColor: BitpayTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: widget.isStandalone,
        leading: widget.isStandalone ? IconButton(
          icon: const Icon(Icons.arrow_back, color: BitpayTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ) : null,
        title: const Text(
          'Receber Bitcoin',
          style: TextStyle(
            color: BitpayTheme.textPrimary,
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
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: BitpayTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Fatura gerada com sucesso!',
                  style: TextStyle(
                    color: BitpayTheme.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
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
                          color: BitpayTheme.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: BitpayTheme.bdr),
                        ),
                        child: Text(
                          _invoiceData!,
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: BitpayTheme.textSecondary,
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
                  '${CurrencyFormatter.formatSats(widget.satsAmount)} SATS',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: BitpayTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '≈ R\$ ${CurrencyFormatter.formatBrl(brlAmount)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: BitpayTheme.textSecondary,
                  ),
                ),
              ] else ...[
                const Text(
                  'VALOR ABERTO',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: BitpayTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'O pagador definirá o valor',
                  style: TextStyle(
                    fontSize: 14,
                    color: BitpayTheme.textSecondary,
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
                    side: const BorderSide(color: BitpayTheme.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Ou defina um valor específico', style: TextStyle(color: BitpayTheme.primary)),
                ),
              ],
              
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(color: BitpayTheme.primary)),
                )
              else if (_invoiceData != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_tethering, color: BitpayTheme.primary, size: 32),
                        const SizedBox(height: 12),
                        const Text('Aguardando pagamento...', style: TextStyle(color: BitpayTheme.textSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox(height: 24),
              
              Text(
                'Expira em $_formattedTime',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 14,
                  color: _secondsRemaining < 60 ? BitpayTheme.danger : BitpayTheme.textTertiary,
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
                        backgroundColor: BitpayTheme.s1,
                        foregroundColor: BitpayTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: BitpayTheme.bdr),
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
              const SizedBox(height: 10),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
