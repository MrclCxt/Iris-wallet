import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'services/wallet_service.dart';
import 'services/liquid_wallet_service.dart';
import 'services/swap_service.dart';
import 'services/exchange_rate_service.dart';
import 'screens/splash_screen.dart';
import 'services/chroma_service.dart';
import 'screens/seed_generation_screen.dart';
import 'screens/seed_confirmation_screen.dart';
import 'screens/seed_restore_screen.dart';
import 'screens/pin_screen.dart';
import 'screens/consumer/home_screen.dart';
import 'screens/merchant/home_screen.dart';
import 'screens/merchant/setup_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/consumer/custom_charge_screen.dart';
import 'screens/consumer/node_manager_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletService()),
        ChangeNotifierProvider(create: (_) => LiquidWalletService()),
        ChangeNotifierProvider(create: (_) => ChromaService()),
        ChangeNotifierProxyProvider2<WalletService, LiquidWalletService, SwapService>(
          create: (context) => SwapService(
            walletService: Provider.of<WalletService>(context, listen: false),
            liquidWalletService: Provider.of<LiquidWalletService>(context, listen: false),
          ),
          update: (context, wallet, liquid, previous) => previous ?? SwapService(walletService: wallet, liquidWalletService: liquid),
        ),
        ChangeNotifierProvider(create: (_) => ExchangeRateService()..fetchRate()),
      ],
      child: const IrisApp(),
    ),
  );
}

class IrisApp extends StatelessWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IRIS',
      debugShowCheckedModeBanner: false,
      theme: IrisTheme.darkTheme,
      home: const SplashScreen(),
      routes: {
        '/unlock': (context) => const PinScreen(mode: PinMode.unlock),
        '/seed_gen': (context) => const SeedGenerationScreen(),
        '/seed_confirm': (context) => const SeedConfirmationScreen(),
        '/seed_restore': (context) => const SeedRestoreScreen(),
        '/pin_create': (context) => const PinScreen(mode: PinMode.create),
        '/consumer_home': (context) => const ConsumerHomeScreen(),
        '/merchant_home': (context) => const MerchantHomeScreen(),
        '/merchant_setup': (context) => const MerchantSetupScreen(),
        '/welcome': (context) => const WelcomeScreen(),
        '/custom_charge': (context) => const CustomChargeScreen(),
        '/node_manager': (context) => const NodeManagerScreen(),
      },
    );
  }
}
