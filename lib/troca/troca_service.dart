import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/rede.dart';
import '../nostr/chaves.dart';
import '../nostr/evento.dart';
import '../nostr/nip44.dart';
import '../nostr/relays.dart';
import '../services/exchange_rate_service.dart';
import '../services/wallet_service.dart';
import 'troca.dart';

/// Liga o protocolo de troca à rede Nostr e à carteira. Tudo roda no aparelho:
/// não há servidor da Iris. As mensagens só são buscadas com a tela de trocas
/// aberta (sem serviço em segundo plano, sem push de terceiros).
class TrocaService extends ChangeNotifier {
  final WalletService carteira;
  final ExchangeRateService cotacao;

  TrocaService({required this.carteira, required this.cotacao}) {
    _travasSub = carteira.travasRecebidas.listen(_aoChegarTrava);
  }

  static const _armazenamento = FlutterSecureStorage();
  static const Duration _intervalo = Duration(seconds: 6);

  StreamSubscription<TravaRecebida>? _travasSub;
  Timer? _vigia;
  ChavesNostr? _chaves;
  int _desde = 0;
  final Map<String, Troca> _trocas = {};
  final Map<String, int> _travaMsat = {};
  final Set<String> _mensagensVistas = {};
  String? ultimoErro;

  List<Troca> get trocas =>
      _trocas.values.toList()..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));

  static String get redeNip69 => Rede.principal ? 'mainnet' : 'testnet4';

  ChavesNostr get chaves {
    final semente = carteira.sementePessoal;
    if (semente == null) {
      throw const ErroTroca('Desbloqueie a carteira para usar as trocas.');
    }
    return _chaves ??= ChavesNostr.daSemente(semente);
  }

  String get _chaveArmazenada => 'trocas_${Rede.nome}_${chaves.publica}';

  Future<void> abrir() async {
    try {
      final bruto = await _armazenamento.read(key: _chaveArmazenada);
      if (bruto != null) {
        final j = jsonDecode(bruto) as Map<String, dynamic>;
        for (final t in j['trocas'] as List) {
          final troca = Troca.fromJson(t as Map<String, dynamic>);
          _trocas[troca.id] = troca;
        }
        _mensagensVistas.addAll((j['vistas'] as List).cast<String>());
      }
    } catch (e) {
      debugPrint('Trocas salvas ilegíveis: $e');
    }
    _desde = DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch ~/
        1000;
    notifyListeners();
    _vigia?.cancel();
    _vigia = Timer.periodic(_intervalo, (_) => _buscarMensagens());
    unawaited(_buscarMensagens());
  }

  void fechar() {
    _vigia?.cancel();
    _vigia = null;
  }

  @override
  void dispose() {
    fechar();
    _travasSub?.cancel();
    super.dispose();
  }

  Future<void> _salvar() async {
    final vistas = _mensagensVistas.toList();
    await _armazenamento.write(
        key: _chaveArmazenada,
        value: jsonEncode({
          'trocas': [for (final t in _trocas.values) t.toJson()],
          'vistas': vistas.sublist(vistas.length > 500 ? vistas.length - 500 : 0),
        }));
  }

  // ---------------------------------------------------------------- ofertas

  Future<List<OfertaIris>> ofertas() async {
    final eventos = await RelaysNostr.buscar({
      'kinds': [kindOferta],
      '#y': [plataformaIris],
      '#s': ['pending'],
      'limit': 200,
    });
    final ultimas = <String, OfertaIris>{};
    for (final e in eventos) {
      final o = OfertaIris.doEvento(e, rede: redeNip69);
      if (o == null) continue;
      final k = '${o.autor}:${o.id}';
      if (!ultimas.containsKey(k) || o.criadaEm.isAfter(ultimas[k]!.criadaEm)) {
        ultimas[k] = o;
      }
    }
    return ultimas.values.toList()
      ..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
  }

  Future<int> anunciar({
    required bool vendo,
    required double fiatMin,
    required double fiatMax,
    required List<String> metodos,
    double premio = 0,
    String? instrucao,
  }) async {
    final oferta = OfertaIris(
      id: _novoId(),
      autor: chaves.publica,
      tipo: vendo ? 'sell' : 'buy',
      fiatMin: fiatMin,
      fiatMax: fiatMax,
      metodos: metodos,
      premio: premio,
      rede: redeNip69,
      criadaEm: DateTime.now(),
    );
    if (vendo) {
      if (instrucao == null || instrucao.trim().isEmpty) {
        throw const ErroTroca('Informe a chave Pix ou o boleto para receber.');
      }
      await _armazenamento.write(
          key: 'troca_instrucao_${oferta.id}', value: instrucao.trim());
    }
    final e = EventoNostr.assinar(chaves,
        kind: kindOferta, conteudo: '', tags: oferta.tags());
    return RelaysNostr.publicar(e);
  }

  Future<void> retirarOferta(OfertaIris o) async {
    final tags = [
      for (final t in o.tags())
        if (t[0] == 's') ['s', 'canceled'] else t
    ];
    await RelaysNostr.publicar(
        EventoNostr.assinar(chaves, kind: kindOferta, conteudo: '', tags: tags));
  }

  /// Sats pelo valor em Real, com o prêmio da oferta. Sem cotação, recusa.
  int satsPara(double fiatBrl, OfertaIris o) {
    final base = cotacao.brlToSats(fiatBrl);
    if (base <= 0) {
      throw const ErroTroca('Sem cotação do Real agora — tente em instantes.');
    }
    // Prêmio positivo: quem anuncia venda cobra mais caro (entrega menos sats).
    final fator = o.anuncianteVende ? 1 - o.premio / 100 : 1 + o.premio / 100;
    return (base * fator).round();
  }

  // ---------------------------------------------------------------- trocas

  /// Quem toma a oferta inicia a troca.
  ///
  /// [instrucao]: se quem toma é o vendedor de sats, onde quer receber o Real.
  Future<Troca> aceitar(OfertaIris o, double fiatBrl, {String? instrucao}) async {
    if (o.autor == chaves.publica) {
      throw const ErroTroca('Esta oferta é sua.');
    }
    if (fiatBrl < o.fiatMin || fiatBrl > o.fiatMax) {
      throw ErroTroca('Valor fora da faixa da oferta '
          '(R\$ ${o.fiatMin} a R\$ ${o.fiatMax}).');
    }
    final sats = satsPara(fiatBrl, o);
    final t = Troca(
      id: _novoId(),
      ofertaId: o.id,
      papel: o.anuncianteVende ? PapelTroca.comprador : PapelTroca.vendedor,
      contraparte: o.autor,
      sats: sats,
      fiatBrl: fiatBrl,
    );
    _trocas[t.id] = t;
    await _enviar(t, MensagemTroca(t.id, 'aceitar',
        {'oferta': o.id, 'sats': sats, 'fiat': fiatBrl}));
    if (t.papel == PapelTroca.vendedor) {
      await _enviar(t, t.enviarHash(instrucao ?? ''));
    }
    await _salvar();
    notifyListeners();
    return t;
  }

  /// Vendedor: paga a fatura conferida, travando os sats. Pode ser repetido
  /// pela tela se a primeira tentativa falhar (sem rota, sem rede).
  Future<void> pagarFatura(Troca t) async {
    if (t.papel != PapelTroca.vendedor ||
        t.estado != EstadoTroca.faturaEnviada ||
        t.fatura == null) {
      return;
    }
    await carteira.payLightningInvoice(t.fatura!);
    await _enviar(t, t.avisarTravado());
    await _salvar();
    notifyListeners();
  }

  /// Comprador: depois de pagar o Real.
  Future<void> informarPago(Troca t, String comprovante) async {
    await _enviar(t, t.enviarPago(comprovante));
    await _salvar();
    notifyListeners();
  }

  /// Vendedor: conferiu o Real no banco — libera os sats.
  Future<void> liberar(Troca t) async {
    await _enviar(t, t.revelarSegredo());
    await _salvar();
    notifyListeners();
  }

  Future<void> cancelar(Troca t, String motivo) async {
    final m = t.cancelar(motivo);
    if (t.papel == PapelTroca.comprador && t.hashHex != null) {
      // Devolve na hora o que já estiver travado, sem esperar o prazo.
      try {
        await carteira.recusarTrava(t.hashHex!);
      } catch (_) {}
    }
    await _enviar(t, m);
    await _salvar();
    notifyListeners();
  }

  // ---------------------------------------------------------------- rede

  Future<void> _enviar(Troca t, MensagemTroca m) async {
    final conversa = Nip44.chaveDaConversa(chaves.privada, t.contraparte);
    final e = EventoNostr.assinar(chaves,
        kind: kindMensagemTroca,
        conteudo: Nip44.cifrar(m.paraJson(), conversa),
        tags: [
          ['p', t.contraparte],
          ['t', 'iris-troca'],
        ]);
    final aceitos = await RelaysNostr.publicar(e);
    if (aceitos == 0) {
      throw const ErroTroca('Nenhum relay aceitou a mensagem. Verifique a rede.');
    }
  }

  Future<void> _buscarMensagens() async {
    final ChavesNostr k;
    try {
      k = chaves;
    } catch (_) {
      return;
    }
    final eventos = await RelaysNostr.buscar({
      'kinds': [kindMensagemTroca],
      '#p': [k.publica],
      'since': _desde,
    });
    for (final e in eventos.reversed) {
      if (!_mensagensVistas.add(e.id) || e.tag('t') != 'iris-troca') continue;
      try {
        final texto =
            Nip44.decifrar(e.conteudo, Nip44.chaveDaConversa(k.privada, e.pubkey));
        final m = MensagemTroca.deJson(texto);
        if (m != null) await _aoReceber(e.pubkey, m);
        ultimoErro = null;
      } catch (err) {
        ultimoErro = err.toString();
        debugPrint('Mensagem de troca recusada: $err');
      }
    }
    await _salvar();
    notifyListeners();
  }

  Future<void> _aoReceber(String de, MensagemTroca m) async {
    if (m.acao == 'aceitar') {
      await _aceitaramMinhaOferta(de, m);
      return;
    }
    final t = _trocas[m.trocaId];
    if (t == null || t.contraparte != de || t.encerrada) return;
    switch (m.acao) {
      case 'hash':
        t.receberHash(m);
        final fatura =
            await carteira.criarFaturaDeTroca(hashHex: t.hashHex!, sats: t.sats);
        await _enviar(t, t.enviarFatura(fatura));
      case 'fatura':
        t.receberFatura(m, redeAtual: (n) => Rede.hrpFatura.contains(n));
        await _salvar();
        await pagarFatura(t);
      case 'travado':
        t.receberTravado();
      case 'pago':
        t.receberPago(m);
      case 'segredo':
        final segredo = t.receberSegredo(m);
        await carteira.resgatarTrava(
          hashHex: t.hashHex!,
          segredoHex: segredo,
          amountMsat: _travaMsat[t.hashHex!] ?? t.sats * 1000,
        );
      case 'cancelar':
        t.receberCancelar();
        if (t.papel == PapelTroca.comprador && t.hashHex != null) {
          try {
            await carteira.recusarTrava(t.hashHex!);
          } catch (_) {}
        }
    }
  }

  /// Alguém tomou uma oferta minha: confiro que ela existe e está aberta.
  Future<void> _aceitaramMinhaOferta(String de, MensagemTroca m) async {
    if (_trocas.containsKey(m.trocaId)) return;
    final minhas = (await ofertas()).where(
        (o) => o.autor == chaves.publica && o.id == m.dados['oferta']);
    if (minhas.isEmpty) return;
    final o = minhas.first;
    final fiat = (m.dados['fiat'] as num?)?.toDouble() ?? 0;
    final sats = (m.dados['sats'] as num?)?.toInt() ?? 0;
    if (fiat < o.fiatMin || fiat > o.fiatMax) return;
    // Confere o valor proposto pela cotação deste aparelho (tolerância de 3%).
    final esperado = satsPara(fiat, o);
    if ((sats - esperado).abs() > esperado * 0.03) {
      final t = Troca(
          id: m.trocaId,
          ofertaId: o.id,
          papel: PapelTroca.vendedor,
          contraparte: de,
          sats: sats,
          fiatBrl: fiat);
      await _enviar(t, t.cancelar('valor em sats fora da cotação'));
      return;
    }
    final t = Troca(
      id: m.trocaId,
      ofertaId: o.id,
      papel: o.anuncianteVende ? PapelTroca.vendedor : PapelTroca.comprador,
      contraparte: de,
      sats: sats,
      fiatBrl: fiat,
    );
    _trocas[t.id] = t;
    if (t.papel == PapelTroca.vendedor) {
      final instrucao = await instrucaoDaOferta(o.id);
      if (instrucao == null) {
        await _enviar(t, t.cancelar('oferta sem forma de recebimento'));
        return;
      }
      await _enviar(t, t.enviarHash(instrucao));
    }
  }

  /// Onde o anunciante quer receber o Real numa oferta de venda. Fica só
  /// neste aparelho e vai cifrado a quem tomar a oferta.
  Future<String?> instrucaoDaOferta(String ofertaId) =>
      _armazenamento.read(key: 'troca_instrucao_$ofertaId');

  void _aoChegarTrava(TravaRecebida tr) {
    _travaMsat[tr.hashHex] = tr.amountMsat;
    for (final t in _trocas.values) {
      if (t.hashHex == tr.hashHex) t.travaChegou(tr.hashHex);
    }
    unawaited(_salvar());
    notifyListeners();
  }

  static String _novoId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (DateTime.now().hashCode & 0xffff).toRadixString(36);
}
