import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../services/exchange_rate_service.dart';

class CurrencyToggleBtn extends StatelessWidget {
  const CurrencyToggleBtn({super.key});

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    final isSats = exchangeRate.isSatsDisplay;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BitpayTheme.s2,
        border: Border.all(color: BitpayTheme.bdr2),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleBtn(context, '⚡ SATS', isSats, () {
            if (!isSats) context.read<ExchangeRateService>().toggleCurrencyDisplay();
          }, BitpayTheme.brandGradient),
          _buildToggleBtn(context, '🌈 R\$', !isSats, () {
            if (isSats) context.read<ExchangeRateService>().toggleCurrencyDisplay();
          }, const LinearGradient(colors: [BitpayTheme.green, BitpayTheme.cyan])),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(
    BuildContext context,
    String label,
    bool isOn,
    VoidCallback onTap,
    LinearGradient gradient,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: isOn ? gradient : null,
          color: isOn ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isOn
              ? [BoxShadow(color: BitpayTheme.primary.withOpacity(0.3), blurRadius: 8)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isOn ? Colors.white : BitpayTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
