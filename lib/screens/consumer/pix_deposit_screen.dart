import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/pix_service.dart';
import '../../services/exchange_rate_service.dart';

/// Hub PIX: entrada e saída de Reais.
///
/// Receber: PIX (BRL) -> DEPIX (Liquid) -> L-BTC -> saldo em sats.
/// Enviar:  sats -> L-BTC -> DEPIX -> provedor paga a chave PIX em BRL.
/// O usuário só vê Reais de um lado e satoshis do outro.
class PixDepositScreen extends StatefulWidget {
  const PixDepositScreen({super.key});

  @override
  State<PixDepositScreen> createState() => _PixDepositScreenState();
}

class _PixDepositScreenState extends State<PixDepositScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _brlCtrl = TextEditingController();
  final TextEditingController _brlOutCtrl = TextEditingController();
  final TextEditingController _pixKeyCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _brlCtrl.dispose();
    _brlOutCtrl.dispose();
    _pixKeyCtrl.dispose();
    super.dispose();
  }

  double _parseBrl(TextEditingController c) {
    final raw = c.text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? IrisTheme.danger : null),
    );
  }

  Future<void> _startDeposit() async {
    final brl = _parseBrl(_brlCtrl);
    if (brl <= 0) return _snack('Informe o valor em Reais.', error: true);
    final rate = context.read<ExchangeRateService>();
    if (!rate.hasRate) {
      rate.fetchRate();
      return _snack('Cotação BTC/BRL indisponível. Tente em instantes.', error: true);
    }
    setState(() => _busy = true);
    try {
      await context.read<PixService>().startDeposit(brl);
    } catch (e) {
      _snack('Erro ao criar cobrança: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startWithdrawal() async {
    final brl = _parseBrl(_brlOutCtrl);
    final pixKey = _pixKeyCtrl.text.trim();
    if (brl <= 0) return _snack('Informe o valor em Reais.', error: true);
    if (pixKey.isEmpty) return _snack('Informe a chave PIX do destinatário.', error: true);
    setState(() => _busy = true);
    try {
      await context.read<PixService>().startWithdrawal(amountBrl: brl, pixKey: pixKey);
    } catch (e) {
      _snack('Erro no saque: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showProviderConfig() {
    final pix = context.read<PixService>();
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: IrisTheme.bdr),
        ),
        title: const Text('Provedor PIX/DEPIX', style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Atual: ${pix.provider.name}',
                style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'URL base da API (vazio = simulado)',
                hintText: 'https://api.provedor.com/v1',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Chave de API'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: IrisTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await pix.configureProvider(baseUrl: urlCtrl.text, apiKey: keyCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pix = context.watch<PixService>();
    final rate = context.watch<ExchangeRateService>();

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('PIX',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: IrisTheme.textSecondary),
            tooltip: 'Provedor PIX/DEPIX',
            onPressed: _showProviderConfig,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: IrisTheme.primary,
          labelColor: IrisTheme.primary,
          unselectedLabelColor: IrisTheme.textSecondary,
          tabs: const [
            Tab(text: '⬇ Receber R\$'),
            Tab(text: '⬆ Enviar R\$'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildDepositTab(pix, rate),
          _buildWithdrawTab(pix, rate),
        ],
      ),
    );
  }

  Widget _buildDepositTab(PixService pix, ExchangeRateService rate) {
    final charge = pix.activeCharge;
    final satsPreview = rate.brlToSats(_parseBrl(_brlCtrl));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (charge == null || charge.status == PixChargeStatus.expired || charge.status == PixChargeStatus.failed) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: IrisTheme.s1,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: IrisTheme.bdr),
              ),
              child: Column(
                children: [
                  const Text('Valor do depósito', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                  TextField(
                    controller: _brlCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono', fontSize: 36, fontWeight: FontWeight.w600, color: IrisTheme.textPrimary),
                    decoration: const InputDecoration(
                      prefixText: 'R\$ ',
                      prefixStyle: TextStyle(fontSize: 24, color: IrisTheme.textSecondary),
                      hintText: '0,00',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  Text('≈ ${CurrencyFormatter.formatSats(satsPreview)} sats',
                      style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13, color: IrisTheme.primary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _startDeposit,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Gerar cobrança PIX', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ] else ...[
            // Cobrança ativa: QR + copia-e-cola
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  QrImageView(data: charge.qrCopiaECola, version: QrVersions.auto, size: 200),
                  const SizedBox(height: 12),
                  Text(
                    charge.qrCopiaECola,
                    style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, color: Colors.black54),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'R\$ ${CurrencyFormatter.formatBrl(charge.amountBrl)} — ${_statusLabel(charge.status)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: charge.status == PixChargeStatus.pending ? IrisTheme.primary : IrisTheme.success,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: charge.qrCopiaECola));
                _snack('Copia-e-cola copiado!');
              },
              icon: const Icon(Icons.copy, size: 16, color: IrisTheme.primary),
              label: const Text('Copiar código PIX', style: TextStyle(color: IrisTheme.primary)),
            ),
            if (pix.provider.isSimulated && charge.status == PixChargeStatus.pending) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => pix.simulatePaymentReceived(),
                style: ElevatedButton.styleFrom(backgroundColor: IrisTheme.success),
                child: const Text('Simular pagamento do PIX (testnet)'),
              ),
            ],
          ],
          const SizedBox(height: 16),
          _buildLogs(pix.logs),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Provedor: ${pix.provider.name} · Rota: PIX → DEPIX (Liquid) → sats',
              style: const TextStyle(fontSize: 10, color: IrisTheme.textTertiary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawTab(PixService pix, ExchangeRateService rate) {
    final satsCost = rate.brlToSats(_parseBrl(_brlOutCtrl));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: IrisTheme.s1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: IrisTheme.bdr),
            ),
            child: Column(
              children: [
                const Text('Valor a enviar', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                TextField(
                  controller: _brlOutCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'JetBrains Mono', fontSize: 36, fontWeight: FontWeight.w600, color: IrisTheme.textPrimary),
                  decoration: const InputDecoration(
                    prefixText: 'R\$ ',
                    prefixStyle: TextStyle(fontSize: 24, color: IrisTheme.textSecondary),
                    hintText: '0,00',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Text('custa ≈ ${CurrencyFormatter.formatSats(satsCost)} sats do seu saldo',
                    style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13, color: IrisTheme.primary)),
                const SizedBox(height: 16),
                TextField(
                  controller: _pixKeyCtrl,
                  style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Chave PIX do destinatário',
                    hintText: 'CPF, e-mail, telefone ou chave aleatória',
                    labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                    hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                    filled: true,
                    fillColor: IrisTheme.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _startWithdrawal,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Enviar via PIX', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 16),
          _buildLogs(pix.logs),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Rota: sats → L-BTC → DEPIX → provedor paga o PIX em R\$',
              style: TextStyle(fontSize: 10, color: IrisTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogs(List<String> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ANDAMENTO',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: IrisTheme.textTertiary)),
          const SizedBox(height: 8),
          for (final log in logs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(log,
                  style: const TextStyle(
                      fontFamily: 'JetBrains Mono', fontSize: 11, color: IrisTheme.textSecondary, height: 1.4)),
            ),
        ],
      ),
    );
  }

  String _statusLabel(PixChargeStatus status) {
    switch (status) {
      case PixChargeStatus.pending:
        return 'aguardando pagamento';
      case PixChargeStatus.paid:
        return 'pago! convertendo...';
      case PixChargeStatus.settled:
        return 'liquidado';
      case PixChargeStatus.expired:
        return 'expirado';
      case PixChargeStatus.failed:
        return 'falhou';
    }
  }
}
