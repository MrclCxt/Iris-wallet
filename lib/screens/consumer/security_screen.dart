import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';
import '../../widgets/max_width_container.dart';
import '../pin_screen.dart';
import 'change_pin_screen.dart';

class SecurityScreen extends StatefulWidget {
  final bool isMerchant;
  const SecurityScreen({super.key, this.isMerchant = false});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late int _freeAttempts;
  late bool _autoWipe;
  late int _wipeThreshold;
  late int _autoLockMinutes;
  late bool _lockOnSuspend;
  bool _loaded = false;

  void _loadFrom(WalletService w) {
    if (_loaded) return;
    _freeAttempts = w.pinFreeAttempts;
    _autoWipe = w.autoWipeEnabled;
    _wipeThreshold = w.autoWipeThreshold;
    _autoLockMinutes = w.autoLockMinutes;
    _lockOnSuspend = w.lockOnSuspend;
    _loaded = true;
  }

  Future<void> _save() async {
    final w = context.read<WalletService>();
    await w.setPinSecurityPolicy(
      freeAttempts: _freeAttempts,
      autoWipeEnabled: _autoWipe,
      autoWipeThreshold: _wipeThreshold,
    );
    await w.setAutoLockPolicy(
      minutes: _autoLockMinutes,
      lockOnSuspend: _lockOnSuspend,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Preferências de segurança salvas.'),
          backgroundColor: IrisTheme.success),
    );
  }

  void _showSeed(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinScreen(
          mode: PinMode.unlock,
          isMerchant: widget.isMerchant,
          onSuccess: () {
            Navigator.pop(context);
            final wallet = context.read<WalletService>();
            final seed = widget.isMerchant
                ? (wallet.merchantSeed ?? 'Semente da loja não encontrada')
                : (wallet.consumerSeed ?? 'Semente não encontrada');
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
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: IrisTheme.bdr)),
        title: Text(
            widget.isMerchant
                ? 'Frase de Recuperação (Loja)'
                : 'Frase de Recuperação',
            style: const TextStyle(color: IrisTheme.danger, fontSize: 16)),
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
            child: const Text('Fechar',
                style: TextStyle(color: IrisTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _handleWipe(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: IrisTheme.bdr)),
        title: Text(
            widget.isMerchant ? 'Apagar Loja Atual?' : 'Apagar Carteira Atual?',
            style: const TextStyle(color: IrisTheme.danger)),
        content: Text(
          widget.isMerchant
              ? 'Isso apagará o perfil e saldo desta loja do dispositivo. Tenha '
                  'certeza que você anotou sua Semente antes de continuar.'
              : 'Isso apagará a carteira atual. Tenha certeza que você anotou '
                  'sua Semente antes de continuar.',
          style: const TextStyle(color: IrisTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: IrisTheme.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: IrisTheme.danger,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              final wallet = context.read<WalletService>();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => PinScreen(
                    mode: PinMode.unlock,
                    isMerchant: widget.isMerchant,
                    onSuccess: () async {
                      if (widget.isMerchant) {
                        await wallet.deleteActiveMerchant();
                        if (!ctx.mounted) return;
                        if (wallet.merchantAccounts.isEmpty) {
                          Navigator.pushNamedAndRemoveUntil(
                              ctx, '/', (route) => false);
                        } else {
                          Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (context) => const PinScreen(
                                  mode: PinMode.unlock, isMerchant: true),
                            ),
                          );
                        }
                      } else {
                        await wallet.deleteActiveConsumer();
                        if (!ctx.mounted) return;
                        if (wallet.consumerAccounts.isEmpty) {
                          Navigator.pushNamedAndRemoveUntil(
                              ctx, '/', (route) => false);
                        } else {
                          Navigator.pushNamedAndRemoveUntil(
                              ctx, '/unlock', (route) => false);
                        }
                      }
                    },
                  ),
                ),
              );
            },
            child: Text(widget.isMerchant ? 'Apagar Loja' : 'Apagar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _loadFrom(context.read<WalletService>());
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.bg,
        elevation: 0,
        title: const Text('Segurança',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
      ),
      body: MaxWidthContainer(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Bloqueio automático'),
                const SizedBox(height: 8),
                _card(
                  icon: Icons.lock_clock_outlined,
                  title: 'Sem botão manual — o app tranca sozinho',
                  body:
                      'Nada de "Bloquear Aplicativo": a carteira volta a pedir '
                      'PIN por conta própria, por inatividade e/ou quando o '
                      'app volta de segundo plano (proxy do dispositivo ter '
                      'sido bloqueado).',
                ),
                const SizedBox(height: 16),
                _sectionTitle('Travar após inatividade'),
                const SizedBox(height: 8),
                _stepper(
                  value: _autoLockMinutes,
                  min: 0,
                  max: 60,
                  step: 1,
                  onChanged: (v) => setState(() => _autoLockMinutes = v),
                  suffix: _autoLockMinutes == 0 ? '(desligado)' : 'min',
                ),
                const SizedBox(height: 6),
                _hint('0 = nunca por inatividade (ainda tranca ao suspender, '
                    'se ligado abaixo).'),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: IrisTheme.primary,
                  title: const Text('Travar ao sair do app / suspender',
                      style: TextStyle(
                          color: IrisTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Ao minimizar, trocar de app ou o dispositivo ser '
                      'suspenso, a próxima vez que abrir pede PIN.',
                      style: TextStyle(
                          color: IrisTheme.textSecondary, fontSize: 12)),
                  value: _lockOnSuspend,
                  onChanged: (v) => setState(() => _lockOnSuspend = v),
                ),
                const SizedBox(height: 28),
                const Divider(color: IrisTheme.bdr),
                const SizedBox(height: 16),
                _sectionHeader('Proteção contra tentativas'),
                const SizedBox(height: 8),
                _card(
                  icon: Icons.shield_outlined,
                  title: 'Bloqueio progressivo por tempo',
                  body:
                      'Após várias tentativas erradas, o app bloqueia o PIN por '
                      'tempo crescente (30s → 1min → 5min → 15min → 1h). O '
                      'contador é persistente: fechar e reabrir o app não '
                      'reseta. A seed fica cifrada; sem o PIN certo, os dados '
                      'não abrem.',
                ),
                const SizedBox(height: 16),
                _sectionTitle('Tentativas antes de começar a bloquear'),
                const SizedBox(height: 8),
                _stepper(
                  value: _freeAttempts,
                  min: 1,
                  max: 10,
                  onChanged: (v) => setState(() => _freeAttempts = v),
                  suffix: 'tentativa(s)',
                ),
                const SizedBox(height: 6),
                _hint('Menos = mais rígido. Mais = tolera erros de digitação.'),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: IrisTheme.primary,
                  title: const Text('Apagar carteira após tentativas demais',
                      style: TextStyle(
                          color: IrisTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Defesa anti-roubo. Ao atingir o limite, TODOS os dados '
                      'locais são apagados — a carteira só volta pela sua seed.',
                      style: TextStyle(
                          color: IrisTheme.textSecondary, fontSize: 12)),
                  value: _autoWipe,
                  onChanged: (v) => setState(() => _autoWipe = v),
                ),
                if (_autoWipe) ...[
                  const SizedBox(height: 12),
                  _sectionTitle('Apagar após'),
                  const SizedBox(height: 8),
                  _stepper(
                    value: _wipeThreshold,
                    min: 5,
                    max: 50,
                    step: 5,
                    onChanged: (v) => setState(() => _wipeThreshold = v),
                    suffix: 'tentativas erradas',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: IrisTheme.danger.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: IrisTheme.danger.withOpacity(0.4)),
                    ),
                    child: const Text(
                      '⚠️ Irreversível. Confirme que anotou sua frase-semente '
                      'antes de ativar — sem ela, o apagamento é permanente.',
                      style: TextStyle(
                          color: IrisTheme.danger, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: IrisTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Salvar'),
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(color: IrisTheme.bdr),
                const SizedBox(height: 16),
                _sectionHeader('PIN'),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.password_outlined,
                  title: 'Alterar PIN',
                  subtitle: 'Troca o PIN sem perder acesso à carteira',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ChangePinScreen(isMerchant: widget.isMerchant)),
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(color: IrisTheme.bdr),
                const SizedBox(height: 16),
                _sectionHeader('Backup e dados'),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.key_outlined,
                  title: widget.isMerchant
                      ? 'Ver Semente da Loja'
                      : 'Ver Frase Semente',
                  subtitle: widget.isMerchant
                      ? 'Faça backup do PDV'
                      : 'Faça backup da sua carteira pessoal',
                  onTap: () => _showSeed(context),
                ),
                const SizedBox(height: 12),
                _actionTile(
                  icon: Icons.delete_forever,
                  title: widget.isMerchant
                      ? 'Apagar Loja Atual'
                      : 'Apagar Carteira Atual',
                  subtitle: widget.isMerchant
                      ? 'Remove a loja selecionada do dispositivo'
                      : 'Remove a carteira selecionada do dispositivo',
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

  Widget _sectionHeader(String t) => Text(t,
      style: const TextStyle(
          color: IrisTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w800));

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          color: IrisTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700));

  Widget _hint(String t) => Text(t,
      style: const TextStyle(color: IrisTheme.textTertiary, fontSize: 11));

  Widget _card(
          {required IconData icon,
          required String title,
          required String body}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: IrisTheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: IrisTheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(body,
                style: const TextStyle(
                    color: IrisTheme.textSecondary, fontSize: 12, height: 1.5)),
          ],
        ),
      );

  Widget _actionTile({
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
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
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

  Widget _stepper({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    int step = 1,
    String suffix = '',
  }) {
    return Row(
      children: [
        _roundBtn(
            Icons.remove, value > min ? () => onChanged(value - step) : null),
        Expanded(
          child: Text('$value $suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: IrisTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
        _roundBtn(
            Icons.add, value < max ? () => onChanged(value + step) : null),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onTap) => Material(
        color: onTap != null ? IrisTheme.s2 : IrisTheme.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: IrisTheme.bdr),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon,
                color: onTap != null
                    ? IrisTheme.textPrimary
                    : IrisTheme.textTertiary,
                size: 20),
          ),
        ),
      );
}
