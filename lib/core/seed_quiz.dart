import 'dart:math';

class SeedQuiz {
  final List<int> indices;

  final List<List<String>> alternativas;

  const SeedQuiz({required this.indices, required this.alternativas});

  static const int perguntas = 4;

  static SeedQuiz gerar(List<String> palavras, {Random? random}) {
    final r = random ?? Random();
    final total = palavras.length;
    final quantas = total < perguntas ? total : perguntas;

    final escolhidas = <int>{};
    while (escolhidas.length < quantas) {
      escolhidas.add(r.nextInt(total));
    }
    final indices = escolhidas.toList()..sort();

    return SeedQuiz(
      indices: indices,
      alternativas: [
        for (final i in indices) _alternativasPara(palavras, i, r),
      ],
    );
  }

  static List<String> _alternativasPara(
      List<String> palavras, int correta, Random r) {
    final opcoes = <String>{palavras[correta]};

    var tentativas = 0;
    while (opcoes.length < 2 && tentativas < 50) {
      opcoes.add(palavras[r.nextInt(palavras.length)]);
      tentativas++;
    }
    while (opcoes.length < 3) {
      opcoes.add(_distratores[r.nextInt(_distratores.length)]);
    }

    return opcoes.toList()..shuffle(r);
  }

  static const List<String> _distratores = [
    'abandon',
    'ability',
    'able',
    'about',
    'above',
    'absent',
    'absorb',
    'abstract',
    'absurd',
    'abuse',
    'access',
    'accident',
    'account',
    'accuse',
    'achieve',
    'acid',
    'acoustic',
    'acquire',
    'across',
    'act',
    'action',
    'actor',
    'actress',
    'actual',
    'adapt',
    'add',
    'addict',
    'address',
    'adjust',
    'admit',
    'adult',
    'advance',
    'advice',
    'aerobic',
    'affair',
    'afford',
    'afraid',
    'again',
    'age',
    'agent',
    'basket',
    'battery',
    'beach',
    'beauty',
    'because',
    'become',
    'beef',
    'before',
    'begin',
    'behave',
    'camera',
    'camp',
    'canal',
    'cancel',
    'candy',
    'cannon',
    'canoe',
    'canvas',
    'canyon',
    'damage',
    'dance',
    'danger',
    'daring',
    'dark',
    'data',
    'date',
    'dawn',
    'day',
    'dead',
    'early',
    'earn',
    'earth',
    'east',
    'easy',
    'eat',
    'echo',
    'ecology',
    'economy',
    'edge',
    'fabric',
    'face',
    'facility',
    'fact',
    'fade',
    'fail',
    'faint',
    'fair',
    'faith',
    'fall',
    'galaxy',
    'gallery',
    'game',
    'gap',
    'garage',
    'garbage',
    'garden',
    'garlic',
    'garment',
    'gas',
    'habit',
    'hair',
    'half',
    'hammer',
    'hamster',
    'hand',
    'happy',
    'harbor',
    'hard',
    'harsh',
    'ice',
    'icon',
    'idea',
    'identify',
    'idle',
    'ignore',
    'ill',
    'illegal',
    'illness',
    'image',
    'jacket',
    'jaguar',
    'jail',
    'jam',
    'jar',
    'jazz',
    'jealous',
    'jeans',
    'jelly',
    'kangaroo',
    'keen',
    'keep',
    'ketchup',
    'key',
    'kick',
    'kid',
    'kidney',
    'kind',
    'kingdom',
    'label',
    'labor',
    'ladder',
    'lady',
    'lake',
    'lamp',
    'language',
    'laptop',
    'large',
    'laser',
    'machine',
    'magic',
    'magnet',
    'maid',
    'mail',
    'main',
    'major',
    'make',
    'mammal',
    'name',
    'napkin',
    'narrow',
    'nasty',
    'nation',
    'nature',
    'near',
    'neck',
    'need',
    'negative',
  ];
}
