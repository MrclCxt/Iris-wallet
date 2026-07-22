import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../widgets/area_switcher_btn.dart';
import '../../widgets/iris_widgets.dart';
import '../../services/chroma_service.dart';
import 'consumer_dashboard.dart';
import 'consumer_pay_screen.dart';
import 'receive_qr_screen.dart';
import 'consumer_config_screen.dart';
import '../../widgets/responsive_layout.dart';

class ConsumerHomeScreen extends StatefulWidget {
  const ConsumerHomeScreen({super.key});

  @override
  State<ConsumerHomeScreen> createState() => _ConsumerHomeScreenState();
}

class _ConsumerHomeScreenState extends State<ConsumerHomeScreen> {
  int _currentIndex = 0;
  bool _isRailExtended = true;

  late final List<Widget> _pagesWithArgs = [
    ConsumerDashboard(onNavigateTab: _onTabTapped),
    const ConsumerPayScreen(),
    const ReceiveQrScreen(satsAmount: 0),
    const ConsumerConfigScreen(),
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
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isRailExtended ? Icons.menu_open : Icons.menu,
                        color: context.watch<ChromaService>().primary,
                      ),
                      onPressed: () => setState(() => _isRailExtended = !_isRailExtended),
                    ),
                    if (_isRailExtended) const IrisAppBarTitle(),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: AreaSwitcherBtn(isCurrentlyConsumer: true, showText: _isRailExtended),
                  ),
                ),
              ),
              selectedIconTheme: const IconThemeData(color: IrisTheme.primary),
              unselectedIconTheme: const IconThemeData(color: IrisTheme.textTertiary),
              destinations: const [
                NavigationRailDestination(
                  icon: Text('🏠', style: TextStyle(fontSize: 20)),
                  label: Text('Início', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                NavigationRailDestination(
                  icon: Text('💸', style: TextStyle(fontSize: 20)),
                  label: Text('Enviar', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                NavigationRailDestination(
                  icon: Text('⬇', style: TextStyle(fontSize: 20)),
                  label: Text('Receber', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                NavigationRailDestination(
                  icon: Text('⚙️', style: TextStyle(fontSize: 20)),
                  label: Text('Config.', style: TextStyle(fontWeight: FontWeight.w600)),
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
        bottomNavigationBar: _IrisBottomNav(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
        ),
      ),
    );
  }
}

class _IrisBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _IrisBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final chroma = context.watch<ChromaService>();
    final hue = chroma.hue;

    final items = [
      ('🏠', 'INÍCIO'),
      ('💸', 'ENVIAR'),
      ('⬇', 'RECEBER'),
      ('⚙️', 'CONFIG'),
    ];

    // Tab accent colors — each 90° apart from the current chroma hue
    final tabColors = List.generate(4, (i) =>
      HSLColor.fromAHSL(1.0, (hue + i * 90) % 360, 0.85, 0.60).toColor(),
    );

    // Animated rainbow that starts at current hue and spans full spectrum
    final rainbowColors = List.generate(9, (i) =>
      HSLColor.fromAHSL(1.0, (hue + i * 45) % 360, 0.88, 0.58).toColor(),
    );

    return Container(
      decoration: const BoxDecoration(
        color: IrisTheme.s1,
        border: Border(top: BorderSide(color: IrisTheme.bdr, width: 1.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated rainbow bar at top — shifts with ChromaService
          AnimatedContainer(
            duration: const Duration(seconds: 3),
            curve: Curves.easeInOut,
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: rainbowColors),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(items.length, (i) {
                  final isSelected = currentIndex == i;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? tabColors[i].withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(items[i].$1, style: TextStyle(fontSize: isSelected ? 20 : 18)),
                          const SizedBox(height: 2),
                          Text(
                            items[i].$2,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isSelected ? tabColors[i] : IrisTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
