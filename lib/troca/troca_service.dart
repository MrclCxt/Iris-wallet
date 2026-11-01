import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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

String sha256Hex(String hex) => sha256.convert(deHex(hex)).toString();

/// Caso recebido por quem é árbitro: o segredo cifrado pelo vendedor e as
/// alegações de cada lado se houver disputa.
class CasoArbitragem {
  final String trocaId;
  final String hash;
  final String segredo;
  final int sats;
  final double fiat;
  final String vendedor;
  final String comprador;
  final Map<String, String> alegacoes = {};
  String? decisao;

  CasoArbitragem({
    required this.trocaId,
    required this.hash,
    required this.segredo,
    required this.sats,
    required this.fiat,
    required this.vendedor,
    required this.comprador,
  });

  bool get emDisputa => alegacoes.isNotEmpty && decisao == null;

  Map<String, dynamic> toJson() => {
        'troca': trocaId,
        'hash': hash,
        'segredo': segredo,
        'sats': sats,
        'fiat': fiat,
        'vendedor': vendedor,
        'comprador': comprador,
        'alegacoes': alegacoes,
        'decisao': decisao,
      };

  factory CasoArbitragem.fromJson(Map<String, dynamic> j) => CasoArbitragem(
        trocaId: j['troca'] as String,
        hash: j['hash'] as String,
        segredo: j['segredo'] as String,
        sats: (j['sats'] as num).toInt(),
        fiat: (j['fiat'] as num).toDouble(),
        vendedor: j['vendedor'] as String,
        comprador: j['comprador'] as String,
      )
        ..alegacoes.addAll(
            ((j['alegacoes'] as Map?) ?? const {}).cast<String, String>())
        ..decisao = j['decisao'] as String?;
}

/// O que a troca precisa da carteira. No app é o [WalletService]; nos testes
/// de ponta a ponta, um nó da regtest.
abstract class CarteiraTroca {
  String? get sementePessoal;
  Stream<TravaRecebida> get travasRecebidas;
  Future<String> criarFaturaDeTroca({required String hashHex, required int sats});
  Future<void> pagarFatura(String fatura);
  Future<void> resgatarTrava(
      {required String hashHex, required String segredoHex, required int amountMsat});
  Future<void> recusarTrava(String hashHex);
}

class _CarteiraDoApp implements CarteiraTroca {
  final WalletService w;
  _CarteiraDoApp(this.w);
  @override
  String? get sementePessoal => w.sementePessoal;
  @override
  Stream<TravaRecebida> get travasRecebidas => w.travasRecebidas;
  @override
  Future<String> criarFaturaDeTroca({required String hashHex, required int sats}) =>
      w.criarFaturaDeTroca(hashHex: hashHex, sats: sats);
  @override
  Future<void> pagarFatura(String fatura) => w.payLightningInvoice(fatura);
  @override
  Future<void> resgatarTrava(
          {required String hashHex,
          required String segredoHex,
          required int amountMsat}) =>
      w.resgatarTrava(
          hashHex: hashHex, segredoHex: segredoHex, amountMsat: amountMsat);
  @override
  Future<void> recusarTrava(String hashHex) => w.recusarTrava(hashHex);
}

/// Onde a troca guarda segredo e estado. No app, o armazenamento seguro.
abstract class CofreLocal {
  Future<String?> ler(String chave);
  Future<void> gravar(String chave, String valor);
  Future<void> apagar(String chave);
}

class _CofreSeguro implements CofreLocal {
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> ler(String chave) => _s.read(key: chave);
  @override
  Future<void> gravar(String chave, String valor) => _s.write(key: chave, value: valor);
  @override
  Future<void> apagar(String chave) => _s.delete(key: chave);
}

/// Liga o protocolo de troca à rede Nostr e à carteira. Tudo roda no aparelho:
/// não há servidor da Iris. As mensagens só são buscadas com a tela de trocas
/// aberta (sem serviço em segundo plano, sem push de terceiros).
class TrocaService extends ChangeNotifier {
  final CarteiraTroca carteira;
  final int Function(double brl) _brlParaSats;
  final CofreLocal _armazenamento;

