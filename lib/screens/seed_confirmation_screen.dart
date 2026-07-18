import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../core/theme.dart';

class SeedConfirmationScreen extends StatefulWidget {
  const SeedConfirmationScreen({super.key});

  @override
  State<SeedConfirmationScreen> createState() => _SeedConfirmationScreenState();
}

class _SeedConfirmationScreenState extends State<SeedConfirmationScreen> {
  late int _idx1;
  late int _idx2;
  List<String> _opts1 = [];
  List<String> _opts2 = [];
  String? _ans1;
  String? _ans2;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateQuestions();
  }

  void _generateQuestions() {
    final seedStr = context.read<WalletService>().consumerSeed;
    if (seedStr == null) return;
    
    final words = seedStr.split(' ');
    final random = Random();
    
    // Pick two distinct indices
    _idx1 = random.nextInt(12);
    _idx2 = _idx1;
    while (_idx2 == _idx1) {
      _idx2 = random.nextInt(12);
    }
    
    // Make sure _idx1 < _idx2 for UI order
    if (_idx1 > _idx2) {
      final tmp = _idx1;
      _idx1 = _idx2;
      _idx2 = tmp;
    }
    
    _opts1 = _generateOptionsFor(words, _idx1, random);
    _opts2 = _generateOptionsFor(words, _idx2, random);
  }

  List<String> _generateOptionsFor(List<String> seedWords, int correctIdx, Random random) {
    final correctWord = seedWords[correctIdx];
    final opts = {correctWord};
    
    // Try to get another word from the seed itself
    while (opts.length < 2) {
      opts.add(seedWords[random.nextInt(12)]);
    }
    
    // Get a random BIP39 word from a small local dictionary to use as a distractor
    final dict = [
      'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract', 'absurd', 'abuse',
      'access', 'accident', 'account', 'accuse', 'achieve', 'acid', 'acoustic', 'acquire', 'across', 'act',
      'action', 'actor', 'actress', 'actual', 'adapt', 'add', 'addict', 'address', 'adjust', 'admit',
      'adult', 'advance', 'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent',
      'basket', 'battery', 'beach', 'beauty', 'because', 'become', 'beef', 'before', 'begin', 'behave',
      'camera', 'camp', 'can', 'canal', 'cancel', 'candy', 'cannon', 'canoe', 'canvas', 'canyon',
      'damage', 'dance', 'danger', 'daring', 'dark', 'data', 'date', 'dawn', 'day', 'dead',
      'early', 'earn', 'earth', 'east', 'easy', 'eat', 'echo', 'ecology', 'economy', 'edge',
      'fabric', 'face', 'facility', 'fact', 'fade', 'fail', 'faint', 'fair', 'faith', 'fall',
      'galaxy', 'gallery', 'game', 'gap', 'garage', 'garbage', 'garden', 'garlic', 'garment', 'gas',
      'habit', 'hair', 'half', 'hammer', 'hamster', 'hand', 'happy', 'harbor', 'hard', 'harsh',
      'ice', 'icon', 'idea', 'identify', 'idle', 'ignore', 'ill', 'illegal', 'illness', 'image',
      'jacket', 'jaguar', 'jail', 'jam', 'james', 'jar', 'jazz', 'jealous', 'jeans', 'jelly',
      'kangaroo', 'keen', 'keep', 'ketchup', 'key', 'kick', 'kid', 'kidney', 'kind', 'kingdom',
      'label', 'labor', 'ladder', 'lady', 'lake', 'lamp', 'language', 'laptop', 'large', 'laser',
      'machine', 'mad', 'magic', 'magnet', 'maid', 'mail', 'main', 'major', 'make', 'mammal',
      'name', 'napkin', 'narrow', 'nasty', 'nation', 'nature', 'near', 'neck', 'need', 'negative'
    ];
    while (opts.length < 3) {
      opts.add(dict[random.nextInt(dict.length)]);
    }
    
    final optList = opts.toList();
    optList.shuffle(random);
    return optList;
  }

  void _verify() {
    final seedStr = context.read<WalletService>().consumerSeed;
    if (seedStr == null) return;
    final words = seedStr.split(' ');
    
    if (_ans1 == words[_idx1] && _ans2 == words[_idx2]) {
      setState(() => _error = null);
      Navigator.pushReplacementNamed(context, '/pin_create');
    } else {
      setState(() => _error = 'Palavras incorretas. Tente novamente ou releia sua semente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final seedStr = context.watch<WalletService>().consumerSeed;
    if (seedStr == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmação'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: IrisTheme.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Text('✅', style: TextStyle(fontSize: 17))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.read<WalletService>().consumerAccounts.isNotEmpty ? 'Confirme a Semente (Secundária)' : 'Confirme sua semente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(context.read<WalletService>().consumerAccounts.isNotEmpty ? 'Para garantir que anotou a nova semente.' : 'Para garantir que anotou corretamente.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: IrisTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuestionBlock(1, _idx1, _opts1, _ans1, (val) => setState(() => _ans1 = val)),
                        const SizedBox(height: 14),
                        _buildQuestionBlock(2, _idx2, _opts2, _ans2, (val) => setState(() => _ans2 = val)),
                        
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Center(
                              child: Text(_error!, style: const TextStyle(color: IrisTheme.danger, fontSize: 12), textAlign: TextAlign.center),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: (_ans1 != null && _ans2 != null) ? _verify : null,
                        child: const Text('Confirmar e continuar'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: IrisTheme.textSecondary,
                          side: const BorderSide(color: IrisTheme.bdr),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Outfit'),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('← Voltar e reler'),
                      ),
                      if (context.watch<WalletService>().consumerAccounts.isNotEmpty || context.watch<WalletService>().merchantAccounts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            context.read<WalletService>().cancelWalletCreation();
                            Navigator.of(context).popUntil((route) => route.settings.name == '/consumer_home' || route.settings.name == '/welcome' || route.isFirst);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: IrisTheme.danger,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancelar e Voltar', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionBlock(int qNum, int idx, List<String> opts, String? currentAns, ValueChanged<String> onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é a ${idx + 1}ª palavra?',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: IrisTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Row(
          children: opts.map((opt) {
            final isSelected = opt == currentAns;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(opt),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? IrisTheme.primary : IrisTheme.s2,
                    border: Border.all(color: isSelected ? IrisTheme.primary : IrisTheme.bdr2, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.black : IrisTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
