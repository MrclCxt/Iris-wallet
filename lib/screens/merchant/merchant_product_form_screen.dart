import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/product_image_store.dart';
import '../../widgets/numpad.dart';
import 'product_image_editor.dart';

class MerchantProductFormScreen extends StatefulWidget {
  final Product? product;
  const MerchantProductFormScreen({super.key, this.product});

  bool get isEdicao => product != null;

  @override
  State<MerchantProductFormScreen> createState() =>
      _MerchantProductFormScreenState();
}

class _MerchantProductFormScreenState extends State<MerchantProductFormScreen> {
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _descricaoCtrl;

  late double _precoBrl;
  late bool _ativo;
  String? _imagemArquivo;

  bool _entrandoEmSats = false;
  bool _carregandoImagem = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nomeCtrl = TextEditingController(text: p?.name ?? '');
    _descricaoCtrl = TextEditingController(text: p?.description ?? '');
    _precoBrl = p?.price ?? 0;
    _ativo = p?.isActive ?? true;

    final foto = p?.image;
    _imagemArquivo =
        (foto != null && ProductImageStore.existe(foto)) ? foto : null;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherImagem() async {
    setState(() => _carregandoImagem = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;

      final escolhido = res.files.first;
      var bytes = escolhido.bytes;
      if (bytes == null && escolhido.path != null) {
        bytes = await File(escolhido.path!).readAsBytes();
      }
      if (bytes == null) {
        _mostrarErro('Não foi possível ler a imagem.');
        return;
      }

      if (!mounted) return;

      final enquadrada = await abrirEditorDeFoto(context, bytes);
      if (enquadrada == null) return;

      final nomeArquivo = await ProductImageStore.salvar(
        enquadrada,
        extensao: 'jpg',
      );
      if (nomeArquivo == null) {
        _mostrarErro('Não foi possível guardar a imagem.');
        return;
      }
      setState(() => _imagemArquivo = nomeArquivo);
    } catch (e) {
      _mostrarErro('Falha ao carregar a imagem: $e');
    } finally {
      if (mounted) setState(() => _carregandoImagem = false);
    }
  }

  Future<void> _ampliarImagem() async {
    final caminho = ProductImageStore.caminhoDe(_imagemArquivo);
    if (caminho == null) return;

    final acao = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (ctx) => _VisualizadorDeFoto(
        caminho: caminho,
        titulo: _nomeCtrl.text.trim().isEmpty
            ? 'Foto do produto'
            : _nomeCtrl.text.trim(),
      ),
    );

    if (!mounted) return;
    if (acao == 'trocar') {
      await _escolherImagem();
    } else if (acao == 'remover') {
      setState(() => _imagemArquivo = null);
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    setState(() => _erro = mensagem);
  }

  Future<void> _abrirTecladoDePreco() async {
    final taxa = context.read<ExchangeRateService>();
    final emSats = _entrandoEmSats;

    final resultado = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: IrisTheme.s1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _FolhaDePreco(
        emSats: emSats,
        valorInicialBrl: _precoBrl,
        taxa: taxa,
      ),
    );

