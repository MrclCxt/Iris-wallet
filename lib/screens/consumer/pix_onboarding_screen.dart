import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/depix_agent_service.dart';
import '../../services/liquid_wallet_service.dart';
import '../../services/pix_service.dart';
import '../../widgets/max_width_container.dart';

/// Onboarding automático de Pix para o usuário.
///
/// Fluxo: o usuário conecta GitHub/Google no painel da DePix e gera o
/// operator token (`op_`); o app registra a conta de agent assinando com uma
/// identidade Ed25519 local, usando o endereço Liquid não-custodial do próprio
/// usuário para receber os depósitos; a chave resultante é guardada só neste
/// dispositivo e ativa o Pix. O Iris nunca detém a conta nem o dinheiro.
class PixOnboardingScreen extends StatefulWidget {
  const PixOnboardingScreen({super.key});

  @override
  State<PixOnboardingScreen> createState() => _PixOnboardingScreenState();
}

class _PixOnboardingScreenState extends State<PixOnboardingScreen> {
  static const String _dashboardUrl = 'https://depixapp.com/#merchant';

  final _agent = DepixAgentService();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _opTokenCtrl = TextEditingController();

  String? _liquidAddress;
  bool _busy = false;
  String? _error;
  AgentRegistration? _result;

  @override
  void initState() {
    super.initState();
    _loadLiquidAddress();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _opTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLiquidAddress() async {
    try {
      final addr = await context.read<LiquidWalletService>().getReceiveAddress();
      if (mounted) setState(() => _liquidAddress = addr);
    } catch (_) {
      // Deixado nulo: o passo de registro avisa que o endereço é obrigatório.
    }
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final opToken = _opTokenCtrl.text.trim();
    final addr = _liquidAddress;

    if (name.length < 2) {
      setState(() => _error = 'Informe um nome de exibição (mínimo 2 letras).');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Informe um e-mail válido para notificações.');
      return;
    }
    if (!opToken.startsWith('op_')) {
      setState(() => _error = 'Cole o operator token (op_...) gerado no painel DePix.');
      return;
    }
    if (addr == null || addr.isEmpty || addr == 'indisponivel') {
      setState(() => _error =
          'Endereço Liquid da sua carteira indisponível. Abra a carteira e tente de novo.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reg = await _agent.register(
        name: name,
        operatorToken: opToken,
        operatorEmail: email,
        liquidAddress: addr,
      );
      if (mounted) setState(() => _result = reg);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activateWith(AgentKey? key, {required bool live}) async {
    if (key == null) {
      setState(() => _error = live
          ? 'A DePix não retornou uma chave de produção — sua conta ainda está em ativação.'
          : 'Chave de sandbox indisponível.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<PixService>()
          .configureProvider(type: 'depixapp', apiKey: key.key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(live
              ? 'Pix ativado (Reais reais — limite inicial até graduar).'
              : 'Pix ativado em modo sandbox (sem mover Reais de verdade).'),
          backgroundColor: IrisTheme.success,
        ),
      );
      Navigator.pop(context); // volta para a tela de ativação/config
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.bg,
        elevation: 0,
        title: const Text('Ativar Pix automaticamente',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
      ),
      body: MaxWidthContainer(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: _result == null ? _buildForm() : _buildResult(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _step(1, 'Crie/conecte sua conta DePix',
            'Abra o painel da DePix e conecte seu GitHub ou Google. Isso gera '
            'seu operator token (op_...) — é a âncora que prova que a conta é '
            'SUA, não do app.'),
        const SizedBox(height: 8),
        _copyRow(_dashboardUrl),
        const SizedBox(height: 24),

        _step(2, 'Seus dados', 'Ficam na sua conta DePix; o app não os guarda.'),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Nome de exibição'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(labelText: 'E-mail (notificações)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _opTokenCtrl,
          style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Operator token',
            hintText: 'op_...',
          ),
        ),
        const SizedBox(height: 24),

        _step(3, 'Endereço de recebimento',
            'Os depósitos DePix caem direto na SUA carteira Liquid não-custodial. '
            'Este endereço é fixado na conta e não muda depois.'),
        const SizedBox(height: 8),
        _liquidAddress == null
            ? const Text('Carregando endereço da sua carteira…',
                style: TextStyle(color: IrisTheme.textTertiary, fontSize: 12))
            : _monoBox(_liquidAddress!),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              style: const TextStyle(color: IrisTheme.danger, fontSize: 12)),
        ],

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _register,
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
                : const Text('Registrar conta DePix'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'A identidade da sua conta é um par de chaves gerado neste aparelho e '
          'nunca sai dele. Cada requisição é assinada localmente.',
          style: TextStyle(
              color: IrisTheme.textTertiary, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final reg = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: IrisTheme.success, size: 28),
            SizedBox(width: 12),
            Text('Conta criada!',
                style: TextStyle(
                    color: IrisTheme.success,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        if (reg.username != null)
          Text('Usuário: ${reg.username}',
              style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
        if (reg.liquidAddress != null) ...[
          const SizedBox(height: 4),
          Text('Recebimento: ${reg.liquidAddress}',
              style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
        ],
        const SizedBox(height: 24),
        const Text('Como quer começar?',
            style: TextStyle(
                color: IrisTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),

        _choiceCard(
          title: 'Modo sandbox (recomendado)',
          subtitle:
              'Testa o fluxo de ponta a ponta sem mover Reais de verdade. '
              'Ideal para validar antes do dinheiro real.',
          enabled: reg.testKey != null,
          onTap: () => _activateWith(reg.testKey, live: false),
        ),
        const SizedBox(height: 12),
        _choiceCard(
          title: 'Reais de verdade (limite inicial)',
          subtitle:
              'Chave starter: até R\$100 por transação e R\$500/dia até sua '
              'conta graduar (5 depósitos liquidados e maturados).',
          enabled: reg.liveStarterKey != null,
          onTap: () => _activateWith(reg.liveStarterKey, live: true),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              style: const TextStyle(color: IrisTheme.danger, fontSize: 12)),
        ],
      ],
    );
  }

  // --- pequenos blocos de UI ------------------------------------------------

  Widget _step(int n, String title, String body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: IrisTheme.primary, shape: BoxShape.circle),
                child: Text('$n',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(body,
                style: const TextStyle(
                    color: IrisTheme.textSecondary, fontSize: 12, height: 1.5)),
          ),
        ],
      );

  Widget _copyRow(String text) => Container(
        margin: const EdgeInsets.only(left: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: IrisTheme.s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: IrisTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copiado')),
                );
              },
              child: const Icon(Icons.copy, color: IrisTheme.textTertiary, size: 18),
            ),
          ],
        ),
      );

  Widget _monoBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: IrisTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'monospace',
                color: IrisTheme.textPrimary,
                fontSize: 12,
                height: 1.4)),
      );

  Widget _choiceCard({
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      Opacity(
        opacity: enabled && !_busy ? 1 : 0.5,
        child: InkWell(
          onTap: (enabled && !_busy) ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: IrisTheme.s1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: IrisTheme.bdr),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        color: IrisTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
        ),
      );
}
