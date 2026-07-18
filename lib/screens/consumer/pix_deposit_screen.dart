import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/swap_service.dart';
import '../../services/exchange_rate_service.dart';

/// Depósito em Reais via PIX com conversão automática:
/// BRL -> DEPIX (Liquid) -> L-BTC -> saldo unificado em sats.
/// O usuário só vê Reais entrando e sats no saldo — a conversão
/// entre ativos acontece nos bastidores (testnet).
class PixDepositScreen extends StatefulWidget {
  const PixDepositScreen({super.key});

  @override
  State<PixDepositScreen> createState() => _PixDepositScreenState();
}

class _PixDepositScreenState extends State<PixDepositScreen> {
  final TextEditingController _brlCtrl = TextEditingController();
  bool _isRouting = false;

  @override
  void dispose() {
    _brlCtrl.dispose();
    super.dispose();
  }

  double get _brlValue {
    final raw = _brlCtrl.text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  Future<void> _startDeposit() async {
    final brl = _brlValue;
    if (brl <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o valor em Reais.'), backgroundColor: IrisTheme.danger),
      );
      return;
    }
    final rate = context.read<ExchangeRateService>();
    if (!rate.hasRate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cotação BTC/BRL indisponível. Tente novamente em instantes.'),
          backgroundColor: IrisTheme.danger,
        ),
      );
      rate.fetchRate();
      return;
    }

    setState(() => _isRouting = true);
    try {
      await context.read<SwapService>().executeFullRouting(brl);
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final swap = context.watch<SwapService>();
    final rate = context.watch<ExchangeRateService>();
    final satsPreview = rate.brlToSats(_brlValue);

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Depositar via PIX',
          style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Valor em BRL
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: IrisTheme.s1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: IrisTheme.bdr),
                ),
                child: Column(
                  children: [
                    const Text('Valor do depósito', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _brlCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: IrisTheme.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        prefixText: 'R\$ ',
                        prefixStyle: TextStyle(fontSize: 24, color: IrisTheme.textSecondary),
                        hintText: '0,00',
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Text(
                      '≈ ${CurrencyFormatter.formatSats(satsPreview)} sats',
                      style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13, color: IrisTheme.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Explicação do roteamento (abstraída para o usuário final)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: IrisTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'COMO FUNCIONA',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: IrisTheme.primary),
                    ),
                    const SizedBox(height: 8),
                    _buildStep('1', 'Você paga o PIX em Reais'),
                    _buildStep('2', 'Os Reais viram DEPIX na rede Liquid'),
                    _buildStep('3', 'O DEPIX é trocado por L-BTC (swap atômico)'),
                    _buildStep('4', 'O L-BTC entra como sats no seu saldo total'),
                    const SizedBox(height: 8),
                    const Text(
                      'Tudo automático: você só vê Reais entrando e satoshis no saldo.',
                      style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isRouting ? null : _startDeposit,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isRouting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Iniciar depósito PIX', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Testnet: o pagamento PIX é simulado; os swaps Liquid/Lightning são reais.',
                  style: TextStyle(fontSize: 10, color: IrisTheme.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              // Logs do roteamento em tempo real
              if (swap.swapLogs.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: IrisTheme.s1,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: IrisTheme.bdr),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ROTEAMENTO',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: IrisTheme.textTertiary),
                      ),
                      const SizedBox(height: 8),
                      for (final log in swap.swapLogs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            log,
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 11,
                              color: IrisTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: IrisTheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: IrisTheme.primary)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: IrisTheme.textPrimary))),
        ],
      ),
    );
  }
}