    if (resultado != null) {
      setState(() {
        _precoBrl = resultado;
        _erro = null;
      });
    }
  }

  void _salvar() {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      setState(() => _erro = 'Informe um nome.');
      return;
    }
    if (_precoBrl <= 0) {
      setState(() => _erro = 'Informe um valor maior que zero.');
      return;
    }

    final wallet = context.read<WalletService>();
    final descricao = _descricaoCtrl.text.trim();

    if (widget.isEdicao) {
      final p = widget.product!;
      p.name = nome;
      p.description = descricao;
      p.price = _precoBrl;
      p.isActive = _ativo;
      p.image = _imagemArquivo;
      wallet.updateMerchantProduct(p);
    } else {
      wallet.addMerchantProduct(Product(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nome,
        price: _precoBrl,
        isActive: _ativo,
        description: descricao,
        image: _imagemArquivo,
      ));
    }
    Navigator.pop(context);
  }

  void _excluir() {
    final p = widget.product;
    if (p == null) return;
    context.read<WalletService>().removeMerchantProduct(p.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final taxa = context.watch<ExchangeRateService>();

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            _cabecalho(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _seletorDeImagem(),
                    const SizedBox(height: 18),
                    _rotulo('Nome'),
                    _campo(
                      controlador: _nomeCtrl,
                      dica: 'Ex: Café, Corte de cabelo...',
                      maxLinhas: 1,
                    ),
                    const SizedBox(height: 16),
                    _rotulo('Descrição'),
                    _campo(
                      controlador: _descricaoCtrl,
                      dica: 'Detalhes que ajudam o cliente (opcional)',
                      maxLinhas: 3,
                    ),
                    const SizedBox(height: 16),
                    _rotulo('Valor'),
                    _blocoDePreco(taxa),
                    const SizedBox(height: 16),
                    _switchAtivo(),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!,
                          style: const TextStyle(
                              color: IrisTheme.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            _rodape(),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: IrisTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(widget.isEdicao ? '✏️' : '➕',
                  style: const TextStyle(fontSize: 17)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isEdicao ? 'Editar produto' : 'Novo produto',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: IrisTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto,
            style: const TextStyle(
                fontSize: 12,
                color: IrisTheme.textSecondary,
                fontWeight: FontWeight.w500)),
      );

  Widget _campo({
    required TextEditingController controlador,
    required String dica,
    required int maxLinhas,
  }) {
    return TextField(
      controller: controlador,
      maxLines: maxLinhas,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: dica,
        hintStyle: const TextStyle(color: IrisTheme.textTertiary, fontSize: 13),
        filled: true,
        fillColor: IrisTheme.s1,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _seletorDeImagem() {
    final temImagem = _imagemArquivo != null;
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _carregandoImagem
                ? null
                : (temImagem ? _ampliarImagem : _escolherImagem),
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: IrisTheme.s1,
                borderRadius: BorderRadius.circular(18),
                border: temImagem ? null : Border.all(color: IrisTheme.bdr),
              ),
              clipBehavior: Clip.antiAlias,
              child: _carregandoImagem
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : temImagem
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(
                                  ProductImageStore.caminhoDe(_imagemArquivo)!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined,
                                    color: IrisTheme.textTertiary),
                              ),
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.zoom_out_map,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 30, color: IrisTheme.textTertiary),
                            SizedBox(height: 8),
                            Text('Enviar foto',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: IrisTheme.textTertiary)),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _carregandoImagem ? null : _escolherImagem,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(temImagem ? 'Trocar foto' : 'Enviar foto'),
                style: TextButton.styleFrom(foregroundColor: IrisTheme.primary),
              ),
              if (temImagem)
                TextButton.icon(
                  onPressed: () => setState(() => _imagemArquivo = null),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remover'),
                  style: TextButton.styleFrom(
                      foregroundColor: IrisTheme.textSecondary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _blocoDePreco(ExchangeRateService taxa) {
    final sats = taxa.brlToSats(_precoBrl);
    final principal = _entrandoEmSats
        ? CurrencyFormatter.formatBtcOrSats(sats)
        : 'R\$ ${CurrencyFormatter.formatBrlCompact(_precoBrl)}';
    final secundario = _entrandoEmSats
        ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(_precoBrl)}'
        : '≈ ${CurrencyFormatter.formatBtcOrSats(sats)}';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: IrisTheme.s1,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _abaDeUnidade('R\$', !_entrandoEmSats,
                  () => setState(() => _entrandoEmSats = false)),
              _abaDeUnidade('SATS', _entrandoEmSats,
                  () => setState(() => _entrandoEmSats = true)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _abrirTecladoDePreco,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: IrisTheme.s1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: IrisTheme.bdr),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _precoBrl > 0 ? principal : 'Tocar para digitar',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _precoBrl > 0
                              ? IrisTheme.textPrimary
                              : IrisTheme.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_precoBrl > 0) ...[
                        const SizedBox(height: 2),
                        Text(secundario,
                            style: const TextStyle(
                                fontSize: 11, color: IrisTheme.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.dialpad, color: IrisTheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _abaDeUnidade(String texto, bool ativa, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: ativa ? IrisTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ativa ? Colors.white : IrisTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchAtivo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Produto ativo',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('Desativado, ele não aparece para cobrança.',
                    style:
                        TextStyle(fontSize: 11, color: IrisTheme.textTertiary)),
              ],
            ),
          ),
          Switch(
            value: _ativo,
            activeColor: IrisTheme.primary,
            onChanged: (v) => setState(() => _ativo = v),
          ),
        ],
      ),
    );
  }

  Widget _rodape() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: IrisTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(
                  widget.isEdicao ? 'Salvar alterações' : 'Salvar produto',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (widget.isEdicao)
                TextButton(
                  onPressed: _excluir,
                  child: const Text('Excluir produto',
                      style: TextStyle(color: IrisTheme.danger)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisualizadorDeFoto extends StatelessWidget {
  final String caminho;
  final String titulo;
  const _VisualizadorDeFoto({required this.caminho, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.file(
                    File(caminho),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: IrisTheme.textTertiary),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'trocar'),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Trocar foto'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'remover'),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remover'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: IrisTheme.danger,
                        side: const BorderSide(color: IrisTheme.danger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolhaDePreco extends StatefulWidget {
  final bool emSats;
  final double valorInicialBrl;
  final ExchangeRateService taxa;

  const _FolhaDePreco({
    required this.emSats,
    required this.valorInicialBrl,
    required this.taxa,
  });

  @override
  State<_FolhaDePreco> createState() => _FolhaDePrecoState();
}

class _FolhaDePrecoState extends State<_FolhaDePreco> {
  String _digitado = '';

  @override
  void initState() {
    super.initState();
    if (widget.valorInicialBrl > 0) {
      _digitado = widget.emSats
          ? widget.taxa.brlToSats(widget.valorInicialBrl).toString()
          : widget.valorInicialBrl.toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  double get _valorBrl {
    if (_digitado.isEmpty) return 0;
    if (widget.emSats) {
      final sats = int.tryParse(_digitado) ?? 0;
      return widget.taxa.satsToBrl(sats);
    }
    return double.tryParse(_digitado.replaceAll(',', '.')) ?? 0;
  }

  void _tecla(String t) {
    setState(() {
      if (t == ',') {
        if (widget.emSats || _digitado.contains(',')) return;
        if (_digitado.isEmpty) _digitado = '0';
        _digitado += ',';
        return;
      }

      final soDigitos = _digitado.replaceAll(RegExp(r'[^0-9]'), '');
      if (soDigitos.length >= 15) return;

      if (!widget.emSats && _digitado.contains(',')) {
        final decimais = _digitado.split(',').last;
        if (decimais.length >= 2) return;
      }
      _digitado += t;
    });
  }

  void _apagar() {
    setState(() {
      if (_digitado.isNotEmpty) {
        _digitado = _digitado.substring(0, _digitado.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unidade = widget.emSats ? 'SATS' : 'R\$';
    final equivalente = widget.emSats
        ? 'R\$ ${CurrencyFormatter.formatBrlCompact(_valorBrl)}'
        : CurrencyFormatter.formatBtcOrSats(widget.taxa.brlToSats(_valorBrl));

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: IrisTheme.bdr,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('Valor em $unidade',
              style: const TextStyle(
                  fontSize: 12, color: IrisTheme.textSecondary)),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              _digitado.isEmpty ? '0' : _digitado,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 34,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text('≈ $equivalente',
              style:
                  const TextStyle(fontSize: 12, color: IrisTheme.textTertiary)),
          const SizedBox(height: 16),
          Numpad(
            onKeyPress: _tecla,
            onBackspace: _apagar,
            showDecimal: !widget.emSats,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _valorBrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: IrisTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('Confirmar valor',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
