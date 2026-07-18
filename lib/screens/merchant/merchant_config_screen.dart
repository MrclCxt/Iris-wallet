import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';
import '../../widgets/max_width_container.dart';
import '../pin_screen.dart';

class MerchantConfigScreen extends StatelessWidget {
  const MerchantConfigScreen({super.key});

  void _showSeed(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinScreen(
          mode: PinMode.unlock,
          isMerchant: true,
          onSuccess: () {
            Navigator.pop(context); // pop PIN
            final seed = context.read<WalletService>().merchantSeed ?? 'Semente da loja não encontrada';
            _showSeedDialog(context, seed);
          },
        ),
      ),
    );
  }

  void _showSeedDialog(BuildContext context, String seed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BitpayTheme.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: BitpayTheme.bdr)),
        title: const Text('Frase da Loja', style: TextStyle(color: BitpayTheme.danger, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Anotou no papel? Nunca compartilhe isso com ninguém.',
              style: TextStyle(color: BitpayTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BitpayTheme.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BitpayTheme.bdr),
              ),
              child: Text(
                seed,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 14,
                  height: 1.5,
                  color: BitpayTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: BitpayTheme.textPrimary)),
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
        builder: (context) => const PinScreen(mode: PinMode.unlock, isMerchant: true),
      ),
      (route) => false,
    );
  }

  void _handleWipe(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BitpayTheme.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: BitpayTheme.bdr)),
        title: const Text('Apagar Loja Atual?', style: TextStyle(color: BitpayTheme.danger)),
        content: const Text(
          'Isso apagará o perfil e saldo desta loja do dispositivo. Tenha certeza que você anotou sua Semente antes de continuar.',
          style: TextStyle(color: BitpayTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: BitpayTheme.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BitpayTheme.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              final wallet = context.read<WalletService>();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => PinScreen(
                    mode: PinMode.unlock,
                    isMerchant: true,
                    onSuccess: () async {
                      await wallet.deleteActiveMerchant();
                      if (ctx.mounted) {
                        if (wallet.merchantAccounts.isEmpty) {
                          Navigator.pushNamedAndRemoveUntil(ctx, '/', (route) => false);
                        } else {
                          Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (context) => const PinScreen(mode: PinMode.unlock, isMerchant: true),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              );
            },
            child: const Text('Apagar Loja'),
          ),
        ],
      ),
    );
  }

  void _handleCreateNew(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BitpayTheme.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: BitpayTheme.bdr)),
        title: const Text('Criar Nova Loja?', style: TextStyle(color: BitpayTheme.primary)),
        content: const Text(
          'Isso criará uma nova loja independente. Você poderá alternar entre suas lojas pelo menu Trocar de Loja.',
          style: TextStyle(color: BitpayTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: BitpayTheme.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BitpayTheme.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(context, '/merchant_setup', (route) => false);
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showAccountSwitcher(BuildContext context) {
    final wallet = context.read<WalletService>();
    final accounts = wallet.merchantAccounts;
    
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: BitpayTheme.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Minhas Lojas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: BitpayTheme.textPrimary)),
                  const SizedBox(height: 16),
                  ...accounts.map((acc) {
                    final isActive = acc.id == wallet.activeMerchant?.id;
                    return ListTile(
                      leading: const Icon(Icons.store_mall_directory, color: BitpayTheme.primary),
                      title: Text(acc.name, style: TextStyle(color: isActive ? BitpayTheme.primary : BitpayTheme.textPrimary, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500)),
                      trailing: isActive ? const Icon(Icons.check, color: BitpayTheme.primary) : null,
                      onTap: () async {
                        if (!isActive) {
                          Navigator.pop(context); // fechar modal
                          await wallet.switchMerchantAccount(acc.id);
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PinScreen(mode: PinMode.unlock, isMerchant: true),
                              ),
                            );
                          }
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
              'Configurações PDV',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),
            
            _buildActionItem(
              icon: Icons.person,
              title: 'Voltar para Consumidor',
              subtitle: 'Acesse sua conta pessoal',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PinScreen(mode: PinMode.unlock, isMerchant: false),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.store_mall_directory,
              title: 'Ver Semente da Loja',
              subtitle: 'Faça backup do PDV',
              onTap: () => _showSeed(context),
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
            
            const Divider(color: BitpayTheme.bdr),
            
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.switch_account,
              title: 'Trocar de Loja',
              subtitle: 'Alternar entre perfis de lojas',
              onTap: () => _showAccountSwitcher(context),
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.add_business,
              title: 'Criar Nova Loja',
              subtitle: 'Cria uma nova loja independente',
              onTap: () => _handleCreateNew(context),
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              icon: Icons.delete_forever,
              title: 'Apagar Loja Atual',
              subtitle: 'Remove a loja selecionada do dispositivo',
              color: BitpayTheme.danger,
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
    Color color = BitpayTheme.primary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BitpayTheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BitpayTheme.bdr),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color == BitpayTheme.danger ? color : BitpayTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: BitpayTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: BitpayTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

