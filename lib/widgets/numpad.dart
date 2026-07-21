import 'package:flutter/material.dart';
import '../core/theme.dart';

class Numpad extends StatelessWidget {
  final Function(String) onKeyPress;
  final VoidCallback onBackspace;
  final bool showDecimal;

  const Numpad({
    super.key,
    required this.onKeyPress,
    required this.onBackspace,
    this.showDecimal = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildRow(['1', '2', '3']),
        const SizedBox(height: 12),
        _buildRow(['4', '5', '6']),
        const SizedBox(height: 12),
        _buildRow(['7', '8', '9']),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                // Vírgula sempre visível, abaixo do 7. Fica inativa (cinza)
                // quando a tela não aceita decimais (ex.: valores em sats).
                child: _buildKey(
                  ',',
                  showDecimal ? () => onKeyPress(',') : null,
                  enabled: showDecimal,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildKey('0', () => onKeyPress('0')),
              ),
            ),
            Expanded(
              child: _buildKey('⌫', onBackspace),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      children: keys.map((k) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: k == keys.last ? 0 : 12),
            child: _buildKey(k, () => onKeyPress(k)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String label, VoidCallback? onTap, {bool enabled = true}) {
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: IrisTheme.s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: IrisTheme.bdr),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            fontFamily: 'Outfit',
            color: enabled ? IrisTheme.textPrimary : IrisTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}
