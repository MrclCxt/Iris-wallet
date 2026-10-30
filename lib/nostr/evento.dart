import 'dart:convert';
import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';

import 'chaves.dart';

/// Evento Nostr (NIP-01): o id é o sha256 da serialização canônica, e a
/// assinatura Schnorr (BIP340) prova que veio da chave em `pubkey`.
class EventoNostr {
  final String id;
  final String pubkey;
  final int criadoEm;
  final int kind;
  final List<List<String>> tags;
  final String conteudo;
  final String assinatura;

  const EventoNostr({
    required this.id,
    required this.pubkey,
    required this.criadoEm,
    required this.kind,
    required this.tags,
    required this.conteudo,
    required this.assinatura,
  });

  static String calcularId(String pubkey, int criadoEm, int kind,
      List<List<String>> tags, String conteudo) {
    final serial = jsonEncode([0, pubkey, criadoEm, kind, tags, conteudo]);
    return sha256.convert(utf8.encode(serial)).toString();
  }

  factory EventoNostr.assinar(
    ChavesNostr chaves, {
    required int kind,
    required String conteudo,
    List<List<String>> tags = const [],
    int? criadoEm,
  }) {
    final t = criadoEm ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = calcularId(chaves.publica, t, kind, tags, conteudo);
    final aux = paraHex(List.generate(32, (_) => Random.secure().nextInt(256)));
    return EventoNostr(
      id: id,
      pubkey: chaves.publica,
      criadoEm: t,
      kind: kind,
      tags: tags,
      conteudo: conteudo,
      assinatura: bip340.sign(chaves.privada, id, aux),
    );
  }

  /// Confere id e assinatura. Evento que vem de relay sem passar aqui não é
  /// confiável: o relay pode inventar ou adulterar.
  bool get valido {
    try {
      return id == calcularId(pubkey, criadoEm, kind, tags, conteudo) &&
          bip340.verify(pubkey, id, assinatura);
    } catch (_) {
      return false;
    }
  }

  /// Valor da primeira tag com este nome (ex.: `d`, `p`, `e`).
  String? tag(String nome) {
    for (final t in tags) {
      if (t.length > 1 && t[0] == nome) return t[1];
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': criadoEm,
        'kind': kind,
        'tags': tags,
        'content': conteudo,
        'sig': assinatura,
      };

  factory EventoNostr.fromJson(Map<String, dynamic> j) => EventoNostr(
        id: j['id'] as String,
        pubkey: j['pubkey'] as String,
        criadoEm: (j['created_at'] as num).toInt(),
        kind: (j['kind'] as num).toInt(),
        tags: [
          for (final t in (j['tags'] as List? ?? const []))
            [for (final x in t as List) x.toString()]
        ],
        conteudo: j['content'] as String? ?? '',
        assinatura: j['sig'] as String,
      );
}
