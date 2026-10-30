import 'evento.dart';
import 'relays.dart';

/// Ordem P2P pública no padrão NIP-69 (kind 38383), publicada por Mostro,
/// RoboSats, Peach, lnp2pBot e outras plataformas. A Iris só lê: a negociação
/// acontece na plataforma de origem, e ninguém aqui segura dinheiro.
class OrdemP2P {
  final String id;
  final String autor;

  /// `sell`: o anunciante vende bitcoin (quem toma, compra). `buy`: o contrário.
  final String tipo;
  final String moeda;
  final String status;
  final int sats;
  final double? fiatMin;
  final double? fiatMax;
  final List<String> metodos;
  final double premio;
  final String plataforma;
  final String rede;
  final String camada;
  final String? nome;
  final String? origem;
  final DateTime criadaEm;

  const OrdemP2P({
    required this.id,
    required this.autor,
    required this.tipo,
    required this.moeda,
    required this.status,
    required this.sats,
    required this.fiatMin,
    required this.fiatMax,
    required this.metodos,
    required this.premio,
    required this.plataforma,
    required this.rede,
    required this.camada,
    required this.nome,
    required this.origem,
    required this.criadaEm,
  });

  bool get vendeBitcoin => tipo == 'sell';

  static OrdemP2P? doEvento(EventoNostr e) {
    if (e.kind != 38383) return null;
    final tipo = e.tag('k');
    final moeda = e.tag('f');
    final d = e.tag('d');
    if (d == null || moeda == null || (tipo != 'sell' && tipo != 'buy')) {
      return null;
    }
    List<String> todos(String nome) => [
          for (final t in e.tags)
            if (t.isNotEmpty && t[0] == nome) ...t.skip(1)
        ];
    final fa = todos('fa').map(double.tryParse).whereType<double>().toList();
    return OrdemP2P(
      id: d,
      autor: e.pubkey,
      tipo: tipo!,
      moeda: moeda.toUpperCase(),
      status: e.tag('s') ?? 'pending',
      sats: int.tryParse(e.tag('amt') ?? '') ?? 0,
      fiatMin: fa.isEmpty ? null : fa.first,
      fiatMax: fa.isEmpty ? null : fa.last,
      metodos: [
        for (final m in todos('pm')) ...m.split(',').map((s) => s.trim())
      ].where((m) => m.isNotEmpty).toList(),
      premio: double.tryParse(e.tag('premium') ?? '') ?? 0,
      plataforma: e.tag('y') ?? 'desconhecida',
      rede: e.tag('network') ?? 'mainnet',
      camada: e.tag('layer') ?? 'lightning',
      nome: e.tag('name'),
      origem: e.tag('source'),
      criadaEm: DateTime.fromMillisecondsSinceEpoch(e.criadoEm * 1000),
    );
  }
}

class OrdensP2P {
  /// Relays onde Mostro e as outras plataformas costumam publicar.
  static const List<String> relaysExtras = ['wss://relay.mostro.network'];

  static Future<List<OrdemP2P>> abertas({String moeda = 'BRL'}) async {
    final relays = <String>{...await RelaysNostr.emUso(), ...relaysExtras};
    final eventos = await RelaysNostr.buscar({
      'kinds': [38383],
      '#s': ['pending'],
      '#f': [moeda],
      'limit': 200,
    }, relays: relays.toList());
    // Evento endereçável: vale a versão mais nova de cada (autor, d).
    final ultimas = <String, OrdemP2P>{};
    for (final e in eventos) {
      final o = OrdemP2P.doEvento(e);
      if (o == null) continue;
      final chave = '${o.autor}:${o.id}';
      final atual = ultimas[chave];
      if (atual == null || o.criadaEm.isAfter(atual.criadaEm)) {
        ultimas[chave] = o;
      }
    }
    return ultimas.values.where((o) => o.status == 'pending').toList()
      ..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
  }
}
