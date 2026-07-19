import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../core/bolt11.dart';
import '../../core/lnurl.dart';
import '../../services/wallet_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../services/pix_service.dart';
import '../../services/exchange_rate_service.dart';
import 'consumer_pay_success_screen.dart';
import '../pin_screen.dart';

/// Confirmação de pagamento real (testnet):
/// - BOLT11: pago via nó LDK local (trilho padrão do dia a dia)
/// - LNURL: busca a fatura final no callback e paga via LDK
/// - Bitcoin on-chain: grandes valores, direto pela rede base
/// - Liquid: envia L-BTC assinado localmente via LWK
/// - PIX: sats -> DEPIX -> provedor paga o destino em Reais
class PayConfirmScreen extends StatefulWidget {
  final int satsAmount;
  final String destination;
  final String? rawInvoice;
  final LnurlPayParams? lnurlParams;
  final String? liquidAddress;
  final String? btcAddress;
  final String? pixTarget; // chave PIX ou BR Code completo
  final double? pixAmountBrl;
  final bool editableAmount;

  const PayConfirmScreen({
    super.key,
    required this.satsAmount,
    required this.destination,
    this.rawInvoice,
    this.lnurlParams,
    this.liquidAddress,
    this.btcAddress,
    this.pixTarget,
    this.pixAmountBrl,
    this.editableAmount = false,
  });

  @override
  State<PayConfirmScreen> createState() => _PayConfirmScreenState();
}

class _PayConfirmScreenState extends State<PayConfirmScreen> {
  late final TextEditingController _amountCtrl;
  final TextEditingController _pixTaxCtrl = TextEditingController();
  late int _satsAmount;

  bool get _isLiquid => widget.liquidAddress != null;
  bool get _isOnchain => widget.btcAddress != null;
  bool get _isPix => widget.pixTarget != null;

  @override
  void initState() {
    super.initState();
    _satsAmount = widget.satsAmount;
    if (_isPix) {
      // No PIX o valor é em Reais (o custo em sats é derivado do câmbio)
      _amountCtrl = TextEditingController(
          text: widget.pixAmountBrl != null && widget.pixAmountBrl! > 0
              ? widget.pixAmountBrl!.toStringAsFixed(2).replaceAll('.', ',')
              : '');
    } else {
      _amountCtrl = TextEditingController(
          text: _satsAmount > 0 ? _satsAmount.toString() : '');
    }
  }

