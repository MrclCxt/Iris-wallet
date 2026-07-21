import 'dart:math';
import 'package:flutter/material.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';

class MerchantSetupScreen extends StatefulWidget {
  const MerchantSetupScreen({super.key});

  @override
  State<MerchantSetupScreen> createState() => _MerchantSetupScreenState();
}

class _MerchantSetupScreenState extends State<MerchantSetupScreen> {
  int _step = 0; // 0: Nome, 1: Escolha (Novo/Importar), 2: Semente, 3: Confirmacao, 4: PIN
  String _mode = ''; // 'new' ou 'import'
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _seedCtrl = TextEditingController();
  String _seed = '';
  String _pin = '';
  String _firstPin = '';
  bool _isConfirmingPin = false;

  // Variables for confirmation step
  late int _idx1;
  late int _idx2;
  List<String> _opts1 = [];
  List<String> _opts2 = [];
  String? _ans1;
  String? _ans2;
  String? _errorMsg;

  void _generateQuestions() {
    final words = _seed.split(' ');
    final random = Random();
    
    _idx1 = random.nextInt(12);
    _idx2 = _idx1;
    while (_idx2 == _idx1) {
      _idx2 = random.nextInt(12);
    }
    
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
    
    while (opts.length < 2) {
      opts.add(seedWords[random.nextInt(12)]);
    }
    
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

  void _nextStep() {
    if (_step == 0 && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insira um nome válido')));
      return;
    }
    if (_step == 2 && _mode == 'import') {
      final seedInput = _seedCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final words = seedInput.split(' ');
      if (words.length != 12) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A semente deve conter exatamente 12 palavras')));
        return;
      }
      if (!bip39.validateMnemonic(seedInput)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Semente inválida. Verifique a ortografia.')));
        return;
      }
      _seed = seedInput;
      setState(() => _step = 4); // skip confirmation for import
      return;
    }
    if (_step == 2 && _mode == 'new') {
      _generateQuestions();
    }
    if (_step == 3) {
      final words = _seed.split(' ');
      if (_ans1 == words[_idx1] && _ans2 == words[_idx2]) {
        setState(() => _errorMsg = null);
      } else {
        setState(() => _errorMsg = 'Palavras incorretas. Tente novamente.');
        return;
      }
    }
    
    setState(() => _step++);
  }

