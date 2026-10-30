import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/pix_service.dart';
import '../../widgets/max_width_container.dart';
import 'pix_onboarding_screen.dart';

class AtivarPixScreen extends StatefulWidget {
  const AtivarPixScreen({super.key});

  @override
  State<AtivarPixScreen> createState() => _AtivarPixScreenState();
}

class _AtivarPixScreenState extends State<AtivarPixScreen> {
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String _type = 'depixapp';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply(String type) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<PixService>().configureProvider(
            type: type,
            baseUrl: _urlCtrl.text,
            apiKey: _keyCtrl.text,
          );
      if (mounted) {
        _keyCtrl.clear();
        _urlCtrl.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pix = context.watch<PixService>();
    final enabled = pix.isPixEnabled;

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.bg,
        elevation: 0,
        title: const Text('Ativar Pix / Reais',
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
                _statusCard(pix, enabled),
                const SizedBox(height: 24),
                const Text(
                  'O Pix é opcional. Sua carteira já envia e recebe Bitcoin '
                  '(Lightning e on-chain) sem nada disto. Ative os Reais só se '
                  'quiser depositar/sacar via Pix — e, para isso, você precisa '
                  'de uma conta DePix própria.',
                  style: TextStyle(
                      color: IrisTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5),
                ),
                const SizedBox(height: 24),
                if (!enabled) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const PixOnboardingScreen()),
                              ),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Ativar automaticamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: IrisTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoBox(
                    'O jeito recomendado: o app cria sua conta DePix e guarda a '
                    'chave sozinho, ligando os depósitos à sua carteira Liquid. '
                    'Você só conecta seu GitHub/Google uma vez.',
                  ),
                  const SizedBox(height: 24),
                ],
                _sectionTitle('Configuração manual (avançado)'),
                const SizedBox(height: 8),
                _infoBox(
                  'Já tem uma chave de API? Cole abaixo. Crie/gerencie a conta '
                  'em depixapp.com → Dashboard → API Keys. A sk_test_ (sandbox) '
                  'sai na hora; a sk_live_ move Reais de verdade. A chave fica '
                  'só neste aparelho.',
                ),
                const SizedBox(height: 20),
                _sectionTitle('Provedor'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _type,
                  dropdownColor: IrisTheme.s2,
                  style: const TextStyle(
                      color: IrisTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(labelText: 'Provedor'),
                  items: const [
                    DropdownMenuItem(
                        value: 'depixapp',
                        child: Text('DePix App (recomendado)')),
                    DropdownMenuItem(
                        value: 'rest', child: Text('REST genérico')),
                    DropdownMenuItem(
                        value: 'sim', child: Text('Simulado (dev/testnet)')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _type = v ?? 'depixapp'),
                ),
                const SizedBox(height: 12),
                if (_type == 'rest')
                  TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'URL base da API',
                      hintText: 'https://api.provedor.com/v1',
                    ),
                  ),
                if (_type == 'depixapp' || _type == 'rest') ...[
                  if (_type == 'rest') const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: true,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: _type == 'depixapp'
                          ? 'Chave de API (sk_test_... ou sk_live_...)'
                          : 'Chave de API',
                    ),
                  ),
                ],
                if (_type == 'sim')
                  _infoBox(
                    'Modo de desenvolvimento: percorre o fluxo do Pix sem mover '
                    'Reais de verdade. Use só para testar a interface.',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(
                          color: IrisTheme.danger, fontSize: 12)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _apply(_type),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: IrisTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(enabled ? 'Atualizar Pix' : 'Ativar Pix'),
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _apply('off'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: IrisTheme.danger,
                        side: const BorderSide(color: IrisTheme.danger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Desativar Pix'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(PixService pix, bool enabled) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: enabled ? IrisTheme.success : IrisTheme.bdr),
      ),
      child: Row(
        children: [
          Icon(enabled ? Icons.check_circle : Icons.lock_outline,
              color: enabled ? IrisTheme.success : IrisTheme.textTertiary,
              size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(enabled ? 'Pix ativo' : 'Pix desativado',
                    style: TextStyle(
                        color:
                            enabled ? IrisTheme.success : IrisTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Provedor: ${pix.provider.name}'
                      : 'Você opera só em sats/BTC.',
                  style: const TextStyle(
                      color: IrisTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
            color: IrisTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3),
      );

  Widget _infoBox(String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: IrisTheme.s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Text(t,
            style: const TextStyle(
                color: IrisTheme.textTertiary, fontSize: 11, height: 1.5)),
      );
}
