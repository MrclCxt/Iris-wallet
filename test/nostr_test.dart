import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/nostr/chaves.dart';
import 'package:iris_wallet/nostr/evento.dart';
import 'package:iris_wallet/nostr/nip44.dart';

/// NIP-06 e NIP-44 contra os vetores oficiais:
/// - NIP-06: https://github.com/nostr-protocol/nips/blob/master/06.md
/// - NIP-44: subconjunto de https://github.com/paulmillr/nip44 (nip44.vectors.json)
/// Se a cifragem divergir em um bit, Bro e Mostro não conseguem ler nossas
/// mensagens — e nós as deles.
void main() {
  _eventos();

  group('NIP-06', () {
    test('vetor 1 (12 palavras)', () {
      final k = ChavesNostr.daSemente(
          'leader monkey parrot ring guide accident before fence cannon height naive bean');
      expect(k.privada,
          '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
      expect(k.publica,
          '17162c921dc4d2518f9a101db33695df1afb56ab82f5ff3e5da6eec3ca5cd917');
    });

    test('vetor 2 (24 palavras)', () {
      final k = ChavesNostr.daSemente(
          'what bleak badge arrange retreat wolf trade produce cricket blur garlic valid proud rude strong choose busy staff weather area salt hollow arm fade');
      expect(k.privada,
          'c15d739894c81a2fcfd3a2df85a0d2c0dbc47a280d092799f144d73d7ae78add');
      expect(k.publica,
          'd41b22899549e1f3d335a31002cfd382174006e166d3e658e3a5eecdb6463573');
    });
  });

  group('NIP-44', () {
    final v = jsonDecode(_vetores) as Map<String, dynamic>;

    test('chave da conversa', () {
      for (final c in v['conversa'] as List) {
        expect(paraHex(Nip44.chaveDaConversa(c['sec1'], c['pub2'])),
            c['conversation_key']);
      }
    });

    test('chaves da mensagem', () {
      final mk = v['chaves_mensagem'];
      for (final c in mk['keys'] as List) {
        final k = Nip44.chavesDaMensagem(
            deHex(mk['conversation_key']), deHex(c['nonce']));
        expect(paraHex(k.chave), c['chacha_key']);
        expect(paraHex(k.nonce), c['chacha_nonce']);
        expect(paraHex(k.mac), c['hmac_key']);
      }
    });

    test('tamanho preenchido', () {
      for (final p in v['preenchimento'] as List) {
        expect(Nip44.tamanhoPreenchido(p[0]), p[1]);
      }
    });

    test('cifra e decifra igual ao vetor', () {
      for (final c in v['cifrar'] as List) {
        final conversa = deHex(c['conversation_key']);
        expect(paraHex(Nip44.chaveDaConversa(
                c['sec1'], ChavesNostr.daPrivada(c['sec2']).publica)),
            c['conversation_key']);
        expect(Nip44.cifrar(c['plaintext'], conversa, nonce: deHex(c['nonce'])),
            c['payload']);
        expect(Nip44.decifrar(c['payload'], conversa), c['plaintext']);
      }
    });

    test('recusa cargas inválidas', () {
      for (final c in v['invalidos'] as List) {
        expect(() => Nip44.decifrar(c['payload'], deHex(c['conversation_key'])),
            throwsA(anything), reason: c['note']);
      }
    });

    test('ida e volta entre duas chaves', () {
      final a = ChavesNostr.daPrivada(
          '0000000000000000000000000000000000000000000000000000000000000003');
      final b = ChavesNostr.daPrivada(
          '0000000000000000000000000000000000000000000000000000000000000004');
      final ab = Nip44.chaveDaConversa(a.privada, b.publica);
      final ba = Nip44.chaveDaConversa(b.privada, a.publica);
      expect(paraHex(ab), paraHex(ba));
      const texto = 'ordem 42: boleto pago ✅';
      expect(Nip44.decifrar(Nip44.cifrar(texto, ab), ba), texto);
    });
  });
}

void _eventos() {
  group('NIP-01', () {
    final k = ChavesNostr.daPrivada(
        '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');

    test('evento assinado é válido e volta igual do JSON', () {
      final e = EventoNostr.assinar(k,
          kind: 1, conteudo: 'olá "mundo"\n⚡', tags: [['t', 'iris']]);
      expect(e.valido, isTrue);
      final volta = EventoNostr.fromJson(
          jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(volta.valido, isTrue);
      expect(volta.tag('t'), 'iris');
    });

    test('conteúdo adulterado invalida o evento', () {
      final e = EventoNostr.assinar(k, kind: 1, conteudo: 'pague 1000');
      final j = e.toJson()..['content'] = 'pague 9000';
      expect(EventoNostr.fromJson(j).valido, isFalse);
    });

    test('assinatura de outra chave invalida o evento', () {
      final e = EventoNostr.assinar(k, kind: 1, conteudo: 'x');
      final outra = ChavesNostr.daPrivada(
          'c15d739894c81a2fcfd3a2df85a0d2c0dbc47a280d092799f144d73d7ae78add');
      final j = e.toJson()..['pubkey'] = outra.publica;
      expect(EventoNostr.fromJson(j).valido, isFalse);
    });
  });
}

const _vetores = r'''
{
  "conversa": [
    {
      "sec1": "315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268",
      "pub2": "c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133",
      "conversation_key": "3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1"
    },
    {
      "sec1": "a1e37752c9fdc1273be53f68c5f74be7c8905728e8de75800b94262f9497c86e",
      "pub2": "03bb7947065dde12ba991ea045132581d0954f042c84e06d8c00066e23c1a800",
      "conversation_key": "4d14f36e81b8452128da64fe6f1eae873baae2f444b02c950b90e43553f2178b"
    },
    {
      "sec1": "98a5902fd67518a0c900f0fb62158f278f94a21d6f9d33d30cd3091195500311",
      "pub2": "aae65c15f98e5e677b5050de82e3aba47a6fe49b3dab7863cf35d9478ba9f7d1",
      "conversation_key": "9c00b769d5f54d02bf175b7284a1cbd28b6911b06cda6666b2243561ac96bad7"
    },
    {
      "sec1": "86ae5ac8034eb2542ce23ec2f84375655dab7f836836bbd3c54cefe9fdc9c19f",
      "pub2": "59f90272378089d73f1339710c02e2be6db584e9cdbe86eed3578f0c67c23585",
      "conversation_key": "19f934aafd3324e8415299b64df42049afaa051c71c98d0aa10e1081f2e3e2ba"
    },
    {
      "sec1": "2528c287fe822421bc0dc4c3615878eb98e8a8c31657616d08b29c00ce209e34",
      "pub2": "f66ea16104c01a1c532e03f166c5370a22a5505753005a566366097150c6df60",
      "conversation_key": "c833bbb292956c43366145326d53b955ffb5da4e4998a2d853611841903f5442"
    },
    {
      "sec1": "49808637b2d21129478041813aceb6f2c9d4929cd1303cdaf4fbdbd690905ff2",
      "pub2": "74d2aab13e97827ea21baf253ad7e39b974bb2498cc747cdb168582a11847b65",
      "conversation_key": "4bf304d3c8c4608864c0fe03890b90279328cd24a018ffa9eb8f8ccec06b505d"
    }
  ],
  "chaves_mensagem": {
    "conversation_key": "a1a3d60f3470a8612633924e91febf96dc5366ce130f658b1f0fc652c20b3b54",
    "keys": [
      {
        "nonce": "e1e6f880560d6d149ed83dcc7e5861ee62a5ee051f7fde9975fe5d25d2a02d72",
        "chacha_key": "f145f3bed47cb70dbeaac07f3a3fe683e822b3715edb7c4fe310829014ce7d76",
        "chacha_nonce": "c4ad129bb01180c0933a160c",
        "hmac_key": "027c1db445f05e2eee864a0975b0ddef5b7110583c8c192de3732571ca5838c4"
      },
      {
        "nonce": "e1d6d28c46de60168b43d79dacc519698512ec35e8ccb12640fc8e9f26121101",
        "chacha_key": "e35b88f8d4a8f1606c5082f7a64b100e5d85fcdb2e62aeafbec03fb9e860ad92",
        "chacha_nonce": "22925e920cee4a50a478be90",
        "hmac_key": "46a7c55d4283cb0df1d5e29540be67abfe709e3b2e14b7bf9976e6df994ded30"
      },
      {
        "nonce": "cfc13bef512ac9c15951ab00030dfaf2626fdca638dedb35f2993a9eeb85d650",
        "chacha_key": "020783eb35fdf5b80ef8c75377f4e937efb26bcbad0e61b4190e39939860c4bf",
        "chacha_nonce": "d3594987af769a52904656ac",
        "hmac_key": "237ec0ccb6ebd53d179fa8fd319e092acff599ef174c1fdafd499ef2b8dee745"
      }
    ]
  },
  "preenchimento": [
    [
      16,
      32
    ],
    [
      32,
      32
    ],
    [
      33,
      64
    ],
    [
      37,
      64
    ],
    [
      45,
      64
    ],
    [
      49,
      64
    ],
    [
      64,
      64
    ],
    [
      65,
      96
    ],
    [
      100,
      128
    ],
    [
      111,
      128
    ],
    [
      200,
      224
    ],
    [
      250,
      256
    ],
    [
      320,
      320
    ],
    [
      383,
      384
    ],
    [
      384,
      384
    ],
    [
      400,
      448
    ],
    [
      500,
      512
    ],
    [
      512,
      512
    ],
    [
      515,
      640
    ],
    [
      700,
      768
    ],
    [
      800,
      896
    ],
    [
      900,
      1024
    ],
    [
      1020,
      1024
    ],
    [
      65536,
      65536
    ]
  ],
  "cifrar": [
    {
      "sec1": "0000000000000000000000000000000000000000000000000000000000000001",
      "sec2": "0000000000000000000000000000000000000000000000000000000000000002",
      "conversation_key": "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d",
      "nonce": "0000000000000000000000000000000000000000000000000000000000000001",
      "plaintext": "a",
      "payload": "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"
    },
    {
      "sec1": "0000000000000000000000000000000000000000000000000000000000000002",
      "sec2": "0000000000000000000000000000000000000000000000000000000000000001",
      "conversation_key": "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d",
      "nonce": "f00000000000000000000000000000f00000000000000000000000000000000f",
      "plaintext": "🍕🫃",
      "payload": "AvAAAAAAAAAAAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAPSKSK6is9ngkX2+cSq85Th16oRTISAOfhStnixqZziKMDvB0QQzgFZdjLTPicCJaV8nDITO+QfaQ61+KbWQIOO2Yj"
    },
    {
      "sec1": "5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a",
      "sec2": "4b22aa260e4acb7021e32f38a6cdf4b673c6a277755bfce287e370c924dc936d",
      "conversation_key": "3e2b52a63be47d34fe0a80e34e73d436d6963bc8f39827f327057a9986c20a45",
      "nonce": "b635236c42db20f021bb8d1cdff5ca75dd1a0cc72ea742ad750f33010b24f73b",
      "plaintext": "表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀",
      "payload": "ArY1I2xC2yDwIbuNHN/1ynXdGgzHLqdCrXUPMwELJPc7s7JqlCMJBAIIjfkpHReBPXeoMCyuClwgbT419jUWU1PwaNl4FEQYKCDKVJz+97Mp3K+Q2YGa77B6gpxB/lr1QgoqpDf7wDVrDmOqGoiPjWDqy8KzLueKDcm9BVP8xeTJIxs="
    },
    {
      "sec1": "8f40e50a84a7462e2b8d24c28898ef1f23359fff50d8c509e6fb7ce06e142f9c",
      "sec2": "b9b0a1e9cc20100c5faa3bbe2777303d25950616c4c6a3fa2e3e046f936ec2ba",
      "conversation_key": "d5a2f879123145a4b291d767428870f5a8d9e5007193321795b40183d4ab8c2b",
      "nonce": "b20989adc3ddc41cd2c435952c0d59a91315d8c5218d5040573fc3749543acaf",
      "plaintext": "ability🤝的 ȺȾ",
      "payload": "ArIJia3D3cQc0sQ1lSwNWakTFdjFIY1QQFc/w3SVQ6yvbG2S0x4Yu86QGwPTy7mP3961I1XqB6SFFTzqDZZavhxoWMj7mEVGMQIsh2RLWI5EYQaQDIePSnXPlzf7CIt+voTD"
    },
    {
      "sec1": "875adb475056aec0b4809bd2db9aa00cff53a649e7b59d8edcbf4e6330b0995c",
      "sec2": "9c05781112d5b0a2a7148a222e50e0bd891d6b60c5483f03456e982185944aae",
      "conversation_key": "3b15c977e20bfe4b8482991274635edd94f366595b1a3d2993515705ca3cedb8",
      "nonce": "8d4442713eb9d4791175cb040d98d6fc5be8864d6ec2f89cf0895a2b2b72d1b1",
      "plaintext": "pepper👀їжак",
      "payload": "Ao1EQnE+udR5EXXLBA2Y1vxb6IZNbsL4nPCJWisrctGxY3AduCS+jTUgAAnfvKafkmpy15+i9YMwCdccisRa8SvzW671T2JO4LFSPX31K4kYUKelSAdSPwe9NwO6LhOsnoJ+"
    }
  ],
  "invalidos": [
    {
      "conversation_key": "ca2527a037347b91bea0c8a30fc8d9600ffd81ec00038671e3a0f0cb0fc9f642",
      "nonce": "daaea5ca345b268e5b62060ca72c870c48f713bc1e00ff3fc0ddb78e826f10db",
      "plaintext": "n o b l e",
      "payload": "#Atqupco0WyaOW2IGDKcshwxI9xO8HgD/P8Ddt46CbxDbrhdG8VmJdU0MIDf06CUvEvdnr1cp1fiMtlM/GrE92xAc1K5odTpCzUB+mjXgbaqtntBUbTToSUoT0ovrlPwzGjyp",
      "note": "unknown encryption version"
    },
    {
      "conversation_key": "36f04e558af246352dcf73b692fbd3646a2207bd8abd4b1cd26b234db84d9481",
      "nonce": "ad408d4be8616dc84bb0bf046454a2a102edac937c35209c43cd7964c5feb781",
      "plaintext": "⚠️",
      "payload": "AK1AjUvoYW3IS7C/BGRUoqEC7ayTfDUgnEPNeWTF/reBZFaha6EAIRueE9D1B1RuoiuFScC0Q94yjIuxZD3JStQtE8JMNacWFs9rlYP+ZydtHhRucp+lxfdvFlaGV/sQlqZz",
      "note": "unknown encryption version 0"
    },
    {
      "conversation_key": "ca2527a037347b91bea0c8a30fc8d9600ffd81ec00038671e3a0f0cb0fc9f642",
      "nonce": "daaea5ca345b268e5b62060ca72c870c48f713bc1e00ff3fc0ddb78e826f10db",
      "plaintext": "n o s t r",
      "payload": "Atфupco0WyaOW2IGDKcshwxI9xO8HgD/P8Ddt46CbxDbrhdG8VmJZE0UICD06CUvEvdnr1cp1fiMtlM/GrE92xAc1EwsVCQEgWEu2gsHUVf4JAa3TpgkmFc3TWsax0v6n/Wq",
      "note": "invalid base64"
    },
    {
      "conversation_key": "cff7bd6a3e29a450fd27f6c125d5edeb0987c475fd1e8d97591e0d4d8a89763c",
      "nonce": "09ff97750b084012e15ecb84614ce88180d7b8ec0d468508a86b6d70c0361a25",
      "plaintext": "¯\\_(ツ)_/¯",
      "payload": "Agn/l3ULCEAS4V7LhGFM6IGA17jsDUaFCKhrbXDANholyySBfeh+EN8wNB9gaLlg4j6wdBYh+3oK+mnxWu3NKRbSvQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "note": "invalid MAC"
    },
    {
      "conversation_key": "cfcc9cf682dfb00b11357f65bdc45e29156b69db424d20b3596919074f5bf957",
      "nonce": "65b14b0b949aaa7d52c417eb753b390e8ad6d84b23af4bec6d9bfa3e03a08af4",
      "plaintext": "🥎",
      "payload": "AmWxSwuUmqp9UsQX63U7OQ6K1thLI69L7G2b+j4DoIr0oRWQ8avl4OLqWZiTJ10vIgKrNqjoaX+fNhE9RqmR5g0f6BtUg1ijFMz71MO1D4lQLQfW7+UHva8PGYgQ1QpHlKgR",
      "note": "invalid MAC"
    },
    {
      "conversation_key": "5254827d29177622d40a7b67cad014fe7137700c3c523903ebbe3e1b74d40214",
      "nonce": "7ab65dbb8bbc2b8e35cafb5745314e1f050325a864d11d0475ef75b3660d91c1",
      "plaintext": "elliptic-curve cryptography",
      "payload": "Anq2XbuLvCuONcr7V0UxTh8FAyWoZNEdBHXvdbNmDZHB573MI7R7rrTYftpqmvUpahmBC2sngmI14/L0HjOZ7lWGJlzdh6luiOnGPc46cGxf08MRC4CIuxx3i2Lm0KqgJ7vA",
      "note": "invalid padding"
    }
  ]
}
''';
