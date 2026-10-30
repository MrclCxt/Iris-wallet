import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/currency_format.dart';
import '../../core/theme.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/wallet_service.dart';
import '../../troca/troca.dart';
import '../../troca/troca_service.dart';
import '../../widgets/max_width_container.dart';

/// Trocas P2P da Iris: comprar e vender bitcoin por Real com outros usuários
/// Iris. Os sats nunca passam pela Iris — ficam travados entre as duas
/// carteiras até quem vende confirmar que recebeu o Real.
class TrocasScreen extends StatelessWidget {
  const TrocasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => TrocaService(
        carteira: ctx.read<WalletService>(),
        cotacao: ctx.read<ExchangeRateService>(),
      )..abrir(),
      child: const _TrocasCorpo(),
    );
  }
}

class _TrocasCorpo extends StatefulWidget {
  const _TrocasCorpo();

  @override
  State<_TrocasCorpo> createState() => _TrocasCorpoState();
}

class _TrocasCorpoState extends State<_TrocasCorpo> {
  Future<List<OfertaIris>>? _ofertas;
  bool _quero = true; // true: quero comprar bitcoin

  @override
  void initState() {
    super.initState();
    _ofertas = context.read<TrocaService>().ofertas();
  }

  void _erro(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))));
  }

  Future<String?> _pedirTexto(String titulo, String dica,
      {TextInputType teclado = TextInputType.text}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        title: Text(titulo,
            style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: teclado,
          autofocus: true,
          style: const TextStyle(color: IrisTheme.textPrimary),
          decoration: InputDecoration(hintText: dica),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _tomar(OfertaIris o) async {
    final svc = context.read<TrocaService>();
    final valor = await _pedirTexto('Quanto em Real?',
        'De ${o.fiatMin.toStringAsFixed(0)} a ${o.fiatMax.toStringAsFixed(0)}',
        teclado: const TextInputType.numberWithOptions(decimal: true));
    final fiat = double.tryParse((valor ?? '').replaceAll(',', '.'));
    if (fiat == null) return;
    String? instrucao;
    if (!o.anuncianteVende) {
      instrucao = await _pedirTexto(
          'Onde receber o Real?', 'Sua chave Pix (vai cifrada só para quem paga)');
      if (instrucao == null || instrucao.isEmpty) return;
    }
    try {
      await svc.aceitar(o, fiat, instrucao: instrucao);
      if (mounted) setState(() {});
    } catch (e) {
      _erro(e);
    }
  }

  Future<void> _anunciar() async {
    final svc = context.read<TrocaService>();
    final vendo = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: IrisTheme.s1,
        title: const Text('Anunciar',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vender bitcoin (recebo Real)')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Comprar bitcoin (pago Real)')),
        ],
      ),
    );
    if (vendo == null) return;
    final faixa = await _pedirTexto('Faixa em Real', 'Ex.: 50-500',
        teclado: TextInputType.text);
    final partes = (faixa ?? '').split('-').map((p) => double.tryParse(p.trim()));
    final nums = partes.whereType<double>().toList();
    if (nums.isEmpty) return;
    String? instrucao;
    if (vendo) {
      instrucao = await _pedirTexto('Onde receber o Real?',
          'Sua chave Pix (fica neste aparelho; vai cifrada a quem tomar)');
      if (instrucao == null || instrucao.isEmpty) return;
    }
    try {
      final aceitos = await svc.anunciar(
        vendo: vendo,
        fiatMin: nums.first,
        fiatMax: nums.last,
        metodos: const ['Pix'],
        instrucao: instrucao,
      );
      _erro(aceitos == 0
          ? 'Nenhum relay aceitou o anúncio.'
          : 'Anúncio publicado em $aceitos relays.');
      setState(() => _ofertas = svc.ofertas());
    } catch (e) {
      _erro(e);
    }
  }

  Future<void> _pagarConta() async {
    final svc = context.read<TrocaService>();
    final codigo = await _pedirTexto('Pagar conta',
        'Linha digitável do boleto ou Pix copia e cola');
    if (codigo == null || codigo.isEmpty) return;
    final valor = await _pedirTexto('Valor da conta (R\$)', 'Ex.: 129,90',
        teclado: const TextInputType.numberWithOptions(decimal: true));
    final v = double.tryParse((valor ?? '').replaceAll('.', '').replaceAll(',', '.'));
    if (v == null) return;
    try {
      final aceitos = await svc.pedirPagamentoDeConta(codigo: codigo, valorBrl: v);
      _erro(aceitos == 0
          ? 'Nenhum relay aceitou o pedido.'
          : 'Pedido publicado. Quando alguém pagar a conta, os sats saem '
              'travados da sua carteira e só são liberados por você.');
    } catch (e) {
      _erro(e);
    }
  }

  Future<void> _configurar() async {
    final svc = context.read<TrocaService>();
    final atual = await svc.arbitroPadrao();
    if (!mounted) return;
    final ctrl = TextEditingController(text: atual ?? '');
    final minha = svc.chaves.publica;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        title: const Text('Árbitro', style: TextStyle(color: IrisTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Quem resolve disputas das suas ofertas. O árbitro só consegue '
                'liberar os sats para quem comprou — nunca para si mesmo.',
                style: TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
            TextField(
              controller: ctrl,
              decoration:
                  const InputDecoration(hintText: 'Chave do árbitro (64 hex)'),
            ),
            const SizedBox(height: 16),
            const Text('Sua chave (para ser árbitro de alguém):',
                style: TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
            InkWell(
              onTap: () => Clipboard.setData(ClipboardData(text: minha)),
              child: Text('$minha  (tocar copia)',
                  style: const TextStyle(
                      color: IrisTheme.primary,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Fechar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (salvar == true) {
      try {
        await svc.definirArbitroPadrao(ctrl.text);
        _erro('Árbitro salvo para as próximas ofertas.');
      } catch (e) {
        _erro(e);
      }
    }
  }

  Widget _cartaoCaso(CasoArbitragem c) {
    final svc = context.read<TrocaService>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IrisTheme.warning.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${CurrencyFormatter.formatBtcOrSats(c.sats)} por '
              'R\$ ${CurrencyFormatter.formatBrl(c.fiat)}',
              style: const TextStyle(
                  color: IrisTheme.textPrimary, fontWeight: FontWeight.w700)),
          for (final e in c.alegacoes.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${e.key}: ${e.value}',
                  style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 13)),
            ),
          if (c.decisao != null)
            Text('Decidido a favor do ${c.decisao}.',
                style: const TextStyle(color: IrisTheme.success))
          else
            Wrap(spacing: 8, children: [
              ElevatedButton(
                  onPressed: () =>
                      svc.decidir(c, favorComprador: true).catchError(_erro),
                  child: const Text('Comprador pagou: liberar')),
              TextButton(
                  onPressed: () =>
                      svc.decidir(c, favorComprador: false).catchError(_erro),
                  child: const Text('Devolver ao vendedor')),
            ]),
        ],
      ),
    );
  }

  String _estadoTexto(Troca t) {
    final souV = t.papel == PapelTroca.vendedor;
    return switch (t.estado) {
      EstadoTroca.aceita => 'Combinando…',
      EstadoTroca.hashEnviado => souV ? 'Esperando a fatura' : 'Criando fatura…',
      EstadoTroca.faturaEnviada =>
        souV ? 'Fatura conferida — travar os sats' : 'Esperando o vendedor travar',
      EstadoTroca.travada => souV
          ? 'Sats travados. Esperando o pagamento'
          : 'Sats travados! Pague e avise',
      EstadoTroca.realPago => souV
          ? 'Comprador diz que pagou. Confira o banco'
          : 'Esperando o vendedor liberar',
      EstadoTroca.concluida => 'Concluída',
      EstadoTroca.cancelada => 'Cancelada',
      EstadoTroca.disputa => 'Em disputa — o árbitro decide antes do prazo da trava',
    };
  }

  Widget _acoes(Troca t) {
    final svc = context.read<TrocaService>();
    final souV = t.papel == PapelTroca.vendedor;
    final botoes = <Widget>[];
    if (souV && t.estado == EstadoTroca.faturaEnviada) {
      botoes.add(ElevatedButton(
          onPressed: () => svc.pagarFatura(t).catchError(_erro),
          child: const Text('Travar sats')));
    }
    if (!souV && t.estado == EstadoTroca.travada) {
      botoes.add(ElevatedButton(
        onPressed: () async {
          final c = await _pedirTexto(
              'Comprovante', 'Código/ID do pagamento');
          if (c == null || c.isEmpty) return;
          svc.informarPago(t, c).catchError(_erro);
        },
        child: const Text('Já paguei'),
      ));
    }
    if (souV && t.estado == EstadoTroca.realPago) {
      botoes.add(ElevatedButton(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: IrisTheme.s1,
              title: const Text('Recebeu o Real?'),
              content: Text(
                  'Confira no app do banco que R\$ ${CurrencyFormatter.formatBrl(t.fiatBrl)} '
                  'entraram. Liberar não tem volta.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Ainda não')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Recebi — liberar')),
              ],
            ),
          );
          if (ok == true) svc.liberar(t).catchError(_erro);
        },
        child: const Text('Liberar sats'),
      ));
    }
    if (t.arbitro != null &&
        (t.estado == EstadoTroca.travada || t.estado == EstadoTroca.realPago)) {
      botoes.add(TextButton(
        onPressed: () async {
          final motivo = await _pedirTexto('Abrir disputa',
              'O que aconteceu? (vai cifrado para o árbitro e o outro lado)');
          if (motivo == null || motivo.isEmpty) return;
          svc.abrirDisputa(t, motivo).catchError(_erro);
        },
        child: const Text('Abrir disputa'),
      ));
    }
    if (!t.encerrada && !(souV && t.estado == EstadoTroca.realPago)) {
      botoes.add(TextButton(
          onPressed: () => svc.cancelar(t, 'cancelada pelo usuário').catchError(_erro),
          child: const Text('Cancelar')));
    }
    return Wrap(spacing: 8, children: botoes);
  }

  Widget _cartaoTroca(Troca t) {
    final souV = t.papel == PapelTroca.vendedor;
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
          Text(
              '${souV ? 'Vendendo' : 'Comprando'} ${CurrencyFormatter.formatBtcOrSats(t.sats)} '
              'por R\$ ${CurrencyFormatter.formatBrl(t.fiatBrl)}',
              style: const TextStyle(
                  color: IrisTheme.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_estadoTexto(t),
              style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 13)),
          if (!souV &&
              t.instrucaoPagamento != null &&
              t.estado == EstadoTroca.travada) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () =>
                  Clipboard.setData(ClipboardData(text: t.instrucaoPagamento!)),
              child: Text('Pague para: ${t.instrucaoPagamento}  (tocar copia)',
                  style: const TextStyle(color: IrisTheme.primary, fontSize: 13)),
            ),
          ],
          if (!souV && t.estado.index < EstadoTroca.travada.index)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Não pague nada antes de ver "Sats travados".',
                  style: TextStyle(color: IrisTheme.warning, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          _acoes(t),
        ],
      ),
    );
  }

  Widget _cartaoOferta(OfertaIris o, String minhaChave) {
    final minha = o.autor == minhaChave;
    return Card(
      color: IrisTheme.s1,
      child: ListTile(
        title: Text(
            'R\$ ${o.fiatMin.toStringAsFixed(0)} – ${o.fiatMax.toStringAsFixed(0)}',
            style: const TextStyle(color: IrisTheme.textPrimary)),
        subtitle: Text(
            '${o.metodos.join(', ')} · ${o.premio == 0 ? 'preço de mercado' : '${o.premio}%'}'
            '${o.arbitro != null ? ' · com árbitro ${o.arbitro!.substring(0, 8)}…' : ' · sem árbitro'}'
            '${minha ? ' · sua oferta' : ''}',
            style: const TextStyle(color: IrisTheme.textSecondary)),
        trailing: minha
            ? TextButton(
                onPressed: () async {
                  final svc = context.read<TrocaService>();
                  await svc.retirarOferta(o);
                  setState(() => _ofertas = svc.ofertas());
                },
                child: const Text('Retirar'))
            : ElevatedButton(
                onPressed: () => _tomar(o),
                child: Text(o.anuncianteVende ? 'Comprar' : 'Vender')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<TrocaService>();
    String minhaChave = '';
    try {
      minhaChave = svc.chaves.publica;
    } catch (_) {}
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: IrisTheme.bg,
        appBar: AppBar(
          backgroundColor: IrisTheme.bg,
          elevation: 0,
          title: const Text('Trocas P2P (prévia)',
              style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
          iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
          bottom: const TabBar(tabs: [Tab(text: 'Ofertas'), Tab(text: 'Minhas trocas')]),
          actions: [
            IconButton(
                icon: const Icon(Icons.gavel),
                tooltip: 'Árbitro',
                onPressed: _configurar),
            IconButton(
                icon: const Icon(Icons.receipt_long),
                tooltip: 'Pagar conta com bitcoin',
                onPressed: _pagarConta),
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() => _ofertas = svc.ofertas())),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _anunciar,
          icon: const Icon(Icons.add),
          label: const Text('Anunciar'),
        ),
        body: MaxWidthContainer(
          child: TabBarView(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Quero comprar')),
                        ButtonSegment(value: false, label: Text('Quero vender')),
                      ],
                      selected: {_quero},
                      onSelectionChanged: (s) => setState(() => _quero = s.first),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<OfertaIris>>(
                      future: _ofertas,
                      builder: (ctx, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final lista = (snap.data ?? const <OfertaIris>[])
                            .where((o) => o.anuncianteVende == _quero)
                            .toList();
                        if (lista.isEmpty) {
                          return const Center(
                              child: Text('Nenhuma oferta agora. Anuncie a sua!',
                                  style: TextStyle(color: IrisTheme.textSecondary)));
                        }
                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [for (final o in lista) _cartaoOferta(o, minhaChave)],
                        );
                      },
                    ),
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (svc.ultimoErro != null)
                    Text('Última mensagem recusada: ${svc.ultimoErro}',
                        style: const TextStyle(color: IrisTheme.danger, fontSize: 12)),
                  if (svc.trocas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                          child: Text('Nenhuma troca ainda.',
                              style: TextStyle(color: IrisTheme.textSecondary))),
                    ),
                  for (final t in svc.trocas) _cartaoTroca(t),
                  if (svc.casos.any((c) => c.alegacoes.isNotEmpty)) ...[
                    const SizedBox(height: 16),
                    const Text('Arbitragem (você é o árbitro)',
                        style: TextStyle(
                            color: IrisTheme.textPrimary,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final c in svc.casos.where((c) => c.alegacoes.isNotEmpty))
                      _cartaoCaso(c),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
