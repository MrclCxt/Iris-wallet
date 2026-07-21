import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';
import '../../widgets/max_width_container.dart';
import '../pin_screen.dart';

class ConsumerConfigScreen extends StatelessWidget {
  const ConsumerConfigScreen({super.key});

  void _showSeed(BuildContext context, {bool isMerchant = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinScreen(
          mode: PinMode.unlock,
          onSuccess: () {
            Navigator.pop(context); // pop PIN
            final wallet = context.read<WalletService>();
            final seed = isMerchant 
                ? (wallet.merchantSeed ?? 'Semente da loja não encontrada')
                : (wallet.consumerSeed ?? 'Semente não encontrada');
            _showSeedDialog(context, seed, isMerchant: isMerchant);
          },
        ),
      ),
    );
  }

  void _showSeedDialog(BuildContext context, String seed, {bool isMerchant = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: IrisTheme.bdr)),
        title: Text(isMerchant ? 'Frase de Recuperação (Loja)' : 'Frase de Recuperação', style: const TextStyle(color: IrisTheme.danger, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Anotou no papel? Nunca compartilhe isso com ninguém.',
              style: TextStyle(color: IrisTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: IrisTheme.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: IrisTheme.bdr),
              ),
              child: Text(
                seed,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.5,
                  color: IrisTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: IrisTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    final wallet = context.read<WalletService>();
    wallet.lock();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const PinScreen(mode: PinMode.unlock, isMerchant: false),
      ),
      (route) => false,
    );
  }

  void _handleWipe(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: IrisTheme.bdr)),
        title: const Text('Apagar Carteira Atual?', style: TextStyle(color: IrisTheme.danger)),
        content: const Text(
          'Isso apagará a carteira atual. Tenha certeza que você anotou sua Semente antes de continuar.',
          style: TextStyle(color: IrisTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: IrisTheme.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: IrisTheme.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              final wallet = context.read<WalletService>();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => PinScreen(
                    mode: PinMode.unlock,
                    isMerchant: false,
                    onSuccess: () async {
                      await wallet.deleteActiveConsumer();
                      if (ctx.mounted) {
                        if (wallet.consumerAccounts.isEmpty) {
                          Navigator.pushNamedAndRemoveUntil(ctx, '/', (route) => false);
                        } else {
                          Navigator.pushNamedAndRemoveUntil(ctx, '/unlock', (route) => false);
                        }
                      }
                    },
                  ),
                ),
              );
            },
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
  }

  void _handleCreateNew(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: IrisTheme.bdr)),
        title: const Text('Criar Nova Conta?', style: TextStyle(color: IrisTheme.primary)),
        content: const Text(
          'Isso criará um novo perfil independente. Você poderá alternar entre suas contas pelo menu de Trocar de Conta.',
          style: TextStyle(color: IrisTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: IrisTheme.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: IrisTheme.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushNamed(context, '/welcome');
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showAccountSwitcher(BuildContext context) {
    final wallet = context.read<WalletService>();
    final accounts = wallet.consumerAccounts;
    
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: IrisTheme.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Minhas Carteiras Pessoais', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: IrisTheme.textPrimary)),
                  const SizedBox(height: 16),
                  ...accounts.map((acc) {
                    final isActive = acc.id == wallet.activeConsumer?.id;
                    return ListTile(
                      leading: const Icon(Icons.account_balance_wallet, color: IrisTheme.primary),
                      title: Text(acc.name, style: TextStyle(color: isActive ? IrisTheme.primary : IrisTheme.textPrimary, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500)),
                      trailing: isActive ? const Icon(Icons.check, color: IrisTheme.primary) : null,
                      onTap: () async {
                        if (!isActive) {
                          Navigator.pop(context); // fechar dialog
                          await wallet.switchConsumerAccount(acc.id);
                          if (context.mounted) {
                            Navigator.pushNamedAndRemoveUntil(context, '/unlock', (route) => false);
                          }
                        }
                      },
                    );
                  }),
                  const Divider(color: IrisTheme.bdr),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline, color: IrisTheme.textPrimary),
                    title: const Text('Adicionar nova carteira', style: TextStyle(color: IrisTheme.textPrimary, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(context);
                      wallet.resetAndGenerateSeed();
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

  @override
  Widget build(BuildContext context) {
    return MaxWidthContainer(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
          children: [
            const Text(
              'Configurações',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),
            
            _buildActionItem(
              icon: Icons.storefront,
              title: 'Modo Lojista / PDV',
              subtitle: 'Receba pagamentos no seu comércio',
              onTap: () {
                final wallet = context.read<WalletService>();
                if (wallet.hasMerchant) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PinScreen(mode: PinMode.unlock, isMerchant: true),
                    ),
                  );
                } else {
                  Navigator.pushNamed(context, '/merchant_setup');
                }
              },
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.security,
              title: 'Ver Frase Semente',
              subtitle: 'Faça backup da sua carteira pessoal',
              onTap: () => _showSeed(context, isMerchant: false),
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.hub,
              title: 'Gestão do Nó Nativo ⚡',
              subtitle: 'Cofre On-chain e Canais Lightning',
              onTap: () => Navigator.pushNamed(context, '/node_manager'),
            ),
            const SizedBox(height: 16),

            _buildActionItem(
              icon: Icons.lock_outline,
              title: 'Bloquear Aplicativo',
              subtitle: 'Sair e exigir PIN novamente',
              onTap: () => _handleLogout(context),
            ),
            const SizedBox(height: 32),
            
            const Divider(color: IrisTheme.bdr),
            
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.switch_account,
              title: 'Trocar de Conta Pessoal',
              subtitle: 'Alternar entre carteiras',
              onTap: () => _showAccountSwitcher(context),
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.person_add,
              title: 'Criar Nova Conta Pessoal',
              subtitle: 'Cria uma nova carteira independente',
              onTap: () => _handleCreateNew(context),
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.delete_forever,
              title: 'Apagar Carteira Atual',
              subtitle: 'Remove a carteira selecionada do dispositivo',
              color: IrisTheme.danger,
              onTap: () => _handleWipe(context),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = IrisTheme.primary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: IrisTheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color == IrisTheme.danger ? color : IrisTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: IrisTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}
