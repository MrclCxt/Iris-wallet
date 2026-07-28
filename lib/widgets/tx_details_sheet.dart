import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/currency_format.dart';
import '../core/theme.dart';
import '../services/node_backend.dart';
import '../services/wallet_service.dart';
import 'tx_status.dart';

class _DadosDaRede {
  final bool confirmada;
  final int? bloco;
  final int? confirmacoes;
  final int? taxaSats;
  final List<({String? endereco, int valor})> entradas;
  final List<({String? endereco, int valor})> saidas;

  const _DadosDaRede({
    required this.confirmada,
    this.bloco,
    this.confirmacoes,
    this.taxaSats,
    this.entradas = const [],
    this.saidas = const [],
  });
}

class TxDetailsSheet extends StatefulWidget {
  final Transaction tx;
  final bool showSats;
  final double brlRate;

  const TxDetailsSheet({
    super.key,
    required this.tx,
    required this.showSats,
    required this.brlRate,
  });

  static Future<void> abrir(
    BuildContext context, {
    required Transaction tx,
    required bool showSats,
    required double brlRate,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          TxDetailsSheet(tx: tx, showSats: showSats, brlRate: brlRate),
    );
  }

  @override
  State<TxDetailsSheet> createState() => _TxDetailsSheetState();
}

class _TxDetailsSheetState extends State<TxDetailsSheet> {
  _DadosDaRede? _rede;
  bool _carregando = true;
  String? _erro;

  bool get _ehOnchain => widget.tx.id.length == 64;

  @override
  void initState() {
    super.initState();
    if (_ehOnchain) {
      _buscarNaRede();
    } else {
      _carregando = false;
    }
  }

