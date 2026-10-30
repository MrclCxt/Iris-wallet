import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/bolt11.dart';
import '../nostr/chaves.dart';
import '../nostr/evento.dart';

/// Protocolo de troca da Iris — ver docs/protocolo-troca.md.
///
/// Vendedor de sats (V) guarda o segredo; comprador (C) cria a fatura pelo
/// hash. Os sats ficam travados até V revelar o segredo, e voltam para V se a
/// troca for desfeita. A Iris nunca segura dinheiro.
const String plataformaIris = 'iris';
const int kindOferta = 38383;
const int kindMensagemTroca = 14;

enum PapelTroca { vendedor, comprador }

enum EstadoTroca {
  aceita,
  hashEnviado,
  faturaEnviada,
  travada,
  realPago,
  concluida,
  cancelada,
  disputa,
}

/// Oferta pública no livro da Iris (formato NIP-69 com `y=iris`).
class OfertaIris {
  final String id;
  final String autor;

  /// `sell`: o anunciante vende sats. `buy`: o anunciante compra sats.
  final String tipo;
  final double fiatMin;
  final double fiatMax;
  final List<String> metodos;
  final double premio;
  final String rede;
  final DateTime criadaEm;

  const OfertaIris({
    required this.id,
    required this.autor,
    required this.tipo,
    required this.fiatMin,
    required this.fiatMax,
    required this.metodos,
    required this.premio,
    required this.rede,
    required this.criadaEm,
  });

  bool get anuncianteVende => tipo == 'sell';

  List<List<String>> tags() => [
        ['d', id],
        ['k', tipo],
        ['f', 'BRL'],
        ['s', 'pending'],
        ['amt', '0'],
        ['fa', _num(fiatMin), _num(fiatMax)],
        ['pm', ...metodos],
        ['premium', _num(premio)],
        ['network', rede],
        ['layer', 'lightning'],
        ['y', plataformaIris],
        ['z', 'order'],
      ];

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Só aceita ofertas da própria Iris e da rede pedida.
  static OfertaIris? doEvento(EventoNostr e, {required String rede}) {
    if (e.kind != kindOferta || e.tag('y') != plataformaIris) return null;
    if ((e.tag('network') ?? '') != rede || e.tag('s') != 'pending') return null;
    final tipo = e.tag('k');
    final id = e.tag('d');
    if (id == null || (tipo != 'sell' && tipo != 'buy') || e.tag('f') != 'BRL') {
      return null;
    }
    final fa = [
      for (final t in e.tags)
        if (t.isNotEmpty && t[0] == 'fa') ...t.skip(1)
    ].map(double.tryParse).whereType<double>().toList();
    if (fa.isEmpty || fa.first <= 0) return null;
    return OfertaIris(
      id: id,
      autor: e.pubkey,
      tipo: tipo!,
      fiatMin: fa.first,
      fiatMax: fa.last,
      metodos: [
        for (final t in e.tags)
          if (t.isNotEmpty && t[0] == 'pm') ...t.skip(1)
      ],
      premio: double.tryParse(e.tag('premium') ?? '') ?? 0,
      rede: rede,
      criadaEm: DateTime.fromMillisecondsSinceEpoch(e.criadoEm * 1000),
    );
  }
}

/// Passo da troca, trocado cifrado (NIP-44) entre as duas partes.
class MensagemTroca {
  final String trocaId;
  final String acao;
  final Map<String, dynamic> dados;

  const MensagemTroca(this.trocaId, this.acao, [this.dados = const {}]);

  String paraJson() => jsonEncode({'troca': trocaId, 'acao': acao, ...dados});

  static MensagemTroca? deJson(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      final troca = j.remove('troca');
      final acao = j.remove('acao');
      if (troca is! String || acao is! String) return null;
      return MensagemTroca(troca, acao, j);
    } catch (_) {
      return null;
    }
  }
}

