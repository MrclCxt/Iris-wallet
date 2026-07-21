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
import '../../services/liquid_wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/pix_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/max_width_container.dart';
import '../../widgets/numpad.dart';
import 'custom_charge_screen.dart';

/// Trilho de recebimento. A moeda do app é sempre o satoshi — o toggle
/// SATS/R$ muda apenas a exibição. PIX é o trilho de entrada de Reais:
/// PIX (BRL) -> DEPIX (Liquid) -> L-BTC -> saldo em sats.
enum ReceiveMethod { lightning, onchain, pix }

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
  String? _errorMessage; // erro de geração do QR (exibido centralizado)
  bool _isLoading = true;
  bool _isPaid = false;
  int _paidAmountSats = 0;
  String? _watchingPaymentHash;
  StreamSubscription<ReceivedPayment>? _paymentSub;
  final TextEditingController _pixBrlCtrl = TextEditingController();
  final TextEditingController _pixCpfCtrl = TextEditingController();
  bool _pixBusy = false;
  bool _pixShowAmountForm = false;
  bool _pixStaticReceived = false;
  int _pixReceivedSats = 0;
  StreamSubscription<int>? _lbtcSub;
  Timer? _paidResetTimer; // após mostrar "recebido", limpa o aviso / volta ao fixo

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
        _schedulePaidReset();
      }
    });

    // Detecção de DEPIX/L-BTC chegando na Liquid (QR PIX fixo pago)
    _lbtcSub = context.read<LiquidWalletService>().lbtcReceived.listen((sats) {
      if (!mounted || _method != ReceiveMethod.pix) return;
      setState(() {
        _pixStaticReceived = true;
        _pixReceivedSats = sats;
      });
      _schedulePaidReset();
    });
  }

  /// Depois de exibir "recebido" por alguns segundos, o aviso some. Se era um
  /// valor específico, o QR volta para o fixo (ou a tela dedicada fecha).
  void _schedulePaidReset() {
    _paidResetTimer?.cancel();
    _paidResetTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      // Tela dedicada de valor específico (Lightning/on-chain): volta ao fixo.
      if (widget.isStandalone && widget.satsAmount > 0) {
        Navigator.pop(context);
        return;
      }
      // Cobrança PIX específica: limpa para voltar ao QR PIX fixo.
      final pix = context.read<PixService>();
      if (pix.activeCharge != null) pix.clearActiveCharge();
      setState(() {
        _isPaid = false;
        _pixStaticReceived = false;
        _pixShowAmountForm = false;
        _invoiceData = null;
      });
      // Regenera o QR fixo (BOLT11 é de uso único).
      if (_method != ReceiveMethod.pix) _generatePayload();
    });
  }

  Future<void> _generatePayload() async {
    if (_method == ReceiveMethod.pix) return; // painel PIX cuida do próprio QR
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
          // Fatura fixa persistida; gerada sob demanda se o nó já subiu mas
          // ela ainda não existe (evita o erro "indisponível" no boot).
          payload = await wallet.getFixedInvoice(forMerchant: widget.isMerchant);
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
        setState(() {
          _isLoading = false;
          _invoiceData = null;
          _errorMessage = _friendlyError(e);
        });
      }
    }
  }

  /// Remove o prefixo "Exception:" das mensagens para exibição.
  String _friendlyError(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  // Teclado numérico do valor do PIX (baseado em centavos, igual à tela de
  // valor específico de Lightning/on-chain).
  void _pixNumKey(String k) {
    if (k == ',') return; // vírgula automática (centavos)
    final digits = _pixBrlCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 12) return;
    final cents = int.tryParse(digits + k) ?? 0;
    _pixBrlCtrl.text = cents > 0 ? CurrencyFormatter.formatBrl(cents / 100.0) : '';
    setState(() {});
  }

  void _pixNumBack() {
    final digits = _pixBrlCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.isEmpty ? '' : digits.substring(0, digits.length - 1);
    final cents = int.tryParse(trimmed) ?? 0;
    _pixBrlCtrl.text = cents > 0 ? CurrencyFormatter.formatBrl(cents / 100.0) : '';
    setState(() {});
  }

  /// Erro de geração do QR: mensagem centralizada (horizontal e vertical) no
  /// espaço visível, no lugar onde o QR apareceria — sem alterar a estrutura.
  Widget _buildCenteredError(String message) {
    final h = (MediaQuery.of(context).size.height * 0.5).clamp(240.0, 460.0);
    return SizedBox(
      height: h,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: IrisTheme.danger, size: 44),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: IrisTheme.danger, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _generatePayload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tentar novamente'),
              style: OutlinedButton.styleFrom(
                foregroundColor: IrisTheme.primary,
                side: const BorderSide(color: IrisTheme.primary),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _switchMethod(ReceiveMethod method) {
    if (_method == method) return;
    setState(() {
      _method = method;
      _invoiceData = null;
      _errorMessage = null;
      _isLoading = method != ReceiveMethod.pix;
    });
    if (method == ReceiveMethod.pix) {
      if (widget.satsAmount > 0) {
        // Cobrança com valor definido (fluxo vindo do "definir valor")
        _maybeAutoCreatePixCharge();
      } else {
        // Padrão: QR PIX fixo da carteira (pagador define o valor).
        // Provedores só-cobrança (ex.: DePix App) caem direto no formulário.
        final pix = context.read<PixService>();
        if (!pix.provider.supportsStaticQr) {
          _pixShowAmountForm = true;
        } else {
          _pixShowAmountForm = false;
          pix.ensureStaticDeposit().catchError((e) {
            if (mounted) setState(() => _pixShowAmountForm = true);
            return PixCharge(id: 'erro', amountBrl: 0, qrCopiaECola: '');
          });
        }
      }
    } else {
      _generatePayload();
    }
  }

  /// Com valor definido, gera a cobrança PIX automaticamente no equivalente
  /// em Reais (câmbio em tempo real).
  Future<void> _maybeAutoCreatePixCharge() async {
    if (widget.satsAmount <= 0) return;
    final pix = context.read<PixService>();
    final rate = context.read<ExchangeRateService>();
    if (!rate.hasRate) {
      rate.fetchRate();
      return;
    }
    final brl = rate.satsToBrl(widget.satsAmount);
    if (pix.activeCharge != null &&
        pix.activeCharge!.status == PixChargeStatus.pending &&
        (pix.activeCharge!.amountBrl - brl).abs() < 0.01) {
      return; // cobrança equivalente já ativa
    }
    setState(() => _pixBusy = true);
    try {
      await pix.startDeposit(double.parse(brl.toStringAsFixed(2)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar cobrança PIX: $e'), backgroundColor: IrisTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _pixBusy = false);
    }
  }

  Future<void> _createPixChargeFromInput() async {
    final raw = _pixBrlCtrl.text.replaceAll('.', '').replaceAll(',', '.');
    final brl = double.tryParse(raw) ?? 0;
    if (brl <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o valor em Reais.'), backgroundColor: IrisTheme.danger),
      );
      return;
    }
    final rate = context.read<ExchangeRateService>();
    if (!rate.hasRate) {
      rate.fetchRate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cotação BTC/BRL indisponível. Tente em instantes.'),
            backgroundColor: IrisTheme.danger),
      );
      return;
    }
    final pix = context.read<PixService>();
    if (pix.provider.requiresPayerTaxNumber && _pixCpfCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe o CPF/CNPJ do pagador (exigência do provedor).'),
            backgroundColor: IrisTheme.danger),
      );
      return;
    }
    setState(() => _pixBusy = true);
    try {
      await pix.startDeposit(brl, payerTaxNumber: _pixCpfCtrl.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar cobrança PIX: $e'), backgroundColor: IrisTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _pixBusy = false);
    }
  }

  void _showPixProviderConfig() {
    final pix = context.read<PixService>();
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    String selectedType = pix.provider is DepixAppProvider
        ? 'depixapp'
        : pix.provider is RestPixProvider
            ? 'rest'
            : 'sim';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: IrisTheme.s1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: IrisTheme.bdr),
          ),
          title: const Text('Provedor PIX/DEPIX',
              style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Atual: ${pix.provider.name}',
                  style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                dropdownColor: IrisTheme.s2,
                style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
                decoration: const InputDecoration(labelText: 'Provedor'),
                items: const [
                  DropdownMenuItem(value: 'depixapp', child: Text('DePix App (recomendado)')),
                  DropdownMenuItem(value: 'rest', child: Text('REST genérico')),
                  DropdownMenuItem(value: 'sim', child: Text('Simulado (sem provedor)')),
                ],
                onChanged: (v) => setStateDialog(() => selectedType = v ?? 'sim'),
              ),
              const SizedBox(height: 8),
              if (selectedType == 'rest')
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'URL base da API',
                    hintText: 'https://api.provedor.com/v1',
                  ),
                ),
              if (selectedType != 'sim')
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: selectedType == 'depixapp'
                        ? 'Chave de API (sk_test_... ou sk_live_...)'
                        : 'Chave de API',
                  ),
                ),
              if (selectedType == 'depixapp') ...[
                const SizedBox(height: 8),
                const Text(
                  'Crie a conta em depixapp.com → Dashboard → API Keys. A chave sk_test_ (sandbox) sai na hora; a sk_live_ move Reais de verdade e exige aprovação. Configure seu endereço Liquid no dashboard.',
                  style: TextStyle(color: IrisTheme.textTertiary, fontSize: 11, height: 1.4),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: IrisTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await pix.configureProvider(
                    type: selectedType,
                    baseUrl: urlCtrl.text,
                    apiKey: keyCtrl.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _switchMethodRefresh();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e'), backgroundColor: IrisTheme.danger),
                  );
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Reaplica o estado do trilho PIX após troca de provedor.
  void _switchMethodRefresh() {
    if (_method != ReceiveMethod.pix) return;
    final pix = context.read<PixService>();
    setState(() {
      _pixShowAmountForm = !pix.provider.supportsStaticQr;
    });
    if (pix.provider.supportsStaticQr) {
      pix.ensureStaticDeposit().catchError((e) {
        if (mounted) setState(() => _pixShowAmountForm = true);
        return PixCharge(id: 'erro', amountBrl: 0, qrCopiaECola: '');
      });
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
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _paymentSub?.cancel();
    _lbtcSub?.cancel();
    _paidResetTimer?.cancel();
    _pixBrlCtrl.dispose();
    _pixCpfCtrl.dispose();
    super.dispose();
  }

  String get _formattedTime {
    if (_method != ReceiveMethod.lightning || widget.satsAmount == 0) {
      return '∞ (Sem expiração)';
    }
    final minutes = (_secondsRemaining / 60).floor();
    final seconds = _secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final pix = context.watch<PixService>();
    final showSats = exchangeRate.isSatsDisplay;
    final brlAmount = exchangeRate.satsToBrl(widget.satsAmount);
    final isPix = _method == ReceiveMethod.pix;
    final pixCharge = pix.activeCharge;
    final pixStatic = pix.staticCharge;
    final showPixForm = isPix && _pixShowAmountForm && pixCharge == null && widget.satsAmount == 0;
    final displayPayload = isPix
        ? (showPixForm ? null : (pixCharge ?? pixStatic)?.qrCopiaECola)
        : _invoiceData;
    final pixPaid = isPix &&
        (_pixStaticReceived ||
            (pixCharge != null &&
                (pixCharge.status == PixChargeStatus.paid ||
                    pixCharge.status == PixChargeStatus.settled)));

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
          'Receber',
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
            child: MaxWidthContainer(
            maxWidth: 460,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Seletor do trilho de recebimento — só aparece no QR fixo/aberto.
              // Ao definir um valor específico (PIX ou sats), o trilho fica
              // travado no que foi escolhido antes; sem opções dos outros.
              if (pixCharge == null && widget.satsAmount == 0 && !showPixForm) ...[
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
                      _buildMethodBtn('🇧🇷 PIX', ReceiveMethod.pix),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Chip de contexto do trilho
              if (isPix)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: IrisTheme.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'PIX → DEPIX (Liquid) → sats · ${pix.provider.name}',
                          style: const TextStyle(
                              color: IrisTheme.success, fontSize: 11, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 18, color: IrisTheme.textTertiary),
                      tooltip: 'Provedor PIX/DEPIX',
                      onPressed: _showPixProviderConfig,
                    ),
                  ],
                )
              else if (_method == ReceiveMethod.onchain)
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

              // Painel PIX: campo de valor em Reais (ação secundária)
              if (showPixForm) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: IrisTheme.s1,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: IrisTheme.bdr),
                  ),
                  child: Column(
                    children: [
                      const Text('Valor do depósito',
                          style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'R\$ ${_pixBrlCtrl.text.isEmpty ? '0,00' : _pixBrlCtrl.text}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 40,
                              fontWeight: FontWeight.w600,
                              color: IrisTheme.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '≈ ${CurrencyFormatter.formatBtcOrSats(exchangeRate.brlToSats(double.tryParse(_pixBrlCtrl.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0))}',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12, color: IrisTheme.primary),
                      ),
                      const SizedBox(height: 16),
                      // Mesmo teclado numérico da tela de valor específico.
                      Numpad(
                        onKeyPress: _pixNumKey,
                        onBackspace: _pixNumBack,
                        showDecimal: false,
                      ),
                      if (pix.provider.requiresPayerTaxNumber) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pixCpfCtrl
                            ..text = _pixCpfCtrl.text.isEmpty
                                ? (pix.payerTaxNumber ?? '')
                                : _pixCpfCtrl.text,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'CPF/CNPJ do pagador',
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _pixBusy ? null : _createPixChargeFromInput,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _pixBusy
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Gerar cobrança PIX'),
                  ),
                ),
              ],

              if (displayPayload != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    // QR responsivo: ~60% da largura da tela, com meio-termo no
                    // mobile e limite no desktop. O box acompanha o QR (sem
                    // espaço vazio nas laterais) e nunca ultrapassa o disponível.
                    final screenW = MediaQuery.of(context).size.width;
                    final available = constraints.maxWidth - 32;
                    double qrSize = (screenW * 0.6).clamp(240.0, 380.0).toDouble();
                    if (qrSize > available) qrSize = available;
                    return Container(
                      width: qrSize + 32,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          QrImageView(
                            data: displayPayload,
                            version: QrVersions.auto,
                            size: qrSize,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
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
                              displayPayload,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.4,
                                color: IrisTheme.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              else if (_errorMessage != null && !_isLoading)
                _buildCenteredError(_errorMessage!),

              const SizedBox(height: 24),

              // Valor exibido
              if (isPix && pixCharge != null) ...[
                Text(
                  'R\$ ${CurrencyFormatter.formatBrlCompact(pixCharge.amountBrl)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: IrisTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '≈ ${CurrencyFormatter.formatBtcOrSats(exchangeRate.brlToSats(pixCharge.amountBrl))} no seu saldo',
                  style: const TextStyle(fontSize: 14, color: IrisTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    pix.clearActiveCharge();
                    setState(() => _pixShowAmountForm = false);
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: IrisTheme.bdr)),
                  child: const Text('← Voltar ao QR fixo',
                      style: TextStyle(color: IrisTheme.textSecondary)),
                ),
              ] else if (isPix && !showPixForm) ...[
                // Título/subtítulo "QR PIX FIXO" removidos; o botão de valor
                // específico foi movido para baixo de Copiar/Compartilhar.
              ] else if (showPixForm) ...[
                OutlinedButton(
                  onPressed: () => setState(() => _pixShowAmountForm = false),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: IrisTheme.bdr)),
                  child: const Text('← Voltar ao QR fixo',
                      style: TextStyle(color: IrisTheme.textSecondary)),
                ),
              ] else if (!isPix && _errorMessage != null) ...[
                // Erro já exibido de forma centralizada acima; nada aqui.
              ] else if (!isPix && widget.satsAmount > 0) ...[
                Text(
                  showSats
                      ? CurrencyFormatter.formatBtcOrSats(widget.satsAmount)
                      : 'R\$ ${CurrencyFormatter.formatBrlCompact(brlAmount)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: IrisTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  showSats
                      ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(brlAmount)}'
                      : '≈ ${CurrencyFormatter.formatBtcOrSats(widget.satsAmount)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: IrisTheme.textSecondary,
                  ),
                ),
              ] else if (!isPix) ...[
                // Título/subtítulo "VALOR ABERTO" removidos; o botão de valor
                // específico foi movido para baixo de Copiar/Compartilhar.
              ],

              // Estado: pago / carregando / aguardando
              if (_isPaid || pixPaid)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: IrisTheme.success, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _pixStaticReceived
                              ? 'PIX recebido! +${CurrencyFormatter.formatBtcOrSats(_pixReceivedSats)} no saldo'
                              : pixPaid
                                  ? 'PIX pago! Convertendo para sats...'
                                  : 'Pagamento recebido! ⚡ ${CurrencyFormatter.formatBtcOrSats(_paidAmountSats)}',
                          style: const TextStyle(color: IrisTheme.success, fontSize: 16, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isLoading || _pixBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(color: IrisTheme.primary)),
                )
              else
                const SizedBox(height: 12),

              // Botão de simulação (sandbox: local ou API oficial do provedor)
              if (isPix &&
                  pixCharge != null &&
                  pixCharge.status == PixChargeStatus.pending &&
                  pix.provider.canSimulate) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => pix.simulatePaymentReceived(),
                    style: ElevatedButton.styleFrom(backgroundColor: IrisTheme.success),
                    child: const Text('Simular pagamento do PIX (sandbox)'),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // "Expira em" só para faturas com valor definido e prazo real
              // (fixo/produto usa ∞ e não precisa mostrar).
              if (!_isPaid && !pixPaid && !isPix && widget.satsAmount > 0)
                Text(
                  'Expira em $_formattedTime',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: _secondsRemaining < 60 ? IrisTheme.danger : IrisTheme.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),

              const SizedBox(height: 16),

              if (displayPayload != null)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: displayPayload));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código copiado!')),
                        );
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
                        onPressed: () => Share.share(displayPayload),
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
              // Botão de valor específico ABAIXO de Copiar/Compartilhar.
              if (!isPix && widget.satsAmount == 0 && displayPayload != null && _errorMessage == null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomChargeScreen(isMerchant: widget.isMerchant),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: IrisTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Ou defina um valor específico', style: TextStyle(color: IrisTheme.primary)),
                  ),
                ),
              ],
              if (isPix && !showPixForm && pixCharge == null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _pixShowAmountForm = true),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: IrisTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Ou cobre um valor específico', style: TextStyle(color: IrisTheme.primary)),
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: isOn ? IrisTheme.brandGradient : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isOn ? Colors.white : IrisTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