  /// Relays fixos (testes); sem isso, os do usuário e os padrão.
  final List<String>? relays;

  /// Prefixos de fatura aceitos (padrão: os da rede do build).
  final List<String> prefixosFatura;

  TrocaService({
    required WalletService carteira,
    required ExchangeRateService cotacao,
  }) : this.comDependencias(
          carteira: _CarteiraDoApp(carteira),
          brlParaSats: cotacao.brlToSats,
          cofre: _CofreSeguro(),
        );

  TrocaService.comDependencias({
    required this.carteira,
    required int Function(double brl) brlParaSats,
    required CofreLocal cofre,
    this.relays,
    this.prefixosFatura = Rede.hrpFatura,
  })  : _brlParaSats = brlParaSats,
        _armazenamento = cofre {
    _travasSub = carteira.travasRecebidas.listen(_aoChegarTrava);
  }
  static const Duration _intervaloTela = Duration(seconds: 6);
  static const Duration _intervaloFundo = Duration(seconds: 30);

  /// Avisa cada passo novo de uma troca (no app: notificação local).
  void Function(Troca t, String texto)? aoMudar;
  bool _telaAberta = false;
  String? _abertoPara;
  DateTime? _ultimoAnuncio;

  StreamSubscription<TravaRecebida>? _travasSub;
  Timer? _vigia;
  ChavesNostr? _chaves;
  int _desde = 0;
  final Map<String, Troca> _trocas = {};
  final Map<String, CasoArbitragem> _casos = {};
  final Map<String, int> _travaMsat = {};
  final Set<String> _mensagensVistas = {};
  String? ultimoErro;

  List<CasoArbitragem> get casos => _casos.values.toList();

