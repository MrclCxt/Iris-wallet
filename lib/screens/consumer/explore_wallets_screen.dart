import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';

/// Popup de exploração de carteiras: abre ao tocar no saldo total e mostra
/// as duas carteiras que guardam valor (Lightning e on-chain), ambas em sats.
Future<void> showExploreWalletsSheet(BuildContext context,
    {required bool isMerchant}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: IrisTheme.s1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ExploreWalletsSheet(isMerchant: isMerchant),
  );
}

class _ExploreWalletsSheet extends StatelessWidget {
  final bool isMerchant;
  const _ExploreWalletsSheet({required this.isMerchant});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final rate = context.watch<ExchangeRateService>();
    final showSats = rate.isSatsDisplay;
    final hide = wallet.hideBalance;

    final lightningSats = isMerchant
        ? wallet.merchantLightningSats
        : wallet.consumerLightningSats;
    final onchainSats =
        isMerchant ? wallet.merchantOnchainSats : wallet.consumerOnchainSats;
    final totalSats = lightningSats + onchainSats;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: IrisTheme.bdr2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Carteiras',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: IrisTheme.textPrimary)),
                IconButton(
                  onPressed: () => wallet.setHideBalance(!hide),
                  tooltip: hide ? 'Mostrar saldos' : 'Ocultar saldos',
                  icon: Icon(
                    hide
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: IrisTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _walletCard(
              icon: '⚡',
              title: 'Lightning',
              sats: lightningSats,
              showSats: showSats,
              rate: rate,
              hide: hide,
              color: IrisTheme.primary,
            ),
            const SizedBox(height: 12),
            _walletCard(
              icon: '₿',
              title: 'Bitcoin (on-chain)',
              sats: onchainSats,
              showSats: showSats,
              rate: rate,
              hide: hide,
              color: IrisTheme.textPrimary,
              pendingSats: wallet.pendingOnchainSats(isMerchant: isMerchant),
            ),
            const SizedBox(height: 16),
            const Divider(color: IrisTheme.bdr),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text(
                  _fmt(totalSats, showSats, rate, hide),
                  style: const TextStyle(
                      color: IrisTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(
      int sats, bool showSats, ExchangeRateService rate, bool hide) {
    if (hide) return '••••••';
    return showSats
        ? CurrencyFormatter.formatBtcOrSats(sats)
        : 'R\$ ${CurrencyFormatter.formatBrlCompact(rate.satsToBrl(sats))}';
  }

  Widget _walletCard({
    required String icon,
    required String title,
    required int sats,
    required bool showSats,
    required ExchangeRateService rate,
    required bool hide,
    required Color color,
    int pendingSats = 0,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IrisTheme.s2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                if (pendingSats > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 11, color: IrisTheme.warning),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          hide
                              ? '•••• aguardando confirmação'
                              : '${_fmt(pendingSats, showSats, rate, false)} aguardando confirmação',
                          style: const TextStyle(
                              color: IrisTheme.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Text(_fmt(sats, showSats, rate, hide),
              style: const TextStyle(
                  color: IrisTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