  Future<void> _buscarNaRede() async {
    final base = EmbeddedNodeApi.esploraEmUso;
    if (base == null) {
      setState(() {
        _carregando = false;
        _erro = 'Sem servidor da rede configurado.';
      });
      return;
    }

    try {
      final r = await http
          .get(Uri.parse('$base/tx/${widget.tx.id}'))
          .timeout(const Duration(seconds: 12));

      if (r.statusCode == 404) {
        setState(() {
          _carregando = false;
          _erro = 'Esta transação não existe na rede.';
        });
        return;
      }
      if (r.statusCode != 200) {
        setState(() {
          _carregando = false;
          _erro = 'A rede respondeu com erro ${r.statusCode}.';
        });
        return;
      }

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final st = (j['status'] as Map<String, dynamic>?) ?? const {};
      final confirmada = st['confirmed'] == true;
      final bloco = (st['block_height'] as num?)?.toInt();

      int? confirmacoes;
      if (confirmada && bloco != null) {
        try {
          final t = await http
              .get(Uri.parse('$base/blocks/tip/height'))
              .timeout(const Duration(seconds: 8));
          final topo = int.tryParse(t.body.trim());
          if (topo != null) confirmacoes = topo - bloco + 1;
        } catch (_) {}
      }

      List<({String? endereco, int valor})> mapear(
              List<dynamic> lista, bool ehEntrada) =>
          lista.map((e) {
            final m = ehEntrada
                ? ((e as Map<String, dynamic>)['prevout']
                        as Map<String, dynamic>?) ??
                    const {}
                : e as Map<String, dynamic>;
            return (
              endereco: m['scriptpubkey_address'] as String?,
              valor: (m['value'] as num?)?.toInt() ?? 0,
            );
          }).toList();

      if (!mounted) return;
      setState(() {
        _carregando = false;
        _rede = _DadosDaRede(
          confirmada: confirmada,
          bloco: bloco,
          confirmacoes: confirmacoes,
          taxaSats: (j['fee'] as num?)?.toInt(),
          entradas: mapear(j['vin'] as List<dynamic>? ?? const [], true),
          saidas: mapear(j['vout'] as List<dynamic>? ?? const [], false),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível consultar a rede agora.';
      });
    }
  }

  void _copiar(String texto, String oQue) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$oQue copiado.'),
        backgroundColor: IrisTheme.s2,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final sinal = tx.isIncoming ? '+' : '-';
    final cor = tx.isIncoming ? IrisTheme.success : IrisTheme.danger;
    final brl = widget.brlRate > 0
        ? (tx.amountSats / 100000000) * widget.brlRate
        : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: IrisTheme.s1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: IrisTheme.bdr,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(tx.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tx.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '$sinal${CurrencyFormatter.formatBtcOrSats(tx.amountSats)}',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: cor),
            ),
            if (widget.brlRate > 0)
              Text(
                '≈ R\$ ${CurrencyFormatter.formatBrlCompact(brl)}',
                style: const TextStyle(
                    fontSize: 13,
                    color: IrisTheme.textSecondary,
                    fontFamily: 'monospace'),
              ),
            const SizedBox(height: 16),
            TxStatusChip(status: _statusEfetivo),
            const SizedBox(height: 20),
            _linha('Data', _dataCompleta(tx.date)),
            if (_rede?.bloco != null) _linha('Bloco', '${_rede!.bloco}'),
            if (_rede?.confirmacoes != null)
              _linha('Confirmações', '${_rede!.confirmacoes}'),
            if (_rede?.taxaSats != null)
              _linha('Taxa de rede', '${_rede!.taxaSats} sats'),
            const SizedBox(height: 8),
            _blocoId(),
            if (_carregando) ...[
              const SizedBox(height: 22),
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(IrisTheme.primary)),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text('Consultando a rede…',
                    style: TextStyle(
                        fontSize: 12, color: IrisTheme.textSecondary)),
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: IrisTheme.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: IrisTheme.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: IrisTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_erro!,
                          style: const TextStyle(
                              fontSize: 12, color: IrisTheme.textSecondary)),
                    ),
                  ],
                ),
              ),
            ],
            if (_rede != null) ...[
              const SizedBox(height: 22),
              _secaoEnderecos('De', _origem),
              const SizedBox(height: 16),
              _secaoEnderecos('Para', _destino),
              if (_trocoOmitido) ...[
                const SizedBox(height: 10),
                const Text(
                  'O troco que voltou para a sua carteira não é listado aqui.',
                  style:
                      TextStyle(fontSize: 11, color: IrisTheme.textTertiary),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  bool _trocoOmitido = false;

  List<({String? endereco, int valor})> get _origem =>
      _rede?.entradas ?? const [];

  /// Numa transação Bitcoin a moeda é gasta inteira e a diferença volta como
  /// troco para a própria carteira. Esse troco não é a outra parte do
  /// pagamento, então a saída mostrada é a que bate com o valor da transação.
  List<({String? endereco, int valor})> get _destino {
    final saidas = _rede?.saidas ?? const <({String? endereco, int valor})>[];
    if (saidas.length < 2) {
      _trocoOmitido = false;
      return saidas;
    }

    final alvo = widget.tx.amountSats;
    final exatas = saidas.where((o) => o.valor == alvo).toList();
    if (exatas.isNotEmpty && exatas.length < saidas.length) {
      _trocoOmitido = true;
      return exatas;
    }

    _trocoOmitido = false;
    return saidas;
  }

  String get _statusEfetivo {
    if (_rede == null) return widget.tx.status;
    return _rede!.confirmada ? 'confirmed' : 'pending';
  }

  static String _dataCompleta(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} às ${p(d.hour)}:${p(d.minute)}';
  }

  Widget _linha(String rotulo, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(rotulo,
                style: const TextStyle(
                    fontSize: 12.5, color: IrisTheme.textSecondary)),
            Text(valor,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
          ],
        ),
      );

  Widget _blocoId() {
    final id = widget.tx.id;
    if (id.isEmpty) return const SizedBox.shrink();
    final rotulo = _ehOnchain ? 'ID da transação na rede' : 'Identificador';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo,
              style: const TextStyle(
                  fontSize: 12.5, color: IrisTheme.textSecondary)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _copiar(id, 'ID da transação'),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: IrisTheme.s2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: IrisTheme.bdr),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(id,
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace')),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_rounded,
                      size: 15, color: IrisTheme.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoEnderecos(
      String titulo, List<({String? endereco, int valor})> itens) {
    if (itens.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: IrisTheme.textSecondary)),
        const SizedBox(height: 8),
        for (final it in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: it.endereco == null
                  ? null
                  : () => _copiar(it.endereco!, 'Endereço'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: IrisTheme.s2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: IrisTheme.bdr),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.endereco ?? '(endereço não legível)',
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      CurrencyFormatter.formatBtcOrSats(it.valor),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
