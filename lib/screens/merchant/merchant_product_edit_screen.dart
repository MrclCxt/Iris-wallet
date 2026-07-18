import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';

class MerchantProductEditScreen extends StatefulWidget {
  final Product product;
  const MerchantProductEditScreen({super.key, required this.product});

  @override
  State<MerchantProductEditScreen> createState() => _MerchantProductEditScreenState();
}

class _MerchantProductEditScreenState extends State<MerchantProductEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _brlCtrl;
  late TextEditingController _satsCtrl;
  late String _selectedEmoji;
  late bool _isActive;
  String? _error;

  final List<String> _emojis = ['☕', '🍕', '🥗', '🍺', '💇', '📦', '🎮', '👕', '🔧', '🏠', '🎵', '📚'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isActive && _nameCtrl.text == widget.product.name) {
      final exchangeRate = context.read<ExchangeRateService>();
      if (_satsCtrl.text.isEmpty) {
        _satsCtrl.text = exchangeRate.brlToSats(widget.product.price).toString();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product.name);
    _brlCtrl = TextEditingController(text: widget.product.price.toStringAsFixed(2));
    _satsCtrl = TextEditingController();
    _selectedEmoji = widget.product.emoji;
    _isActive = widget.product.isActive;
    if (!_emojis.contains(_selectedEmoji)) _emojis.add(_selectedEmoji);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brlCtrl.dispose();
    _satsCtrl.dispose();
    super.dispose();
  }

  void _syncBrlToSats(String val) {
    if (val.isEmpty) {
      _satsCtrl.text = '';
      return;
    }
    double? brl = double.tryParse(val.replaceAll(',', '.'));
    if (brl != null) {
      final exchangeRate = context.read<ExchangeRateService>();
      _satsCtrl.text = exchangeRate.brlToSats(brl).toString();
    }
  }

  void _syncSatsToBrl(String val) {
    if (val.isEmpty) {
      _brlCtrl.text = '';
      return;
    }
    int? sats = int.tryParse(val);
    if (sats != null) {
      final exchangeRate = context.read<ExchangeRateService>();
      _brlCtrl.text = exchangeRate.satsToBrl(sats).toStringAsFixed(2);
    }
  }

  void _saveProduct() {
    final name = _nameCtrl.text.trim();
    final brlText = _brlCtrl.text.replaceAll(',', '.');
    final price = double.tryParse(brlText) ?? 0.0;

    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome.');
      return;
    }
    if (price <= 0) {
      setState(() => _error = 'Informe um valor válido.');
      return;
    }

    final p = Product(
      id: widget.product.id,
      emoji: _selectedEmoji,
      name: name,
      price: price,
      isActive: _isActive,
    );

    context.read<WalletService>().updateMerchantProduct(p);
    Navigator.pop(context);
  }

  void _delete() {
    context.read<WalletService>().removeMerchantProduct(widget.product.id);
    Navigator.pop(context); // volta pro qr code
    Navigator.pop(context); // volta pra lista de produtos
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      body: SafeArea(
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
                      color: IrisTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(child: Text('✏️', style: TextStyle(fontSize: 17))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Editar produto', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: IrisTheme.danger),
                    onPressed: _delete,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: IrisTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
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
                    const Text('Nome', style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ex: Café, Corte de cabelo...',
                        filled: true,
                        fillColor: IrisTheme.s1,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('Ícone', style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: IrisTheme.s1,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedEmoji,
                          isExpanded: true,
                          dropdownColor: IrisTheme.s2,
                          items: _emojis.map((e) => DropdownMenuItem(value: e, child: Text('$e Ícone', style: const TextStyle(fontSize: 14)))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedEmoji = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Valor R\$', style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _brlCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: _syncBrlToSats,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '0,00',
                                  filled: true,
                                  fillColor: IrisTheme.s1,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 34, left: 10, right: 10),
                          child: Text('ou', style: TextStyle(color: IrisTheme.textSecondary.withOpacity(0.5), fontSize: 12)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Valor sats', style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _satsCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: _syncSatsToBrl,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  filled: true,
                                  fillColor: IrisTheme.s1,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Produto Ativo?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Switch(
                          value: _isActive,
                          activeColor: IrisTheme.primary,
                          onChanged: (val) {
                            setState(() => _isActive = val);
                          },
                        ),
                      ],
                    ),
                    Text(
                      'Produtos inativos não podem gerar cobranças no PDV.',
                      style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary),
                    ),
                    
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: const TextStyle(color: IrisTheme.danger, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
            
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: _saveProduct,
                        style: ElevatedButton.styleFrom(backgroundColor: IrisTheme.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: const Text('Salvar alterações', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('← Voltar', style: TextStyle(color: IrisTheme.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
