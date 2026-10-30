import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/nostr/chaves.dart';
import 'package:iris_wallet/services/node_backend.dart';
import 'package:iris_wallet/services/wallet_service.dart';
import 'package:iris_wallet/troca/troca.dart';
import 'package:iris_wallet/troca/troca_service.dart';

import '../apoio/relay_local.dart';

/// Troca P2P de ponta a ponta com o código real do app: dois TrocaService
/// conversando por um relay local, cada um com um nó Lightning de verdade
/// (iris-noded na regtest). Roda dentro de scripts/regtest_canal.py, que
/// define as variáveis abaixo; sem elas, o teste é pulado.
///
/// IRIS_DAEMON_A / IRIS_DAEMON_B: URL REST dos nós (A tem o canal com saldo).
/// IRIS_SEMENTE_A / IRIS_SEMENTE_B: as sementes, para a identidade Nostr.
void main() {
  final env = Platform.environment;
  final pronto = env['IRIS_DAEMON_A'] != null && env['IRIS_DAEMON_B'] != null;

  test('troca com garantia e disputa decidida pelo árbitro', () async {
    final relay = await RelayLocal.iniciar();
    final a = _CarteiraDaemon(
        env['IRIS_DAEMON_A']!, env['IRIS_SEMENTE_A']!, env['IRIS_TOKEN_A']);
    final b = _CarteiraDaemon(
        env['IRIS_DAEMON_B']!, env['IRIS_SEMENTE_B']!, env['IRIS_TOKEN_B']);
    final arbitro = _CarteiraDaemon.soChave(
        'what bleak badge arrange retreat wolf trade produce cricket blur '
        'garlic valid proud rude strong choose busy staff weather area salt '
        'hollow arm fade');
    TrocaService servico(CarteiraTroca c) => TrocaService.comDependencias(
          carteira: c,
          brlParaSats: (brl) => (brl * 150).round(), // R$1 = 150 sats
          cofre: _CofreMemoria(),
          relays: [relay.url],
          prefixosFatura: const ['bcrt'],
        );
    final va = servico(a);
    final vb = servico(b);
    final varb = servico(arbitro);

    Future<void> ate(String oQue, bool Function() cond) async {
      for (var i = 0; i < 60; i++) {
        await va.sincronizar();
        await vb.sincronizar();
        await varb.sincronizar();
        if (cond()) return;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      fail('tempo esgotado: $oQue (A: ${va.trocas.map((t) => t.estado)}, '
          'B: ${vb.trocas.map((t) => t.estado)}, erro B: ${vb.ultimoErro}, '
          'erro A: ${va.ultimoErro})');
    }

    try {
      // 1) Caminho feliz: A vende 100 reais em sats, B compra.
      final saldoB0 = await b.lightning();
      await va.anunciar(
          vendo: true, fiatMin: 100, fiatMax: 100, metodos: ['Pix'],
          instrucao: 'pix-do-a@exemplo');
      final oferta = (await vb.ofertas()).single;
      expect(oferta.anuncianteVende, isTrue);
      await vb.aceitar(oferta, 100);

      await ate('sats travados no nó de B',
          () => vb.trocas.single.estado == EstadoTroca.travada);
      expect(vb.trocas.single.instrucaoPagamento, 'pix-do-a@exemplo');
      expect(await b.lightning(), saldoB0, reason: 'B não pode receber antes');

      await vb.informarPago(vb.trocas.single, 'E2E-123');
      await ate('A ver o pagamento',
          () => va.trocas.single.estado == EstadoTroca.realPago);
      await va.liberar(va.trocas.single);
      await ate('B resgatar',
          () => vb.trocas.single.estado == EstadoTroca.concluida);
      await _esperarSaldo(b, saldoB0 + 15000);

      // 2) Disputa: A anuncia com árbitro e some depois do Pix.
      await va.anunciar(
          vendo: true, fiatMin: 50, fiatMax: 50, metodos: ['Pix'],
          instrucao: 'pix-do-a@exemplo', arbitro: arbitro.chaves.publica);
      final comArb = (await vb.ofertas())
          .firstWhere((o) => o.arbitro == arbitro.chaves.publica);
      final saldoB1 = await b.lightning();
      final troca2 = await vb.aceitar(comArb, 50);
      await ate('segunda troca travada', () => troca2.estado == EstadoTroca.travada);
      expect(varb.casos.map((c) => c.trocaId), contains(troca2.id),
          reason: 'o árbitro recebeu o segredo cifrado');
      await vb.informarPago(troca2, 'E2E-456');
      await vb.abrirDisputa(troca2, 'paguei e o vendedor sumiu');
      await ate('árbitro ver a disputa',
          () => varb.casos.any((c) => c.trocaId == troca2.id && c.emDisputa));
      await varb.decidir(varb.casos.firstWhere((c) => c.trocaId == troca2.id),
          favorComprador: true);
      await ate('B resgatar pela decisão do árbitro',
          () => troca2.estado == EstadoTroca.concluida);
      await _esperarSaldo(b, saldoB1 + 7500);
    } finally {
      va.dispose();
      vb.dispose();
      varb.dispose();
      a.parar();
      b.parar();
      await relay.parar();
    }
  }, skip: pronto ? false : 'roda só dentro de scripts/regtest_canal.py',
      timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _esperarSaldo(_CarteiraDaemon c, int minimo) async {
  for (var i = 0; i < 60; i++) {
    if (await c.lightning() >= minimo) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail('saldo Lightning não chegou a $minimo (está em ${await c.lightning()})');
}

class _CofreMemoria implements CofreLocal {
  final _m = <String, String>{};
  @override
  Future<String?> ler(String chave) async => _m[chave];
  @override
  Future<void> gravar(String chave, String valor) async => _m[chave] = valor;
  @override
  Future<void> apagar(String chave) async => _m.remove(chave);
}

/// Carteira de troca apoiada num iris-noded, pelo mesmo RemoteNodeApi que o
/// app usa no modo daemon.
class _CarteiraDaemon implements CarteiraTroca {
  final RemoteNodeApi? _api;
  final String _semente;
  final _travas = StreamController<TravaRecebida>.broadcast();
  Timer? _eventos;
  late final ChavesNostr chaves = ChavesNostr.daSemente(_semente);

  _CarteiraDaemon(String url, this._semente, String? token)
      : _api = RemoteNodeApi(url, token: token) {
    _eventos = Timer.periodic(const Duration(milliseconds: 500), (_) => _lerEventos());
  }

  _CarteiraDaemon.soChave(this._semente) : _api = null;

  bool _lendo = false;
  Future<void> _lerEventos() async {
    if (_lendo) return;
    _lendo = true;
    try {
      while (true) {
        final e = await _api!.nextEvent();
        if (e == null) break;
        await _api!.eventHandled();
        if (e.type == 'payment_claimable') {
          _travas.add(TravaRecebida(
              hashHex: e.paymentHashHex,
              amountMsat: e.amountMsat,
              prazoBloco: e.claimDeadline));
        }
      }
    } catch (_) {
    } finally {
      _lendo = false;
    }
  }

  Future<int> lightning() async => (await _api!.balances()).lightningSats;

  void parar() => _eventos?.cancel();

  @override
  String? get sementePessoal => _semente;
  @override
  Stream<TravaRecebida> get travasRecebidas => _travas.stream;
  @override
  Future<String> criarFaturaDeTroca({required String hashHex, required int sats}) =>
      _api!.criarFaturaComHash(
          hashHex: hashHex,
          amountMsat: sats * 1000,
          description: 'Iris: troca',
          expirySecs: 3600);
  @override
  Future<void> pagarFatura(String fatura) => _api!.payInvoice(fatura);
  @override
  Future<void> resgatarTrava(
          {required String hashHex,
          required String segredoHex,
          required int amountMsat}) =>
      _api!.resgatarTrava(
          hashHex: hashHex, segredoHex: segredoHex, amountMsat: amountMsat);
  @override
  Future<void> recusarTrava(String hashHex) => _api!.recusarTrava(hashHex);
}
