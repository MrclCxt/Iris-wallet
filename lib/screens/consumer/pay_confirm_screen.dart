import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../core/bolt11.dart';
import '../../core/lnurl.dart';
import '../../core/tx_policy.dart';
import '../../services/wallet_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../services/pix_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/chroma_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/numpad.dart';
import '../../widgets/max_width_container.dart';
import 'consumer_pay_success_screen.dart';
import '../pin_screen.dart';

class PayConfirmScreen extends StatefulWidget {
  final int satsAmount;
  final String destination;
  final String? rawInvoice;
  final LnurlPayParams? lnurlParams;
  final String? liquidAddress;
  final String? btcAddress;
  final String? pixTarget;
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

  ExchangeRateService? _rate;
  bool _lastShowSats = true;

  Timer? _idleTimer;
  bool _amountEditing = true;
  final FocusNode _amountFocus = FocusNode();

  bool get _isLiquid => widget.liquidAddress != null;
  bool get _isOnchain => widget.btcAddress != null;
  bool get _isPix => widget.pixTarget != null;

  @override
  void initState() {
    super.initState();
    _satsAmount = widget.satsAmount;
    if (_isPix) {
      _amountCtrl = TextEditingController(
          text: widget.pixAmountBrl != null && widget.pixAmountBrl! > 0
              ? CurrencyFormatter.formatBrl(widget.pixAmountBrl!)
              : '');
    } else {
      _amountCtrl = TextEditingController(
          text:
              _satsAmount > 0 ? CurrencyFormatter.formatSats(_satsAmount) : '');
    }

    _amountEditing = _amountCtrl.text.isEmpty;

    _amountCtrl.addListener(_onAmountTyped);
    _amountFocus.addListener(_onAmountFocusChange);
  }