class ErroTroca implements Exception {
  final String mensagem;
  const ErroTroca(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Estado de uma troca do ponto de vista deste aparelho.
class Troca {
  final String id;
  final String ofertaId;
  final PapelTroca papel;
  final String contraparte;
  final int sats;
  final double fiatBrl;
  EstadoTroca estado;
  String? hashHex;
  String? segredoHex;
  String? fatura;
  String? comprovante;
  final DateTime criadaEm;

  Troca({
    required this.id,
    required this.ofertaId,
    required this.papel,
    required this.contraparte,
    required this.sats,
    required this.fiatBrl,
    this.estado = EstadoTroca.aceita,
    this.hashHex,
    this.segredoHex,
    this.fatura,
    this.comprovante,
    DateTime? criadaEm,
  }) : criadaEm = criadaEm ?? DateTime.now();

  bool get encerrada =>
      estado == EstadoTroca.concluida || estado == EstadoTroca.cancelada;

  void _exigir(PapelTroca p, Set<EstadoTroca> estados, String passo) {
    if (papel != p) throw ErroTroca('Passo "$passo" não cabe a este lado.');
    if (!estados.contains(estado)) {
      throw ErroTroca('Passo "$passo" fora de ordem (troca em ${estado.name}).');
    }
  }

  /// V: gera o segredo e manda só o hash.
  MensagemTroca enviarHash() {
    _exigir(PapelTroca.vendedor, {EstadoTroca.aceita}, 'hash');
    final r = Random.secure();
    final segredo = List<int>.generate(32, (_) => r.nextInt(256));
    segredoHex = paraHex(segredo);
    hashHex = sha256.convert(segredo).toString();
    estado = EstadoTroca.hashEnviado;
    return MensagemTroca(id, 'hash', {'hash': hashHex, 'sats': sats});
  }

  /// C: recebe o hash; o próximo passo é criar a fatura para ele.
  void receberHash(MensagemTroca m) {
    _exigir(PapelTroca.comprador, {EstadoTroca.aceita}, 'hash');
    final h = m.dados['hash'];
    if (h is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) {
      throw const ErroTroca('Hash inválido.');
    }
    if (m.dados['sats'] != sats) {
      throw const ErroTroca('Valor em sats diferente do combinado.');
    }
    hashHex = h;
    estado = EstadoTroca.hashEnviado;
  }

  /// C: manda a fatura criada pelo nó para o hash recebido.
  MensagemTroca enviarFatura(String invoice) {
    _exigir(PapelTroca.comprador, {EstadoTroca.hashEnviado}, 'fatura');
    fatura = invoice;
    estado = EstadoTroca.faturaEnviada;
    return MensagemTroca(id, 'fatura', {'fatura': invoice});
  }

  /// V: confere a fatura ANTES de pagar. Se o hash não for o do segredo de V,
  /// C poderia receber sem trava — por isso recusa qualquer diferença.
  void receberFatura(MensagemTroca m,
      {bool Function(String)? redeAtual,
      Bolt11Data Function(String) decodificar = Bolt11.decode}) {
    _exigir(PapelTroca.vendedor, {EstadoTroca.hashEnviado}, 'fatura');
    final inv = m.dados['fatura'];
    if (inv is! String) throw const ErroTroca('Fatura ausente.');
    final Bolt11Data d;
    try {
      d = decodificar(inv);
    } catch (_) {
      throw const ErroTroca('Fatura ilegível.');
    }
    if (d.paymentHashHex != hashHex) {
      throw const ErroTroca(
          'A fatura não é para o hash desta troca — não pague.');
    }
    if (d.amountSats != sats) {
      throw const ErroTroca('A fatura cobra valor diferente do combinado.');
    }
    if (redeAtual != null && !redeAtual(d.network)) {
      throw const ErroTroca('Fatura de outra rede.');
    }
    if (d.isExpired) throw const ErroTroca('Fatura expirada.');
    fatura = inv;
    estado = EstadoTroca.faturaEnviada;
  }

  /// V: pagou a fatura; os sats estão travados.
  MensagemTroca avisarTravado() {
    _exigir(PapelTroca.vendedor, {EstadoTroca.faturaEnviada}, 'travado');
    estado = EstadoTroca.travada;
    return MensagemTroca(id, 'travado');
  }

  /// C: o próprio nó viu o pagamento travado (PaymentClaimable).
  void travaChegou(String hash) {
    if (papel != PapelTroca.comprador || hash != hashHex) return;
    if (estado == EstadoTroca.faturaEnviada) estado = EstadoTroca.travada;
  }

  /// V: recebeu o aviso de C de que o pagamento travado chegou.
  void receberTravado() {
    if (papel == PapelTroca.vendedor && estado == EstadoTroca.faturaEnviada) {
      estado = EstadoTroca.travada;
    }
  }

  /// C: pagou o Real e manda o comprovante.
  MensagemTroca enviarPago(String comprovanteTexto) {
    _exigir(PapelTroca.comprador, {EstadoTroca.travada}, 'pago');
    comprovante = comprovanteTexto;
    estado = EstadoTroca.realPago;
    return MensagemTroca(id, 'pago', {'comprovante': comprovanteTexto});
  }

  void receberPago(MensagemTroca m) {
    _exigir(PapelTroca.vendedor, {EstadoTroca.travada}, 'pago');
    comprovante = m.dados['comprovante']?.toString() ?? '';
    estado = EstadoTroca.realPago;
  }

  /// V: conferiu o Real no banco e libera os sats revelando o segredo.
  MensagemTroca revelarSegredo() {
    _exigir(PapelTroca.vendedor, {EstadoTroca.realPago, EstadoTroca.travada},
        'segredo');
    estado = EstadoTroca.concluida;
    return MensagemTroca(id, 'segredo', {'segredo': segredoHex});
  }

  /// C: recebe o segredo; só aceita se bater com o hash.
  String receberSegredo(MensagemTroca m) {
    _exigir(PapelTroca.comprador,
        {EstadoTroca.travada, EstadoTroca.realPago}, 'segredo');
    final s = m.dados['segredo'];
    if (s is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ||
        sha256.convert(deHex(s)).toString() != hashHex) {
      throw const ErroTroca('Segredo não corresponde ao hash da troca.');
    }
    segredoHex = s;
    estado = EstadoTroca.concluida;
    return s;
  }

  MensagemTroca cancelar(String motivo) {
    if (estado == EstadoTroca.realPago && papel == PapelTroca.vendedor) {
      throw const ErroTroca(
          'O comprador diz que já pagou: confira o banco ou abra disputa.');
    }
    estado = EstadoTroca.cancelada;
    return MensagemTroca(id, 'cancelar', {'motivo': motivo});
  }

  void receberCancelar() {
    if (!encerrada) estado = EstadoTroca.cancelada;
  }
}