  void _onKeyPress(String key) async {
    if (key == 'del') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    } else {
      if (_pin.length < 6) {
        setState(() => _pin += key);
        if (_pin.length == 6) {
          if (!_isConfirmingPin) {
            setState(() {
              _firstPin = _pin;
              _pin = '';
              _isConfirmingPin = true;
            });
          } else {
            if (_pin == _firstPin) {
              // Finalize setup
              final wallet = context.read<WalletService>();
              await wallet.setupMerchant(_nameCtrl.text.trim(), _seed, _pin);
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/merchant_home');
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Os PINs não coincidem. Tente novamente.'), backgroundColor: IrisTheme.danger),
              );
              setState(() {
                _pin = '';
                _firstPin = '';
                _isConfirmingPin = false;
              });
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () {
            if (_step == 4 && _mode == 'import') {
              setState(() => _step = 2);
            } else if (_step > 0) {
              setState(() => _step--);
            } else {
              Navigator.pushReplacementNamed(context, '/consumer_home');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step == 0) _buildStep0()
                else if (_step == 1) _buildStep1()
                else if (_step == 2 && _mode == 'new') _buildStep2New()
                else if (_step == 2 && _mode == 'import') _buildStep2Import()
                else if (_step == 3) _buildStep3Confirmation()
                else if (_step == 4) _buildStep4Pin()
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep0() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🏪', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text('Criar perfil de Loja', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('O seu PDV terá saldo e configurações independentes da sua carteira pessoal.', style: TextStyle(color: IrisTheme.textSecondary)),
            const SizedBox(height: 32),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Nome do seu estabelecimento',
                filled: true,
                fillColor: IrisTheme.s1,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Opções de Carteira', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Como deseja configurar a carteira do seu estabelecimento?', style: TextStyle(color: IrisTheme.textSecondary)),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                _seed = bip39.generateMnemonic();
                _mode = 'new';
                _nextStep();
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: IrisTheme.primary),
              child: const Text('Criar com nova carteira →', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _mode = 'import';
                _nextStep();
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: IrisTheme.s2, foregroundColor: IrisTheme.textPrimary),
              child: const Text('🔄 Importar carteira existente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2New() {
    final words = _seed.split(' ');
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: IrisTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Text('🔑', style: TextStyle(fontSize: 17))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Semente da Loja', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      const Text('12 palavras que abrem sua loja', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('ANOTE EM PAPEL ANTES DE CONTINUAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: IrisTheme.textTertiary)),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 4.5,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
              ),
              itemCount: 12,
              itemBuilder: (ctx, i) {
                return Container(
                  decoration: BoxDecoration(
                    color: IrisTheme.s2,
                    border: Border.all(color: IrisTheme.bdr),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text('${i + 1}.', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: IrisTheme.textTertiary)),
                      ),
                      Text(words[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: IrisTheme.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: IrisTheme.primaryDark,
                border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Guarde essas palavras em lugar seguro. Se perder o acesso, elas recuperam o saldo da loja.',
                style: TextStyle(color: IrisTheme.primaryLight, fontSize: 12, height: 1.55),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: _nextStep,
                  child: const Text('Já anotei — verificar →'),
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
                    setState(() {
                      _seed = bip39.generateMnemonic();
                    });
                  },
                  child: const Text('Gerar palavras novas'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Import() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: IrisTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Text('🔄', style: TextStyle(fontSize: 17))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Importar carteira', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      const Text('Use uma seed já existente', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '12 palavras (separadas por espaço)',
                    style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _seedCtrl,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: IrisTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'palavra1 palavra2 ...',
                      hintStyle: TextStyle(color: IrisTheme.textSecondary.withOpacity(0.5)),
                      filled: true,
                      fillColor: IrisTheme.s2,
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: IrisTheme.bdr2, width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: IrisTheme.primary, width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: IrisTheme.primaryDark,
                      border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Use se já tem uma carteira Bitcoin Lightning para a loja.',
                      style: TextStyle(color: IrisTheme.primaryLight, fontSize: 12, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Importar →'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Confirmation() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
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
                      Text('Confirme as palavras', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      const Text('Selecione na ordem certa', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
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
                  
                  if (_errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Center(
                        child: Text(_errorMsg!, style: const TextStyle(color: IrisTheme.danger, fontSize: 12), textAlign: TextAlign.center),
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
                  onPressed: (_ans1 != null && _ans2 != null) ? _nextStep : null,
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
                    setState(() {
                      _ans1 = null;
                      _ans2 = null;
                      _errorMsg = null;
                      _step = 2; // voltar e reler
                    });
                  },
                  child: const Text('← Voltar e reler'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Pin() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isConfirmingPin ? 'Confirme o PIN' : 'Crie um PIN para a Loja', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Seus funcionários podem usar este PIN para cobrar clientes sem acessar seu saldo pessoal.', style: TextStyle(color: IrisTheme.textSecondary)),
              ],
            ),
          ),
          const Spacer(),
          _buildDots(),
          const SizedBox(height: 32),
          _buildKeypad(),
          const Spacer(),
        ],
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
                      fontFamily: 'monospace',
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

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        bool isFilled = index < _pin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isFilled ? IrisTheme.primary : IrisTheme.textTertiary,
              width: 2,
            ),
            color: isFilled ? IrisTheme.primary : Colors.transparent,
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 1; i <= 9; i++) _keyBtn('$i'),
              const SizedBox.shrink(),
              _keyBtn('0'),
              _keyBtn('del', icon: '⌫'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyBtn(String val, {String? icon}) {
    return Material(
      color: IrisTheme.s2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: IrisTheme.bdr),
      ),
      child: InkWell(
        onTap: () => _onKeyPress(val),
        borderRadius: BorderRadius.circular(12),
        highlightColor: IrisTheme.s3,
        child: Center(
          child: Text(
            icon ?? val,
            style: TextStyle(
              fontSize: icon != null ? 16 : 20,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: IrisTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