  void _onAmountTyped() {
    if (!_amountFocus.hasFocus) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _amountCtrl.text.isNotEmpty) {
        setState(() => _amountEditing = false);
      }
    });
    if (mounted) setState(() => _amountEditing = true);
  }

  void _onAmountFocusChange() {
    if (!_amountFocus.hasFocus &&
        _amountEditing &&
        _amountCtrl.text.isNotEmpty) {
      _idleTimer?.cancel();
      if (mounted) setState(() => _amountEditing = false);
    }
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _amountCtrl.text.isNotEmpty) {
        setState(() => _amountEditing = false);
      }
    });
  }

  void _numpadKey(String key) {
    final showSats = _rate?.isSatsDisplay ?? true;
    if (key == ',' && showSats) return;
    final fmt = _AmountInputFormatter(decimal: !showSats);
    final appended = _amountCtrl.text + key;
    _amountCtrl.value = fmt.formatEditUpdate(
      _amountCtrl.value,
      TextEditingValue(
        text: appended,
        selection: TextSelection.collapsed(offset: appended.length),
      ),
    );
    _amountEditing = true;
    _scheduleIdle();
    setState(() {});
  }

  void _numpadBackspace() {
    if (_amountCtrl.text.isEmpty) return;
    final showSats = _rate?.isSatsDisplay ?? true;
    final fmt = _AmountInputFormatter(decimal: !showSats);
    final trimmed = _amountCtrl.text.substring(0, _amountCtrl.text.length - 1);
    _amountCtrl.value = fmt.formatEditUpdate(
      _amountCtrl.value,
      TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      ),
    );
    _amountEditing = true;
    _scheduleIdle();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rate = context.read<ExchangeRateService>();
    if (!identical(_rate, rate)) {
      _rate?.removeListener(_onCurrencyToggle);
      _rate = rate;
      _lastShowSats = rate.isSatsDisplay;
      _rate!.addListener(_onCurrencyToggle);
    }
  }

  void _onCurrencyToggle() {
    final rate = _rate;
    if (rate == null || rate.isSatsDisplay == _lastShowSats) return;
    final wasSats = _lastShowSats;
    _lastShowSats = rate.isSatsDisplay;

    if (_isPix || !widget.editableAmount) {
      if (mounted) setState(() {});
      return;
    }
    if (wasSats) {
      final sats = int.tryParse(_amountCtrl.text.replaceAll('.', '')) ?? 0;
      _amountCtrl.text =
          sats > 0 ? CurrencyFormatter.formatBrl(rate.satsToBrl(sats)) : '';
    } else {
      final raw = _amountCtrl.text.replaceAll('.', '').replaceAll(',', '.');
      final brl = double.tryParse(raw) ?? 0;
      final sats = rate.brlToSats(brl);
      _amountCtrl.text = sats > 0 ? CurrencyFormatter.formatSats(sats) : '';
    }
    if (mounted) setState(() {});
  }

  int _currentSats(ExchangeRateService rate) {
    if (rate.isSatsDisplay) {
      return int.tryParse(_amountCtrl.text.replaceAll('.', '')) ?? 0;
    }
    final raw = _amountCtrl.text.replaceAll('.', '').replaceAll(',', '.');
    final brl = double.tryParse(raw) ?? 0;
    return rate.brlToSats(brl);
  }

  double get _pixBrl {
    if (widget.pixAmountBrl != null && !widget.editableAmount) {
      return widget.pixAmountBrl!;
    }
    final raw = _amountCtrl.text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  int _availableSats(WalletService wallet, LiquidWalletService liquid) {
    if (_isPix) return liquid.balanceSats;
    if (_isLiquid) return liquid.balanceSats;
    if (_isOnchain) return wallet.consumerOnchainSats;
    return wallet.consumerLightningSats;
  }

  int _amountSats(ExchangeRateService rate) {
    if (_isPix) return rate.brlToSats(_pixBrl);
    return widget.editableAmount ? _currentSats(rate) : _satsAmount;
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _amountFocus.removeListener(_onAmountFocusChange);
    _amountFocus.dispose();
    _rate?.removeListener(_onCurrencyToggle);
    _amountCtrl.removeListener(_onAmountTyped);
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

      if (liquid.balanceSats < satsCost) {
        if (wallet.consumerBalance >= satsCost) {
          _showError(
              'Você tem ${wallet.consumerBalance} sats em Lightning, mas o saque '
              'PIX sai da carteira Liquid, que tem ${liquid.balanceSats} sats. '
              'A conversão de Lightning para Liquid ainda não está disponível.');
        } else {
          _showError(
              'Saldo Liquid insuficiente: custa ≈ $satsCost sats e há ${liquid.balanceSats}.');
        }
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
            child: CircularProgressIndicator(color: IrisTheme.primary)),
      );
      try {
        await context.read<PixService>().startWithdrawal(
              amountBrl: brl,
              pixTarget: widget.pixTarget!,
              taxNumber: _pixTaxCtrl.text.trim().isEmpty
                  ? null
                  : _pixTaxCtrl.text.trim(),
            );
        if (mounted) {
          Navigator.pop(context);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => const ConsumerPaySuccessScreen()),
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
      _satsAmount = _currentSats(context.read<ExchangeRateService>());
    }
    if (_satsAmount <= 0) {
      _showError('Informe um valor.');
      return;
    }

    final params = widget.lnurlParams;
    if (params != null &&
        (_satsAmount < params.minSendableSats ||
            _satsAmount > params.maxSendableSats)) {
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
          child: CircularProgressIndicator(color: IrisTheme.primary)),
    );

    try {
      if (_isLiquid) {
        await liquid.sendLbtc(
            toAddress: widget.liquidAddress!, sats: _satsAmount);
      } else if (_isOnchain) {
        await wallet.sendOnchain(
            address: widget.btcAddress!, sats: _satsAmount);
      } else if (params != null) {
        final invoice = await Lnurl.requestInvoice(params, _satsAmount * 1000);
        final parsed = Bolt11.decode(invoice);
        if (parsed.amountSats != null && parsed.amountSats != _satsAmount) {
          throw Exception(
              'Servidor LNURL retornou fatura com valor divergente (${parsed.amountSats} sats).');
        }
        await wallet.payLightningInvoice(invoice);
      } else {
        await wallet.payLightningInvoice(
          widget.rawInvoice!,
          amountSatsOverride: widget.editableAmount ? _satsAmount : null,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const ConsumerPaySuccessScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
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
      final v = _currentSats(context.read<ExchangeRateService>());
      if (v <= 0) {
        _showError('Informe um valor antes de confirmar.');
        return;
      }
      _satsAmount = v;
    }

    if (!_isPix &&
        !_isOnchain &&
        !_isLiquid &&
        TxPolicy.isBtcScale(_satsAmount)) {
      _showError(
          'Valores a partir de 1 BTC só podem ser enviados on-chain (rede Bitcoin). Use um endereço Bitcoin.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinScreen(
          mode: PinMode.unlock,
          onSuccess: () async {
            Navigator.pop(context);
            await _executePayment();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final wallet = context.watch<WalletService>();
    final liquid = context.watch<LiquidWalletService>();
    final networkLabel = _isPix
        ? 'PIX (Reais via DEPIX/Liquid)'
        : _isLiquid
            ? 'Liquid (testnet)'
            : _isOnchain
                ? 'Bitcoin on-chain (testnet4)'
                : 'Lightning (testnet4)';

    final availableSats = _availableSats(wallet, liquid);
    final amountSats = _amountSats(exchangeRate);
    final insufficient = amountSats > 0 && amountSats > availableSats;
    final availableLabel = exchangeRate.isSatsDisplay
        ? CurrencyFormatter.formatBtcOrSats(availableSats)
        : 'R\$ ${CurrencyFormatter.formatBrlCompact(exchangeRate.satsToBrl(availableSats))}';

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
            Text('Confirmar envio',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: IrisTheme.textPrimary)),
            Text('Verifique antes de enviar',
                style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: CurrencyToggleBtn(ocultarSemPix: true),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: MaxWidthContainer(
              maxWidth: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBalanceHeader(context, exchangeRate, availableSats,
                      availableLabel, insufficient),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: IrisTheme.s1,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: IrisTheme.bdr),
                    ),
                    child: Column(
                      children: [
                        const Text('Valor',
                            style: TextStyle(
                                fontSize: 11, color: IrisTheme.textSecondary)),
                        const SizedBox(height: 4),
                        if (_isPix) ...[
                          if (widget.editableAmount)
                            TextField(
                              controller: _amountCtrl,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9,.]'))
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: IrisTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                prefixText: 'R\$ ',
                                prefixStyle: TextStyle(
                                    fontSize: 22,
                                    color: IrisTheme.textSecondary),
                                hintText: '0,00',
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => setState(() {}),
                            )
                          else
                            Text(
                              'R\$ ${CurrencyFormatter.formatBrl(_pixBrl)}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 38,
                                fontWeight: FontWeight.w600,
                                color: IrisTheme.textPrimary,
                                height: 1.1,
                              ),
                            ),
                          Text(
                            'custa ≈ ${CurrencyFormatter.formatBtcOrSats(exchangeRate.brlToSats(_pixBrl))} do seu saldo',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: IrisTheme.primary),
                          ),
                          if (context
                              .watch<PixService>()
                              .provider
                              .requiresPayerTaxNumber) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pixTaxCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: IrisTheme.textPrimary, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'CPF/CNPJ do favorecido',
                                hintText: 'Somente números',
                                labelStyle: const TextStyle(
                                    color: IrisTheme.textSecondary),
                                hintStyle: const TextStyle(
                                    color: IrisTheme.textTertiary),
                                filled: true,
                                fillColor: IrisTheme.bg,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none),
                              ),
                            ),
                          ],
                        ] else if (widget.editableAmount)
                          _buildEditableAmount(exchangeRate)
                        else
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              exchangeRate.isSatsDisplay
                                  ? CurrencyFormatter.formatBtcOrSats(
                                      _satsAmount)
                                  : 'R\$ ${CurrencyFormatter.formatBrlCompact(exchangeRate.satsToBrl(_satsAmount))}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 38,
                                fontWeight: FontWeight.w600,
                                color: IrisTheme.textPrimary,
                                height: 1.1,
                              ),
                            ),
                          ),
                        if (!_isPix)
                          Builder(builder: (context) {
                            final sats = widget.editableAmount
                                ? _currentSats(exchangeRate)
                                : _satsAmount;

                            return Text(
                              exchangeRate.isSatsDisplay
                                  ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(exchangeRate.satsToBrl(sats))}'
                                  : '≈ ${CurrencyFormatter.formatBtcOrSats(sats)}',
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: IrisTheme.primary),
                            );
                          }),
                        const SizedBox(height: 12),
                        const Divider(color: IrisTheme.bdr),
                        const SizedBox(height: 12),
                        _buildEnderecos(wallet),
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
                  if (widget.editableAmount && !_isPix) ...[
                    const SizedBox(height: 20),
                    Numpad(
                      onKeyPress: _numpadKey,
                      onBackspace: _numpadBackspace,
                      showDecimal: !exchangeRate.isSatsDisplay,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: IrisTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                    ),
                    child: const Text(
                      'Depois de confirmar não é possível cancelar. Verifique o destino.',
                      style: TextStyle(
                          fontSize: 12, color: IrisTheme.primary, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: insufficient ? null : _confirmWithPin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        textStyle: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                        disabledBackgroundColor: IrisTheme.s3,
                        disabledForegroundColor: IrisTheme.textTertiary,
                      ),
                      child: Text(insufficient
                          ? 'Saldo insuficiente'
                          : 'Confirmar com PIN'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceHeader(BuildContext context, ExchangeRateService rate,
      int availableSats, String availableLabel, bool insufficient) {
    final chroma = context.watch<ChromaService>();
    final brl = rate.satsToBrl(availableSats);
    const bigStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 40,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    return Column(
      children: [
        const Text(
          'SALDO DISPONÍVEL',
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
          child: insufficient
              ? Text(availableLabel,
                  style: bigStyle.copyWith(color: IrisTheme.danger))
              : ShaderMask(
                  shaderCallback: (b) =>
                      chroma.spectrumGradient.createShader(b.inflate(2)),
                  child: Text(availableLabel, style: bigStyle),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          rate.isSatsDisplay
              ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(brl)}'
              : '≈ ${CurrencyFormatter.formatBtcOrSats(availableSats)}',
          style: const TextStyle(fontSize: 12, color: IrisTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildEditableAmount(ExchangeRateService rate) {
    final showSats = rate.isSatsDisplay;
    const numStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 32,
      fontWeight: FontWeight.w600,
      color: IrisTheme.textPrimary,
    );
    const unitStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: IrisTheme.textSecondary,
    );

    if (!_amountEditing && _amountCtrl.text.isNotEmpty) {
      final String display;
      if (showSats) {
        display = CurrencyFormatter.formatBtcOrSats(_currentSats(rate));
      } else {
        final brl = double.tryParse(
                _amountCtrl.text.replaceAll('.', '').replaceAll(',', '.')) ??
            0;
        display = 'R\$ ${CurrencyFormatter.formatBrlCompact(brl)}';
      }
      return GestureDetector(
        onTap: () {
          setState(() => _amountEditing = true);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _amountFocus.requestFocus());
        },
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(display, style: numStyle),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!showSats)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text('R\$', style: unitStyle),
            ),
          IntrinsicWidth(
            child: TextField(
              controller: _amountCtrl,
              focusNode: _amountFocus,
              readOnly: true,
              showCursor: _amountCtrl.text.isNotEmpty,
              inputFormatters: [_AmountInputFormatter(decimal: !showSats)],
              textAlign: TextAlign.center,
              style: numStyle,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: showSats ? '0' : '0,00',
                hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                border: InputBorder.none,
              ),
            ),
          ),
          if (showSats)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('sats', style: unitStyle),
            ),
        ],
      ),
    );
  }

  String _agrupar(String endereco) {
    final buf = StringBuffer();
    for (var i = 0; i < endereco.length; i += 4) {
      if (i > 0) buf.write(' ');
      buf.write(endereco.substring(
          i, i + 4 > endereco.length ? endereco.length : i + 4));
    }
    return buf.toString();
  }

  Widget _buildEnderecos(WalletService wallet) {
    final destino = widget.btcAddress ?? widget.destination;
    final nomeDestino =
        _isOnchain ? wallet.nomeDaCarteiraDoEndereco(destino) : null;
    final ehMinha = nomeDestino != null;
    final origem = wallet.activeConsumer?.name ?? 'Carteira pessoal';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow('Saindo de', origem, isBold: true),
        const SizedBox(height: 8),
        _buildRow(
          'Indo para',
          ehMinha ? 'Sua carteira: $nomeDestino' : 'Carteira externa',
          valueColor: ehMinha ? IrisTheme.warning : IrisTheme.textPrimary,
          isBold: true,
        ),
        const SizedBox(height: 10),
        const Text('Endereço de destino',
            style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: IrisTheme.bg,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: ehMinha ? IrisTheme.warning : IrisTheme.bdr),
          ),
          child: SelectableText(
            _isOnchain ? _agrupar(destino) : destino,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: IrisTheme.textPrimary,
            ),
          ),
        ),
        if (ehMinha) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: IrisTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: IrisTheme.warning.withOpacity(0.45)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: IrisTheme.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Este endereço é de uma carteira SUA',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: IrisTheme.warning),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Seus perfis compartilham a mesma frase semente, então '
                        'enviar aqui não move o dinheiro para outro lugar: o '
                        'saldo continua seu e você paga a taxa de mineração à toa.',
                        style: TextStyle(
                            fontSize: 11, color: IrisTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(String label, String value,
      {Color valueColor = IrisTheme.textPrimary, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
                fontSize: 12,
                color: valueColor,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AmountInputFormatter extends TextInputFormatter {
  final bool decimal;
  const _AmountInputFormatter({required this.decimal});

  static const int _maxSats = 2100000000000000;
  static const int _maxBrlIntDigits = 13;

  String _group(String digits) {
    final b = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
      b.write(digits[i]);
    }
    return b.toString();
  }

  String _stripLeadingZeros(String d) =>
      d.replaceFirst(RegExp(r'^0+(?=\d)'), '');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    if (!decimal) {
      final digits =
          _stripLeadingZeros(newValue.text.replaceAll(RegExp(r'[^0-9]'), ''));
      if (digits.length > 16) return oldValue;
      final v = int.tryParse(digits.isEmpty ? '0' : digits) ?? 0;
      if (v > _maxSats) return oldValue;
      final out = _group(digits);
      return TextEditingValue(
        text: out,
        selection: TextSelection.collapsed(offset: out.length),
      );
    }

    final text = newValue.text.replaceAll('.', '');
    final commaIdx = text.indexOf(',');
    String intPart, out;
    if (commaIdx >= 0) {
      intPart = _stripLeadingZeros(
          text.substring(0, commaIdx).replaceAll(RegExp(r'[^0-9]'), ''));
      if (intPart.length > _maxBrlIntDigits) return oldValue;
      var dec = text.substring(commaIdx + 1).replaceAll(RegExp(r'[^0-9]'), '');
      if (dec.length > 2) dec = dec.substring(0, 2);
      out = '${_group(intPart.isEmpty ? '0' : intPart)},$dec';
    } else {
      intPart = _stripLeadingZeros(text.replaceAll(RegExp(r'[^0-9]'), ''));
      if (intPart.length > _maxBrlIntDigits) return oldValue;
      out = _group(intPart);
    }
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}
