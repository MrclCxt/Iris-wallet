import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/max_width_container.dart';
import '../consumer/security_screen.dart';
import '../consumer/profile_screen.dart';
import '../../widgets/area_switcher_btn.dart';

class MerchantConfigScreen extends StatelessWidget {
  const MerchantConfigScreen({super.key});

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
                  onTap: () => AreaSwitcherBtn.trocarArea(context,
                      isCurrentlyConsumer: false),
                ),
                const SizedBox(height: 16),
                _buildActionItem(
                  icon: Icons.person_outline,
                  title: 'Perfil da loja',
                  subtitle: 'Nome, avatar, moeda, lojas',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProfileScreen(isMerchant: true)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionItem(
                  icon: Icons.shield_outlined,
                  title: 'Segurança',
                  subtitle: 'Bloqueio automático, semente, apagar loja',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SecurityScreen(isMerchant: true)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionItem(
                  icon: Icons.hub,
                  title: 'Carteira Bitcoin e Canais ⚡',
                  subtitle: 'Saldo on-chain, endereço e canais',
                  onTap: () => Navigator.pushNamed(context, '/node_manager'),
                ),
                const SizedBox(height: 16),
                _buildActionItem(
                  icon: Icons.pix,
                  title: 'Pix / Reais · em breve',
                  subtitle: 'Em desenvolvimento e testes de integração',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Pix/Reais chega em breve. Por enquanto, a loja recebe '
                          'em Bitcoin — Lightning e on-chain.'),
                    ),
                  ),
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
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color == IrisTheme.danger
                              ? color
                              : IrisTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: IrisTheme.textSecondary)),
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
