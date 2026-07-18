import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'merchant_dashboard.dart';
import 'merchant_products_screen.dart';
import '../../widgets/responsive_layout.dart';
import 'merchant_history_screen.dart';
import 'merchant_config_screen.dart';
import '../consumer/receive_qr_screen.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/area_switcher_btn.dart';
import 'package:provider/provider.dart';

class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  int _currentIndex = 0;
  bool _isRailExtended = true;

  late final List<Widget> _pagesWithArgs = [
    MerchantDashboard(onNavigateTab: _onTabTapped),
    const MerchantProductsScreen(),
    const _MerchantReceiveWrapper(),
    const MerchantHistoryScreen(),
    const MerchantConfigScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      desktop: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: _isRailExtended,
              minExtendedWidth: 160,
              backgroundColor: IrisTheme.s1,
              selectedIndex: _currentIndex,
              onDestinationSelected: _onTabTapped,
              leading: IconButton(
                icon: Icon(_isRailExtended ? Icons.menu_open : Icons.menu, color: IrisTheme.primary),
                onPressed: () {
                  setState(() {
                    _isRailExtended = !_isRailExtended;
                  });
                },
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: AreaSwitcherBtn(isCurrentlyConsumer: false, showText: _isRailExtended),
                  ),
                ),
              ),
              selectedIconTheme: const IconThemeData(color: IrisTheme.primary),
              unselectedIconTheme: const IconThemeData(color: IrisTheme.textTertiary),
              destinations: [
                NavigationRailDestination(
                  icon: const Text('📈', style: TextStyle(fontSize: 20)), 
                  label: const Text('Início', style: TextStyle(fontWeight: FontWeight.w600))
                ),
                NavigationRailDestination(
                  icon: const Text('📦', style: TextStyle(fontSize: 20)), 
                  label: const Text('Produtos', style: TextStyle(fontWeight: FontWeight.w600))
                ),
                NavigationRailDestination(
                  icon: const Text('⚡', style: TextStyle(fontSize: 20)), 
                  label: const Text('Cobrar', style: TextStyle(fontWeight: FontWeight.w600))
                ),
                NavigationRailDestination(
                  icon: const Text('🧾', style: TextStyle(fontSize: 20)), 
                  label: const Text('Histórico', style: TextStyle(fontWeight: FontWeight.w600))
                ),
                NavigationRailDestination(
                  icon: const Text('⚙️', style: TextStyle(fontSize: 20)), 
                  label: const Text('Config.', style: TextStyle(fontWeight: FontWeight.w600))
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1, color: IrisTheme.bdr),
            Expanded(child: _pagesWithArgs[_currentIndex]),
          ],
        ),
      ),
      mobile: Scaffold(
        body: _pagesWithArgs[_currentIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: IrisTheme.bg,
            border: const Border(
              top: BorderSide(color: IrisTheme.bdr, width: 1.0),
            ),
          ),
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabItem(0, '📊', 'Início'),
                _buildTabItem(1, '📦', 'Produtos'),
                _buildTabItem(2, '⚡', 'Cobrar'),
                _buildTabItem(3, '📜', 'Histórico'),
                _buildTabItem(4, '⚙️', 'Config'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String emoji, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTabTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 18, height: 1),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: isSelected ? IrisTheme.primary : IrisTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantReceiveWrapper extends StatelessWidget {
  const _MerchantReceiveWrapper();

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final pending = wallet.pendingChargeAmount;
    
    // Convert BRL to sats if there's a pending charge
    // But ReceiveQrScreen expects sats. Let's let it handle 0 (fixed QR) or specific sats.
    int sats = 0;
    if (pending > 0) {
       final exchangeRate = context.read<ExchangeRateService>();
       sats = exchangeRate.brlToSats(pending);
       // We should clear it so it doesn't persist forever if they leave the tab? 
       // For now it's fine, let's keep it simple.
    }
    
    return ReceiveQrScreen(satsAmount: sats, isMerchant: true);
  }
}
