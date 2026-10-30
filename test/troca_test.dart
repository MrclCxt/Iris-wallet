import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/bolt11.dart';
import 'package:iris_wallet/nostr/chaves.dart';
import 'package:iris_wallet/nostr/evento.dart';
import 'package:iris_wallet/troca/troca.dart';

/// Máquina de estados da troca: a ordem dos passos e, principalmente, as
/// conferências que impedem alguém de receber sem a garantia.
void main() {
  Troca par(PapelTroca p) => Troca(
      id: 't1',
      ofertaId: 'o1',
      papel: p,
      contraparte: 'x',
      sats: 15000,
      fiatBrl: 100);

  Bolt11Data fatura(String hash, int sats) => Bolt11Data(
        network: 'tb',
        amountMsat: sats * 1000,
        description: 'Iris: troca',
        paymentHashHex: hash,
        timestamp: DateTime.now(),
        expiry: const Duration(hours: 1),
      );

  test('caminho feliz de ponta a ponta', () {
    final v = par(PapelTroca.vendedor);
    final c = par(PapelTroca.comprador);

    final mHash = v.enviarHash();
    c.receberHash(mHash);
    expect(c.hashHex, v.hashHex);

    final mFatura = c.enviarFatura('lntb-fatura');
    v.receberFatura(mFatura, decodificar: (_) => fatura(v.hashHex!, 15000));

    v.avisarTravado();
    c.travaChegou(v.hashHex!);
    expect(c.estado, EstadoTroca.travada);

    v.receberPago(c.enviarPago('Pix E2E 123'));
    final segredo = c.receberSegredo(v.revelarSegredo());
    expect(segredo, v.segredoHex);
    expect(v.estado, EstadoTroca.concluida);
    expect(c.estado, EstadoTroca.concluida);
  });

  test('vendedor recusa fatura para outro hash (receber sem trava)', () {
    final v = par(PapelTroca.vendedor)..enviarHash();
    expect(
        () => v.receberFatura(const MensagemTroca('t1', 'fatura', {'fatura': 'x'}),
            decodificar: (_) => fatura('0' * 64, 15000)),
        throwsA(isA<ErroTroca>()));
    expect(v.estado, EstadoTroca.hashEnviado);
  });

  test('vendedor recusa fatura de valor diferente', () {
    final v = par(PapelTroca.vendedor)..enviarHash();
    expect(
        () => v.receberFatura(const MensagemTroca('t1', 'fatura', {'fatura': 'x'}),
            decodificar: (_) => fatura(v.hashHex!, 16000)),
        throwsA(isA<ErroTroca>()));
  });

  test('comprador recusa segredo que não bate com o hash', () {
    final v = par(PapelTroca.vendedor);
    final c = par(PapelTroca.comprador)..receberHash(v.enviarHash());
    c.enviarFatura('x');
    c.travaChegou(v.hashHex!);
    expect(
        () => c.receberSegredo(
            MensagemTroca('t1', 'segredo', {'segredo': 'a' * 64})),
        throwsA(isA<ErroTroca>()));
  });

  test('comprador recusa hash com valor diferente do combinado', () {
    final c = par(PapelTroca.comprador);
    expect(
        () => c.receberHash(
            MensagemTroca('t1', 'hash', {'hash': 'b' * 64, 'sats': 99999})),
        throwsA(isA<ErroTroca>()));
  });

  test('passo fora de ordem ou do lado errado é recusado', () {
    final v = par(PapelTroca.vendedor);
    expect(() => v.revelarSegredo(), throwsA(isA<ErroTroca>()));
    expect(() => v.enviarFatura('x'), throwsA(isA<ErroTroca>()));
  });

  test('vendedor não cancela depois que o comprador diz que pagou', () {
    final v = par(PapelTroca.vendedor);
    final c = par(PapelTroca.comprador)..receberHash(v.enviarHash());
    v.receberFatura(c.enviarFatura('x'),
        decodificar: (_) => fatura(v.hashHex!, 15000));
    v.avisarTravado();
    c.travaChegou(v.hashHex!);
    v.receberPago(c.enviarPago('ok'));
    expect(() => v.cancelar('mudei de ideia'), throwsA(isA<ErroTroca>()));
  });

  test('mensagem vai e volta em JSON', () {
    final m = MensagemTroca('t9', 'hash', {'hash': 'c' * 64, 'sats': 10});
    final volta = MensagemTroca.deJson(m.paraJson())!;
    expect(volta.trocaId, 't9');
    expect(volta.acao, 'hash');
    expect(volta.dados['sats'], 10);
    expect(MensagemTroca.deJson('lixo'), isNull);
  });

  test('oferta só entra no livro se for da Iris e da mesma rede', () {
    final k = ChavesNostr.daPrivada(
        '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
    final oferta = OfertaIris(
      id: 'o1',
      autor: k.publica,
      tipo: 'sell',
      fiatMin: 50,
      fiatMax: 500,
      metodos: ['Pix'],
      premio: 1.5,
      rede: 'testnet4',
      criadaEm: DateTime.now(),
    );
    final e = EventoNostr.assinar(k,
        kind: kindOferta, conteudo: '', tags: oferta.tags());
    final lida = OfertaIris.doEvento(e, rede: 'testnet4')!;
    expect(lida.fiatMin, 50);
    expect(lida.fiatMax, 500);
    expect(lida.metodos, ['Pix']);
    expect(lida.anuncianteVende, isTrue);
    expect(OfertaIris.doEvento(e, rede: 'bitcoin'), isNull);

    final outra = EventoNostr.assinar(k,
        kind: kindOferta,
        conteudo: '',
        tags: [
          for (final t in oferta.tags())
            if (t[0] == 'y') ['y', 'mostro'] else t
        ]);
    expect(OfertaIris.doEvento(outra, rede: 'testnet4'), isNull);
  });
}
