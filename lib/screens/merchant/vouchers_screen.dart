import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/currency_format.dart';
import '../../core/theme.dart';
import '../../core/varredura.dart';
import '../../services/taxa_rede.dart';
import '../../services/voucher_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/max_width_container.dart';

/// Prévia: o lojista emite vouchers Bitcoin para vender no balcão. Cada voucher
/// é uma chave nova financiada pela carteira; quem tem o papel tem o bitcoin.
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  late final VoucherService _svc =
      VoucherService(context.read<WalletService>());
  final _valor = TextEditingController();
  ChaveAvulsa? _ultimo;
  int _ultimoSats = 0;
  bool _ocupado = false;

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _emitir() async {
    final sats = int.tryParse(_valor.text.replaceAll('.', '').trim());
    if (sats == null || sats < 5000) {
      _msg('Mínimo de 5.000 sats, para a taxa do resgate não comer o voucher.');
      return;
    }
    setState(() => _ocupado = true);
    try {
      final k = await _svc.emitir(sats, confirmar: (envio) async {
        final alerta = TaxaRede.alerta(taxa: envio.taxa, valor: sats);
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: IrisTheme.s1,
            title: const Text('Taxa da rede'),
            content: Text(
                'Financiar o voucher de ${CurrencyFormatter.formatBtcOrSats(sats)} '
                'custa ${CurrencyFormatter.formatBtcOrSats(envio.taxa)} de taxa '
                '(${envio.satPorVbyte.toStringAsFixed(1)} sat/vB).'
                '${alerta != null ? '\n\n$alerta' : ''}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Emitir')),
            ],
          ),
        );
        return ok == true;
      });
      if (k == null) return;
      setState(() {
        _ultimo = k;
        _ultimoSats = sats;
      });
    } catch (e) {
      _msg(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _reaver(String wif) async {
    try {
      await _svc.resgatar(wif);
      _msg('Voucher reavido para a sua carteira.');
    } catch (e) {
      _msg(e.toString().replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.bg,
        elevation: 0,
        title: const Text('Vouchers Bitcoin (prévia)',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
      ),
      body: MaxWidthContainer(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Venda bitcoin no balcão sem intermediário: o voucher é uma chave '
              'nova, financiada pela sua carteira. O cliente lê o QR no Iris '
              '(ou em qualquer carteira) e resgata.',
              style: TextStyle(color: IrisTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: IrisTheme.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: IrisTheme.warning.withOpacity(0.4)),
              ),
              child: const Text(
                'Título ao portador: quem tiver o papel tem o bitcoin. Você, que '
                'emitiu, também conhece a chave — use valores pequenos e guarde '
                'os papéis como dinheiro vivo.',
                style: TextStyle(color: IrisTheme.warning, fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _valor,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: IrisTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Valor em sats'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _ocupado ? null : _emitir,
              child: Text(_ocupado ? 'Emitindo…' : 'Emitir voucher'),
            ),
            if (_ultimo != null) ...[
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  color: Colors.white,
                  child: QrImageView(data: _ultimo!.wif, size: 240),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                    'Voucher de ${CurrencyFormatter.formatBtcOrSats(_ultimoSats)} — '
                    'vale depois que a rede confirmar o envio',
                    style: const TextStyle(color: IrisTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _ultimo!.wif)),
                child: const Text('Copiar chave (para imprimir)'),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Emitidos neste aparelho',
                style: TextStyle(
                    color: IrisTheme.textPrimary, fontWeight: FontWeight.w700)),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _svc.emitidosGuardados(),
              builder: (ctx, snap) => Column(
                children: [
                  for (final v in (snap.data ?? const []).reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          CurrencyFormatter.formatBtcOrSats(v['sats'] as int),
                          style: const TextStyle(color: IrisTheme.textPrimary)),
                      subtitle: Text((v['em'] as String).substring(0, 16),
                          style: const TextStyle(color: IrisTheme.textTertiary)),
                      trailing: TextButton(
                        onPressed: () => _reaver(v['wif'] as String),
                        child: const Text('Reaver'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
