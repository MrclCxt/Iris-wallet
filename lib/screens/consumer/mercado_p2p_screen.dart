import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/currency_format.dart';
import '../../core/theme.dart';
import '../../nostr/ordens_p2p.dart';
import '../../widgets/max_width_container.dart';

/// Prévia: ofertas P2P abertas em Real, lidas direto dos relays Nostr
/// (padrão NIP-69). A Iris só mostra; a negociação é na plataforma de origem.
class MercadoP2PScreen extends StatefulWidget {
  const MercadoP2PScreen({super.key});

  @override
  State<MercadoP2PScreen> createState() => _MercadoP2PScreenState();
}

class _MercadoP2PScreenState extends State<MercadoP2PScreen> {
  late Future<List<OrdemP2P>> _ordens;
  bool _quemVende = true;

  @override
  void initState() {
    super.initState();
    _ordens = OrdensP2P.abertas();
  }

  String _fiat(OrdemP2P o) {
    final min = o.fiatMin, max = o.fiatMax;
    if (min == null) return 'valor a combinar';
    if (max == null || max == min) return 'R\$ ${CurrencyFormatter.formatBrl(min)}';
    return 'R\$ ${CurrencyFormatter.formatBrl(min)} – ${CurrencyFormatter.formatBrl(max)}';
  }

  Widget _cartao(OrdemP2P o) {
    final premio = o.premio == 0
        ? 'preço de mercado'
        : '${o.premio > 0 ? '+' : ''}${o.premio.toStringAsFixed(1)}% sobre o mercado';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_fiat(o),
                    style: const TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              Text(o.plataforma,
                  style: const TextStyle(
                      color: IrisTheme.textTertiary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text(premio,
              style:
                  const TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
          if (o.metodos.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(o.metodos.join(' · '),
                style: const TextStyle(
                    color: IrisTheme.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                  '${o.camada} · ${o.rede}${o.nome != null ? ' · ${o.nome}' : ''}',
                  style: const TextStyle(
                      color: IrisTheme.textTertiary, fontSize: 11)),
              const Spacer(),
              if (o.origem != null)
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: o.origem!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Link da oferta copiado.')));
                  },
                  child: const Text('Copiar link'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.bg,
        elevation: 0,
        title: const Text('Ofertas P2P (prévia)',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _ordens = OrdensP2P.abertas()),
          ),
        ],
      ),
      body: MaxWidthContainer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Comprar bitcoin')),
                    ButtonSegment(value: false, label: Text('Vender bitcoin')),
                  ],
                  selected: {_quemVende},
                  onSelectionChanged: (s) => setState(() => _quemVende = s.first),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Ofertas públicas de Mostro, RoboSats, Peach e lnp2pBot, '
                  'lidas direto da rede Nostr. A Iris não intermedeia: a '
                  'negociação acontece na plataforma de cada oferta.',
                  style: TextStyle(
                      color: IrisTheme.textTertiary, fontSize: 11, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<OrdemP2P>>(
                  future: _ordens,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: IrisTheme.primary));
                    }
                    final lista = (snap.data ?? const <OrdemP2P>[])
                        .where((o) => o.vendeBitcoin == _quemVende)
                        .toList();
                    if (lista.isEmpty) {
                      return const Center(
                        child: Text('Nenhuma oferta aberta agora.',
                            style: TextStyle(color: IrisTheme.textSecondary)),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [for (final o in lista) _cartao(o)],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
