import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../widgets/numpad.dart';
import '../consumer/receive_qr_screen.dart';
import '../../services/exchange_rate_service.dart';
import 'package:provider/provider.dart';
import '../../widgets/currency_toggle_btn.dart';

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
      convertedDisplay = '≈ ${CurrencyFormatter.formatSats(exchangeRate.brlToSats(_inputValue / 100.0))} sats';
    }

    return Scaffold(
      backgroundColor: BitpayTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: BitpayTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Cobrar Valor Específico', style: TextStyle(color: BitpayTheme.textPrimary, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40), 
                  const CurrencyToggleBtn(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mainDisplay,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 48,
                      fontWeight: FontWeight.w600,
                      color: BitpayTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    convertedDisplay,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 16,
                      color: BitpayTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Numpad(
                    onKeyPress: _handleKeyPress,
                    onBackspace: _handleBackspace,
                    showDecimal: !isSatsMode,
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _inputValue > 0 ? _generateQR : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Gerar QR Code'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: isSelected ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? BitpayTheme.s3 : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? BitpayTheme.textPrimary : BitpayTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}