  double get _pixBrl {
    if (widget.pixAmountBrl != null && !widget.editableAmount) return widget.pixAmountBrl!;
    final raw = _amountCtrl.text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _pixTaxCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: IrisTheme.danger),
    );
  }

  Future<void> _executePayment() async {
    final wallet = context.read<WalletService>();
    final liquid = context.read<LiquidWalletService>();

    if (_isPix) {
      final brl = _pixBrl;
      if (brl <= 0) {
        _showError('Informe o valor em Reais.');
        return;
      }
      final rate = context.read<ExchangeRateService>();
      final satsCost = rate.brlToSats(brl);
      if (satsCost <= 0) {
        rate.fetchRate();
        _showError('Cotação BTC/BRL indisponível. Tente em instantes.');
        return;
      }
      if (wallet.consumerBalance + liquid.balanceSats < satsCost) {
        _showError('Saldo insuficiente (custa ≈ $satsCost sats).');
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator(color: IrisTheme.primary)),
      );
      try {
        await context.read<PixService>().startWithdrawal(
              amountBrl: brl,
              pixTarget: widget.pixTarget!,
              taxNumber: _pixTaxCtrl.text.trim().isEmpty ? null : _pixTaxCtrl.text.trim(),
            );
        if (mounted) {
          Navigator.pop(context);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ConsumerPaySuccessScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          _showError('Falha no envio PIX: $e');
        }
      }
      return;
    }

    if (widget.editableAmount) {
      _satsAmount = int.tryParse(_amountCtrl.text.replaceAll('.', '')) ?? 0;
    }
    if (_satsAmount <= 0) {
      _showError('Informe um valor em sats.');
      return;
    }

    final params = widget.lnurlParams;
    if (params != null &&
        (_satsAmount < params.minSendableSats || _satsAmount > params.maxSendableSats)) {
      _showError(
          'Valor deve estar entre ${params.minSendableSats} e ${params.maxSendableSats} sats.');
      return;
    }

    if (_isLiquid) {
      if (liquid.balanceSats < _satsAmount) {
        _showError('Saldo L-BTC insuficiente!');
        return;
      }
    } else if (_isOnchain) {
      if (wallet.consumerOnchainSats < _satsAmount) {
        _showError('Saldo on-chain insuficiente!');
        return;
      }
    } else if (wallet.consumerLightningSats < _satsAmount) {
      _showError('Saldo Lightning insuficiente!');
      return;
    }

    // Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: IrisTheme.primary)),
    );

    try {
      if (_isLiquid) {
        await liquid.sendLbtc(toAddress: widget.liquidAddress!, sats: _satsAmount);
      } else if (_isOnchain) {
        await wallet.sendOnchain(address: widget.btcAddress!, sats: _satsAmount);
      } else if (params != null) {
        final invoice = await Lnurl.requestInvoice(params, _satsAmount * 1000);
        final parsed = Bolt11.decode(invoice);
        if (parsed.amountSats != null && parsed.amountSats != _satsAmount) {
          throw Exception(
              'Servidor LNURL retornou fatura com valor divergente (${parsed.amountSats} sats).');
        }
        await context.read<WalletService>().payLightningInvoice(invoice);
      } else {
        await wallet.payLightningInvoice(
          widget.rawInvoice!,
          amountSatsOverride: widget.editableAmount ? _satsAmount : null,
        );
      }

      if (mounted) {
        Navigator.pop(context); // fecha loading
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ConsumerPaySuccessScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // fecha loading
        _showError('Falha no pagamento: $e');
      }
    }
  }

  void _confirmWithPin() {
    if (_isPix) {
      if (_pixBrl <= 0) {
        _showError('Informe o valor em Reais antes de confirmar.');
        return;
      }
    } else if (widget.editableAmount) {
      final v = int.tryParse(_amountCtrl.text.replaceAll('.', '')) ?? 0;
      if (v <= 0) {
        _showError('Informe um valor em sats antes de confirmar.');
        return;
      }
      _satsAmount = v;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinScreen(
          mode: PinMode.unlock,
          onSuccess: () async {
            Navigator.pop(context); // pop PIN
            await _executePayment();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final networkLabel = _isPix
        ? 'PIX (Reais via DEPIX/Liquid)'
        : _isLiquid
            ? 'Liquid (testnet)'
            : _isOnchain
                ? 'Bitcoin on-chain (testnet)'
                : 'Lightning (testnet)';

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirmar pagamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: IrisTheme.textPrimary)),
            Text('Verifique antes de pagar', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: IrisTheme.s1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: IrisTheme.bdr),
                ),
                child: Column(
                  children: [
                    const Text('Valor', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                    const SizedBox(height: 4),
                    if (_isPix) ...[
                      if (widget.editableAmount)
                        TextField(
                          controller: _amountCtrl,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            color: IrisTheme.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            prefixText: 'R\$ ',
                            prefixStyle: TextStyle(fontSize: 22, color: IrisTheme.textSecondary),
                            hintText: '0,00',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        )
                      else
                        Text(
                          'R\$ ${CurrencyFormatter.formatBrl(_pixBrl)}',
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 38,
                            fontWeight: FontWeight.w600,
                            color: IrisTheme.textPrimary,
                            height: 1.1,
                          ),
                        ),
                      Text(
                        'custa ≈ ${CurrencyFormatter.formatSats(exchangeRate.brlToSats(_pixBrl))} sats do seu saldo',
                        style: const TextStyle(
                            fontFamily: 'JetBrains Mono', fontSize: 12, color: IrisTheme.primary),
                      ),
                      if (context.watch<PixService>().provider.requiresPayerTaxNumber) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pixTaxCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'CPF/CNPJ do favorecido',
                            hintText: 'Somente números',
                            labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                            hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                            filled: true,
                            fillColor: IrisTheme.bg,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                    ] else if (widget.editableAmount)
                      TextField(
                        controller: _amountCtrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          color: IrisTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: '0',
                          suffixText: 'sats',
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      )
                    else
                      Text(
                        '${CurrencyFormatter.formatSats(_satsAmount)} sats',
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 38,
                          fontWeight: FontWeight.w600,
                          color: IrisTheme.textPrimary,
                          height: 1.1,
                        ),
                      ),
                    if (!_isPix)
                      Text(
                        '≈ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(widget.editableAmount ? (int.tryParse(_amountCtrl.text) ?? 0) : _satsAmount))}',
                        style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: IrisTheme.primary),
                      ),
                    const SizedBox(height: 12),
                    const Divider(color: IrisTheme.bdr),
                    const SizedBox(height: 12),
                    _buildRow('Para', widget.destination, isBold: true),
                    const SizedBox(height: 8),
                    _buildRow('Rede', networkLabel),
                    const SizedBox(height: 8),
                    if (widget.lnurlParams != null) ...[
                      _buildRow('Limites',
                          '${widget.lnurlParams!.minSendableSats} – ${widget.lnurlParams!.maxSendableSats} sats'),
                      const SizedBox(height: 8),
                    ],
                    _buildRow(
                        'Taxa estimada',
                        _isPix
                            ? 'taxa do provedor DEPIX'
                            : _isLiquid
                                ? '~0,1 sat/vB'
                                : _isOnchain
                                    ? 'taxa de mineração (on-chain)'
                                    : 'roteamento LN',
                        valueColor: IrisTheme.success,
                        isBold: true),
                    if (_isOnchain) ...[
                      const SizedBox(height: 8),
                      _buildRow('Confirmação', '~10 min por bloco'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: IrisTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                ),
                child: const Text(
                  'Depois de confirmar não é possível cancelar. Verifique o destino.',
                  style: TextStyle(fontSize: 12, color: IrisTheme.primary, height: 1.5),
                ),
              ),
              const Spacer(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirmWithPin,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Confirmar com PIN'),
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

  Widget _buildRow(String label, String value, {Color valueColor = IrisTheme.textPrimary, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: valueColor, fontWeight: isBold ? FontWeight.w600 : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
