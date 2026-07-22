import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../../core/theme.dart';

/// Editor da foto do produto: gira em passos de 90° e permite arrastar e dar
/// zoom até enquadrar no 1:1 usado na exibição.
///
/// Devolve os bytes JPEG já recortados no quadrado, ou null se cancelar.
Future<Uint8List?> abrirEditorDeFoto(
  BuildContext context,
  Uint8List bytesOriginais,
) async {
  // Só para saber a proporção da imagem; o recorte final sai do que aparece
  // na tela, não desta decodificação.
  final decodificada = img.decodeImage(bytesOriginais);
  if (decodificada == null) return null;

  if (!context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _EditorDeFoto(
        bytes: bytesOriginais,
        larguraOriginal: decodificada.width,
        alturaOriginal: decodificada.height,
      ),
    ),
  );
}

class _EditorDeFoto extends StatefulWidget {
  final Uint8List bytes;
  final int larguraOriginal;
  final int alturaOriginal;

  const _EditorDeFoto({
    required this.bytes,
    required this.larguraOriginal,
    required this.alturaOriginal,
  });

  @override
  State<_EditorDeFoto> createState() => _EditorDeFotoState();
}

class _EditorDeFotoState extends State<_EditorDeFoto> {
  final GlobalKey _quadroKey = GlobalKey();
  final TransformationController _transformacao = TransformationController();

  /// Giros de 90° no sentido horário.
  int _giros = 0;
  bool _processando = false;

  /// Lado do recorte na imagem final. Fixo para o arquivo não variar conforme
  /// o tamanho da tela do aparelho.
  static const double _ladoDeSaida = 1440;

  @override
  void dispose() {
    _transformacao.dispose();
    super.dispose();
  }

  void _girar(int passo) {
    setState(() {
      _giros = (_giros + passo) % 4;
      if (_giros < 0) _giros += 4;
      // O enquadramento anterior não faz sentido na nova orientação.
      _transformacao.value = Matrix4.identity();
    });
  }

  /// Dimensões do widget da imagem dentro do quadro: a proporção é preservada
  /// e o menor lado cobre o quadro, de modo que sempre haja imagem em toda a
  /// área 1:1 e sobre margem para arrastar no lado maior.
  Size _tamanhoNoQuadro(double lado) {
    final girado = _giros.isOdd;
    final w = girado ? widget.alturaOriginal : widget.larguraOriginal;
    final h = girado ? widget.larguraOriginal : widget.alturaOriginal;
    if (w <= 0 || h <= 0) return Size(lado, lado);

    final proporcao = w / h;
    return proporcao >= 1
        ? Size(lado * proporcao, lado) // paisagem: sobra na horizontal
        : Size(lado, lado / proporcao); // retrato: sobra na vertical
  }

  Future<void> _confirmar() async {
    setState(() => _processando = true);
    try {
      final limite =
          _quadroKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (limite == null) {
        Navigator.pop(context);
        return;
      }

      // Captura exatamente o que está enquadrado. Fazer o recorte pela captura
      // evita refazer à mão a matemática do zoom/arrasto e garante que o
      // resultado seja igual ao que o lojista viu.
      final ladoNaTela = limite.size.width;
      final escala = ladoNaTela > 0 ? _ladoDeSaida / ladoNaTela : 1.0;
      final imagem = await limite.toImage(pixelRatio: escala);
      final png = await imagem.toByteData(format: ui.ImageByteFormat.png);
      imagem.dispose();
      if (png == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      // PNG de foto fica enorme; reencoda em JPEG de alta qualidade.
      final recortada = img.decodeImage(png.buffer.asUint8List());
      if (recortada == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final saida = Uint8List.fromList(img.encodeJpg(recortada, quality: 92));

      if (mounted) Navigator.pop(context, saida);
    } catch (e) {
      debugPrint('Editor de foto: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Enquadrar foto',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final lado = [
                      constraints.maxWidth - 24,
                      constraints.maxHeight - 24,
                    ].reduce((a, b) => a < b ? a : b);
                    final tamanho = _tamanhoNoQuadro(lado);

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: lado,
                        height: lado,
                        child: RepaintBoundary(
                          key: _quadroKey,
                          child: Container(
                            color: Colors.black,
                            child: InteractiveViewer(
                              transformationController: _transformacao,
                              // constrained: false deixa a imagem maior que o
                              // quadro, então dá para arrastar e escolher a
                              // parte que aparece mesmo sem zoom.
                              constrained: false,
                              minScale: 1,
                              maxScale: 6,
                              child: SizedBox(
                                width: tamanho.width,
                                height: tamanho.height,
                                child: RotatedBox(
                                  quarterTurns: _giros,
                                  child: Image.memory(
                                    widget.bytes,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Arraste e use dois dedos para o zoom. O que estiver no quadro '
                'é o que será salvo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BotaoDeGiro(
                    icone: Icons.rotate_left,
                    rotulo: 'Girar',
                    onTap: _processando ? null : () => _girar(-1),
                  ),
                  const SizedBox(width: 16),
                  _BotaoDeGiro(
                    icone: Icons.rotate_right,
                    rotulo: 'Girar',
                    onTap: _processando ? null : () => _girar(1),
                  ),
                  const SizedBox(width: 16),
                  _BotaoDeGiro(
                    icone: Icons.restart_alt,
                    rotulo: 'Reiniciar',
                    onTap: _processando
                        ? null
                        : () => setState(() {
                              _giros = 0;
                              _transformacao.value = Matrix4.identity();
                            }),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _processando ? null : _confirmar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: IrisTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(
                    _processando ? 'Processando...' : 'Usar esta foto',
                    style: const TextStyle(color: Colors.white),
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

class _BotaoDeGiro extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final VoidCallback? onTap;
  const _BotaoDeGiro({required this.icone, required this.rotulo, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icone, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white10,
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 2),
        Text(rotulo,
            style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }
}