  List<Troca> get trocas =>
      _trocas.values.toList()..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));

  static String get redeNip69 => Rede.principal
      ? 'mainnet'
      : (Rede.ehSignet ? 'signet' : 'testnet4');

  ChavesNostr get chaves {
    final semente = carteira.sementePessoal;
    if (semente == null) {
      throw const ErroTroca('Desbloqueie a carteira para usar as trocas.');
    }
    return _chaves ??= ChavesNostr.daSemente(semente);
  }

  String get _chaveArmazenada => 'trocas_${Rede.nome}_${chaves.publica}';

  /// Chamado sempre que a carteira muda: começa a acompanhar as trocas da
  /// semente desbloqueada, ou para tudo quando a carteira bloqueia.
  Future<void> acompanhar() async {
    final semente = carteira.sementePessoal;
    if (semente == null) {
      fechar();
      _chaves = null;
      _abertoPara = null;
      _trocas.clear();
      _casos.clear();
      return;
    }
    if (_abertoPara == semente) return;
    _chaves = null;
    _trocas.clear();
    _casos.clear();
    _abertoPara = semente;
    await abrir();
  }

  /// A tela de trocas aberta acelera a busca de mensagens.
  void telaAberta(bool aberta) {
    _telaAberta = aberta;
    _reprogramar();
    if (aberta) unawaited(_buscarMensagens());
  }

  bool get _temAtividade =>
      _trocas.values.any((t) => !t.encerrada) ||
      _casos.values.any((c) => c.decisao == null) ||
      (_ultimoAnuncio != null &&
          DateTime.now().difference(_ultimoAnuncio!) < const Duration(hours: 24));

  void _reprogramar() {
    _vigia?.cancel();
    _vigia = null;
    if (_abertoPara == null && carteira.sementePessoal == null) return;
    if (!_telaAberta && !_temAtividade) return;
    _vigia = Timer.periodic(
        _telaAberta ? _intervaloTela : _intervaloFundo, (_) => _buscarMensagens());
  }

  Future<void> abrir() async {
    try {
      final bruto = await _armazenamento.ler(_chaveArmazenada);
      if (bruto != null) {
        final j = jsonDecode(bruto) as Map<String, dynamic>;
        for (final t in j['trocas'] as List) {
          final troca = Troca.fromJson(t as Map<String, dynamic>);
          _trocas[troca.id] = troca;
        }
        _mensagensVistas.addAll((j['vistas'] as List).cast<String>());
        final ua = j['ultimo_anuncio'];
        if (ua is int) _ultimoAnuncio = DateTime.fromMillisecondsSinceEpoch(ua);
        for (final c in (j['casos'] as List? ?? const [])) {
          final caso = CasoArbitragem.fromJson(c as Map<String, dynamic>);
          _casos[caso.trocaId] = caso;
        }
      }
    } catch (e) {
      debugPrint('Trocas salvas ilegíveis: $e');
    }
    _desde = DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch ~/
        1000;
    notifyListeners();
    _reprogramar();
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
    await _armazenamento.gravar(_chaveArmazenada, jsonEncode({
          'trocas': [for (final t in _trocas.values) t.toJson()],
          'vistas': vistas.sublist(vistas.length > 500 ? vistas.length - 500 : 0),
          'casos': [for (final c in _casos.values) c.toJson()],
          if (_ultimoAnuncio != null)
            'ultimo_anuncio': _ultimoAnuncio!.millisecondsSinceEpoch,
        }));
  }

  // ---------------------------------------------------------------- ofertas

  Future<List<OfertaIris>> ofertas() async {
    final eventos = await RelaysNostr.buscar({
      'kinds': [kindOferta],
      '#y': [plataformaIris],
      '#s': ['pending'],
      'limit': 200,
    }, relays: relays);
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
    String? arbitro,
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
      arbitro: arbitro ?? await arbitroPadrao(),
    );
    if (vendo) {
      if (instrucao == null || instrucao.trim().isEmpty) {
        throw const ErroTroca('Informe a chave Pix ou o boleto para receber.');
      }
      await _armazenamento.gravar('troca_instrucao_${oferta.id}', instrucao.trim());
    }
    final e = EventoNostr.assinar(chaves,
        kind: kindOferta, conteudo: '', tags: oferta.tags());
    _ultimoAnuncio = DateTime.now();
    unawaited(_salvar());
    _reprogramar();
    return RelaysNostr.publicar(e, relays: relays);
  }

  /// Pagar conta: vira uma venda de sats no valor exato da conta. Quem tomar
  /// paga o boleto/Pix (o código vai cifrado só para essa pessoa) e recebe os
  /// sats travados, liberados quando a conta aparecer paga.
  Future<int> pedirPagamentoDeConta(
      {required String codigo, required double valorBrl}) {
    if (valorBrl <= 0) throw const ErroTroca('Informe o valor da conta.');
    return anunciar(
      vendo: true,
      fiatMin: valorBrl,
      fiatMax: valorBrl,
      metodos: const ['Conta'],
      instrucao: codigo,
    );
  }

  Future<void> retirarOferta(OfertaIris o) async {
    final tags = [
      for (final t in o.tags())
        if (t[0] == 's') ['s', 'canceled'] else t
    ];
    await RelaysNostr.publicar(
        EventoNostr.assinar(chaves, kind: kindOferta, conteudo: '', tags: tags),
        relays: relays);
  }

  /// Sats pelo valor em Real, com o prêmio da oferta. Sem cotação, recusa.
  int satsPara(double fiatBrl, OfertaIris o) {
    final base = _brlParaSats(fiatBrl);
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
      arbitro: o.arbitro,
    );
    _trocas[t.id] = t;
    await _enviar(t, MensagemTroca(t.id, 'aceitar',
        {'oferta': o.id, 'sats': sats, 'fiat': fiatBrl}));
    if (t.papel == PapelTroca.vendedor) {
      await _enviarHash(t, instrucao ?? '');
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
    await carteira.pagarFatura(t.fatura!);
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

  /// V: manda o hash ao comprador e, se houver árbitro, o segredo cifrado
  /// para ele — antes de qualquer sat travar.
  Future<void> _enviarHash(Troca t, String instrucao) async {
    final m = t.enviarHash(instrucao);
    final cofre = t.cofreParaArbitro(vendedor: chaves.publica);
    if (cofre != null) await _enviarPara(t.arbitro!, cofre);
    await _enviar(t, m);
  }

  Future<void> abrirDisputa(Troca t, String motivo) async {
    final m = t.abrirDisputa(motivo);
    await _enviarPara(t.arbitro!, m);
    await _enviar(t, m);
    await _salvar();
    notifyListeners();
  }

  /// Árbitro: decide a favor do comprador (revela o segredo a ele) ou do
  /// vendedor (pede ao comprador que devolva; se ele não devolver, o prazo da
  /// trava devolve sozinho).
  Future<void> decidir(CasoArbitragem c, {required bool favorComprador}) async {
    if (favorComprador) {
      await _enviarPara(c.comprador,
          MensagemTroca(c.trocaId, 'segredo', {'segredo': c.segredo}));
    } else {
      await _enviarPara(c.comprador, MensagemTroca(c.trocaId, 'devolver'));
    }
    await _enviarPara(c.vendedor, MensagemTroca(c.trocaId, 'decisao',
        {'favor': favorComprador ? 'comprador' : 'vendedor'}));
    c.decisao = favorComprador ? 'comprador' : 'vendedor';
    await _salvar();
    notifyListeners();
  }

  Future<void> _enviar(Troca t, MensagemTroca m) => _enviarPara(t.contraparte, m);

  Future<void> _enviarPara(String destino, MensagemTroca m) async {
    final conversa = Nip44.chaveDaConversa(chaves.privada, destino);
    final e = EventoNostr.assinar(chaves,
        kind: kindMensagemTroca,
        conteudo: Nip44.cifrar(m.paraJson(), conversa),
        tags: [
          ['p', destino],
          ['t', 'iris-troca'],
        ]);
    final aceitos = await RelaysNostr.publicar(e, relays: relays);
    if (aceitos == 0) {
      throw const ErroTroca('Nenhum relay aceitou a mensagem. Verifique a rede.');
    }
  }

  /// Busca e processa mensagens agora (a vigia faz isso a cada poucos segundos).
  Future<void> sincronizar() => _buscarMensagens();

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
    }, relays: relays);
    final antes = {for (final t in _trocas.values) t.id: t.estado};
    final casosAntes = {
      for (final c in _casos.values) c.trocaId: c.alegacoes.length
    };
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
    for (final t in _trocas.values) {
      if (antes[t.id] != t.estado) aoMudar?.call(t, textoDoEstado(t));
    }
    for (final c in _casos.values) {
      if ((casosAntes[c.trocaId] ?? 0) < c.alegacoes.length) {
        aoMudar?.call(
            Troca(
                id: c.trocaId,
                ofertaId: '',
                papel: PapelTroca.comprador,
                contraparte: c.comprador,
                sats: c.sats,
                fiatBrl: c.fiat,
                estado: EstadoTroca.disputa),
            'Nova disputa para você arbitrar');
      }
    }
    _reprogramar();
    await _salvar();
    notifyListeners();
  }

  /// Texto curto do passo atual, do ponto de vista deste aparelho.
  static String textoDoEstado(Troca t) {
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
      EstadoTroca.concluida => 'Troca concluída',
      EstadoTroca.cancelada => 'Troca cancelada',
      EstadoTroca.disputa => 'Em disputa — o árbitro decide antes do prazo da trava',
    };
  }

  Future<void> _aoReceber(String de, MensagemTroca m) async {
    if (m.acao == 'aceitar') {
      await _aceitaramMinhaOferta(de, m);
      return;
    }
    if (m.acao == 'cofre') {
      _receberCofre(de, m);
      return;
    }
    final caso = _casos[m.trocaId];
    if (m.acao == 'disputa' &&
        caso != null &&
        (de == caso.vendedor || de == caso.comprador)) {
      final comprovante = m.dados['comprovante'];
      caso.alegacoes[de == caso.vendedor ? 'vendedor' : 'comprador'] =
          '${m.dados['motivo'] ?? ''}'
          '${comprovante != null ? ' — comprovante: $comprovante' : ''}';
      return;
    }
    final t = _trocas[m.trocaId];
    if (t == null || t.encerrada) return;
    if (de == t.arbitro && de != t.contraparte) {
      await _decisaoDoArbitro(t, m);
      return;
    }
    if (t.contraparte != de) return;
    switch (m.acao) {
      case 'disputa':
        t.receberDisputa(m);
      case 'hash':
        t.receberHash(m);
        final fatura =
            await carteira.criarFaturaDeTroca(hashHex: t.hashHex!, sats: t.sats);
        await _enviar(t, t.enviarFatura(fatura));
      case 'fatura':
        t.receberFatura(m, redeAtual: prefixosFatura.contains);
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

  void _receberCofre(String de, MensagemTroca m) {
    final d = m.dados;
    if (_casos.containsKey(m.trocaId) || d['vendedor'] != de) return;
    final segredo = d['segredo'];
    final hash = d['hash'];
    if (segredo is! String ||
        hash is! String ||
        sha256Hex(segredo) != hash ||
        d['comprador'] is! String) {
      return;
    }
    _casos[m.trocaId] = CasoArbitragem(
      trocaId: m.trocaId,
      hash: hash,
      segredo: segredo,
      sats: (d['sats'] as num?)?.toInt() ?? 0,
      fiat: (d['fiat'] as num?)?.toDouble() ?? 0,
      vendedor: de,
      comprador: d['comprador'] as String,
    );
  }

  Future<void> _decisaoDoArbitro(Troca t, MensagemTroca m) async {
    switch (m.acao) {
      case 'segredo':
        if (t.papel != PapelTroca.comprador) return;
        final segredo = t.receberSegredo(m);
        await carteira.resgatarTrava(
          hashHex: t.hashHex!,
          segredoHex: segredo,
          amountMsat: _travaMsat[t.hashHex!] ?? t.sats * 1000,
        );
      case 'devolver':
        if (t.papel != PapelTroca.comprador) return;
        try {
          await carteira.recusarTrava(t.hashHex!);
        } catch (_) {}
        t.estado = EstadoTroca.cancelada;
      case 'decisao':
        t.estado = m.dados['favor'] == 'comprador'
            ? EstadoTroca.concluida
            : EstadoTroca.cancelada;
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
      arbitro: o.arbitro,
    );
    _trocas[t.id] = t;
    if (t.papel == PapelTroca.vendedor) {
      final instrucao = await instrucaoDaOferta(o.id);
      if (instrucao == null) {
        await _enviar(t, t.cancelar('oferta sem forma de recebimento'));
        return;
      }
      await _enviarHash(t, instrucao);
    }
  }

  /// Árbitro que o usuário escolheu para as próprias ofertas (chave Nostr hex).
  Future<String?> arbitroPadrao() => _armazenamento.ler('troca_arbitro');

  Future<void> definirArbitroPadrao(String? chave) async {
    if (chave == null || chave.trim().isEmpty) {
      await _armazenamento.apagar('troca_arbitro');
      return;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(chave.trim())) {
      throw const ErroTroca('Chave do árbitro inválida (64 caracteres hex).');
    }
    await _armazenamento.gravar('troca_arbitro', chave.trim());
  }

  /// Onde o anunciante quer receber o Real numa oferta de venda. Fica só
  /// neste aparelho e vai cifrado a quem tomar a oferta.
  Future<String?> instrucaoDaOferta(String ofertaId) =>
      _armazenamento.ler('troca_instrucao_$ofertaId');

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
