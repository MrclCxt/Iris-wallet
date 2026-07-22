import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../widgets/numpad.dart';
import '../consumer/receive_qr_screen.dart';
import '../../services/exchange_rate_service.dart';
import 'package:provider/provider.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/max_width_container.dart';

class CustomChargeScreen extends StatefulWidget {
  final bool isMerchant;
  const CustomChargeScreen({super.key, this.isMerchant = false});
  @override
  State<CustomChargeScreen> createState() => _CustomChargeScreenState();
}

class _CustomChargeScreenState extends State<CustomChargeScreen> {
  int _inputValue = 0; // Represents cents (BRL) or sats (SATS)
  bool? _lastSatsMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final exchangeRate = context.watch<ExchangeRateService>();
    final isSatsMode = exchangeRate.isSatsDisplay;
    
    if (_lastSatsMode != null && _lastSatsMode != isSatsMode) {
      if (isSatsMode) {
        // Convert BRL cents to SATS
        double brl = _inputValue / 100.0;
        _inputValue = exchangeRate.brlToSats(brl);
      } else {
        // Convert SATS to BRL cents
        double brl = exchangeRate.satsToBrl(_inputValue);
        _inputValue = (brl * 100).round();
      }
    }
    _lastSatsMode = isSatsMode;
  }

  void _handleKeyPress(String key) {
    if (key == ',') return; // ignore comma in currency mode
    setState(() {
      final isSatsMode = context.read<ExchangeRateService>().isSatsDisplay;
      if (_inputValue.toString().length < (isSatsMode ? 12 : 10)) {
        _inputValue = _inputValue * 10 + int.parse(key);
      }
    });
  }

  void _handleBackspace() {
    setState(() {
      _inputValue = _inputValue ~/ 10;
    });
  }

  void _generateQR() {
    if (_inputValue <= 0) return;

    final exchangeRate = context.read<ExchangeRateService>();
    final isSatsMode = exchangeRate.isSatsDisplay;
    int satsAmount = isSatsMode ? _inputValue : exchangeRate.brlToSats(_inputValue / 100.0);

    // Sem cotação não há como converter BRL -> sats: evita cobrança zerada
    if (satsAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cotação BTC/BRL indisponível no momento. Tente novamente em instantes.'),
          backgroundColor: IrisTheme.danger,
        ),
      );
      exchangeRate.fetchRate();
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ReceiveQrScreen(satsAmount: satsAmount, isStandalone: true, isMerchant: widget.isMerchant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final isSatsMode = exchangeRate.isSatsDisplay;
    
    String mainDisplay = '';
    String convertedDisplay = '';
    
    if (isSatsMode) {
      mainDisplay = '${CurrencyFormatter.formatSats(_inputValue)} SATS';
      convertedDisplay = '≈ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(_inputValue))}';
    } else {
      mainDisplay = 'R\$ ${CurrencyFormatter.formatBrl(_inputValue / 100.0)}';
      convertedDisplay = '≈ ${CurrencyFormatter.formatBtcOrSats(exchangeRate.brlToSats(_inputValue / 100.0))}';
    }

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Cobrar Valor Específico', style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
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
                  const Center(child: CurrencyToggleBtn()),
                  const SizedBox(height: 20),
                  // Mesmo card do valor específico do PIX: rótulo + valor + numpad.
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: IrisTheme.s1,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: IrisTheme.bdr),
                    ),
                    child: Column(
                      children: [
                        const Text('Valor da cobrança',
                            style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            mainDisplay,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 40,
                              fontWeight: FontWeight.w600,
                              color: IrisTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          convertedDisplay,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: IrisTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Numpad(
                          onKeyPress: _handleKeyPress,
                          onBackspace: _handleBackspace,
                          showDecimal: !isSatsMode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _inputValue > 0 ? _generateQR : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Gerar QR Code'),
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

}
