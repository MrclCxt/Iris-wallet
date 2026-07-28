import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../services/wallet_service.dart';
import '../screens/pin_screen.dart';
import 'account_avatar.dart';

class AreaSwitcherBtn extends StatelessWidget {
  final bool isCurrentlyConsumer;
  final bool showText;

  const AreaSwitcherBtn({
    super.key,
    required this.isCurrentlyConsumer,
    this.showText = true,
  });

  /// Troca entre a área pessoal e a da loja.
  ///
  /// Vive aqui como método estático porque o botão saiu das telas iniciais e a
  /// ação passou a ser acionada pelas Configurações — mas o comportamento
  /// (escolher entre várias contas, pedir PIN, ou mandar para o cadastro
  /// quando ainda não existe loja) precisa ser exatamente o mesmo nos dois
  /// caminhos.
  static void trocarArea(BuildContext context,
      {required bool isCurrentlyConsumer}) {
    final wallet = context.read<WalletService>();
    if (isCurrentlyConsumer) {
      if (wallet.merchantAccounts.length > 1) {
        _showMerchantAccountSwitcher(context, wallet);
      } else if (wallet.merchantAccounts.length == 1) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const PinScreen(mode: PinMode.unlock, isMerchant: true),
          ),
        );
      } else {
        Navigator.pushNamed(context, '/merchant_setup');
      }
    } else {
      if (wallet.consumerAccounts.length > 1) {
        _showConsumerAccountSwitcher(context, wallet);
      } else if (wallet.consumerAccounts.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const PinScreen(mode: PinMode.unlock, isMerchant: false),
          ),
        );
      } else {
        Navigator.pushNamed(context, '/welcome');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          trocarArea(context, isCurrentlyConsumer: isCurrentlyConsumer),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: IrisTheme.s2,
          border: Border.all(color: IrisTheme.bdr2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isCurrentlyConsumer ? '🏪' : '⚡',
                style: TextStyle(fontSize: showText ? 14 : 11)),
            if (showText) ...[
              const SizedBox(width: 4),
              Text(
                isCurrentlyConsumer ? 'Lojista' : 'Eu',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: IrisTheme.textPrimary),
              ),
            ]
          ],
        ),
      ),
    );
  }

  static void _showMerchantAccountSwitcher(
      BuildContext context, WalletService wallet) {
    final accounts = wallet.merchantAccounts;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: IrisTheme.bg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Selecione a Loja',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: IrisTheme.textPrimary)),
                  const SizedBox(height: 16),
                  ...accounts.map((acc) {
                    final isActive = acc.id == wallet.activeMerchant?.id;
                    return ListTile(
                      leading: AvatarCircle(
                          accountId: acc.id,
                          colorHex: acc.avatarColor,
                          size: 32),
                      title: Text(acc.name,
                          style: TextStyle(
                              color: isActive
                                  ? IrisTheme.primary
                                  : IrisTheme.textPrimary,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      trailing: isActive
                          ? const Icon(Icons.check, color: IrisTheme.primary)
                          : null,
                      onTap: () async {
                        Navigator.pop(context);
                        if (!isActive) {
                          await wallet.switchMerchantAccount(acc.id);
                        }
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PinScreen(
                                  mode: PinMode.unlock, isMerchant: true),
                            ),
                          );
                        }
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showConsumerAccountSwitcher(
      BuildContext context, WalletService wallet) {
    final accounts = wallet.consumerAccounts;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: IrisTheme.bg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Minhas Carteiras Pessoais',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: IrisTheme.textPrimary)),
                  const SizedBox(height: 16),
                  ...accounts.map((acc) {
                    final isActive = acc.id == wallet.activeConsumer?.id;
                    return ListTile(
                      leading: AvatarCircle(
                          accountId: acc.id,
                          colorHex: acc.avatarColor,
                          size: 32),
                      title: Text(acc.name,
                          style: TextStyle(
                              color: isActive
                                  ? IrisTheme.primary
                                  : IrisTheme.textPrimary,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      trailing: isActive
                          ? const Icon(Icons.check, color: IrisTheme.primary)
                          : null,
                      onTap: () async {
                        Navigator.pop(context);
                        if (!isActive) {
                          await wallet.switchConsumerAccount(acc.id);
                        }
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PinScreen(
                                  mode: PinMode.unlock, isMerchant: false),
                            ),
                          );
                        }
                      },
                    );
                  }),
                  const Divider(color: IrisTheme.bdr),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline,
                        color: IrisTheme.textPrimary),
                    title: const Text('Adicionar nova carteira',
                        style: TextStyle(
                            color: IrisTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(context);
                      // A semente é gerada na tela seguinte, depois da escolha do tamanho.
                      Navigator.pushNamed(context, '/seed_gen');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
