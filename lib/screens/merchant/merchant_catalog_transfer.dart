import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../services/wallet_service.dart';

Future<void> showCatalogExportSheet(BuildContext context) async {
  final wallet = context.read<WalletService>();

  final total = wallet.merchantProducts.length;
  if (total == 0) {
    _aviso(context, 'Cadastre ao menos um produto antes de exportar.');
    return;
  }

  final String conteudo;
  try {
    conteudo = await wallet.exportMerchantCatalog();
  } catch (e) {
    if (context.mounted) {
      _aviso(context, 'Não foi possível exportar: $e', erro: true);
    }
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _Moldura(
      titulo: 'Exportar catálogo',
      children: [
        Text(
          '$total ${total == 1 ? 'produto' : 'produtos'} de "${wallet.merchantName ?? 'Minha Loja'}".',
          style: const TextStyle(fontSize: 13, color: IrisTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        const _NotaSeguranca(
          'O arquivo contém apenas nome, emoji e preço dos produtos. '
          'Seed, PIN, chave PIX e endereços de recebimento não são incluídos.',
        ),
        const SizedBox(height: 20),
        _Botao(
          icone: Icons.save_alt,
          rotulo: 'Baixar arquivo',
          principal: true,
          onTap: () async {
            Navigator.of(ctx).pop();
            await _baixarArquivo(context, conteudo, wallet.merchantName);
          },
        ),
        const SizedBox(height: 10),
        _Botao(
          icone: Icons.ios_share,
          rotulo: 'Compartilhar arquivo',
          onTap: () async {
            Navigator.of(ctx).pop();
            await _compartilharArquivo(context, conteudo, wallet.merchantName);
          },
        ),
        const SizedBox(height: 10),
        _Botao(
          icone: Icons.copy_all,
          rotulo: 'Copiar código',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: conteudo));
            if (ctx.mounted) Navigator.of(ctx).pop();

            if (!Platform.isAndroid && context.mounted) {
              _aviso(context, 'Catálogo copiado. Cole no outro aparelho.');
            }
          },
        ),
      ],
    ),
  );
}

String _nomeArquivo(String? nomeLoja) {
  final slug = (nomeLoja ?? 'loja')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'catalogo-${slug.isEmpty ? 'loja' : slug}.json';
}

Future<void> _baixarArquivo(
    BuildContext context, String conteudo, String? nomeLoja) async {
  try {
    final bytes = Uint8List.fromList(utf8.encode(conteudo));
    final caminho = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar catálogo',
      fileName: _nomeArquivo(nomeLoja),
      bytes: bytes,
    );
    if (caminho == null) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(caminho).writeAsBytes(bytes);
    }
    if (context.mounted) _aviso(context, 'Catálogo salvo em $caminho');
  } catch (e) {
    if (context.mounted) {
      _aviso(context, 'Falha ao salvar o arquivo: $e', erro: true);
    }
  }
}

Future<void> _compartilharArquivo(
    BuildContext context, String conteudo, String? nomeLoja) async {
  try {
    final dir = await getTemporaryDirectory();
    final arquivo = File('${dir.path}/${_nomeArquivo(nomeLoja)}');
    await arquivo.writeAsString(conteudo);
    await Share.shareXFiles([XFile(arquivo.path)],
        subject: 'Catálogo Iris — ${nomeLoja ?? 'Minha Loja'}');
  } catch (e) {
    if (context.mounted) {
      _aviso(context, 'Falha ao compartilhar o arquivo: $e', erro: true);
    }
  }
}

Future<void> showCatalogImportDialog(BuildContext context) async {
  final wallet = context.read<WalletService>();
  final controlador = TextEditingController();
  final jaTemProdutos = wallet.merchantProducts.isNotEmpty;

  var substituir = false;
  var importando = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => _Moldura(
        titulo: 'Importar catálogo',
        children: [
          const Text(
            'Escolha o arquivo .json que você baixou, ou cole o código copiado '
            'do outro aparelho.',
            style: TextStyle(
                fontSize: 13, color: IrisTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          _Botao(
            icone: Icons.folder_open,
            rotulo: 'Escolher arquivo',
            principal: true,
            onTap: () async {
              final texto = await _lerArquivoEscolhido(ctx);
              if (texto != null) {
                controlador.text = texto;
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: Divider(color: IrisTheme.bdr)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('ou cole o código',
                    style:
                        TextStyle(fontSize: 11, color: IrisTheme.textTertiary)),
              ),
              Expanded(child: Divider(color: IrisTheme.bdr)),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controlador,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: '{ "iris_catalog": 1, ... }',
              hintStyle:
                  const TextStyle(color: IrisTheme.textTertiary, fontSize: 12),
              filled: true,
              fillColor: IrisTheme.s2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: IrisTheme.bdr),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: IrisTheme.bdr),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Botao(
            icone: Icons.content_paste,
            rotulo: 'Colar da área de transferência',
            onTap: () async {
              final dados = await Clipboard.getData('text/plain');
              if (dados?.text != null && dados!.text!.isNotEmpty) {
                controlador.text = dados.text!;
                setState(() {});
              }
            },
          ),
          if (jaTemProdutos) ...[
            const SizedBox(height: 18),
            const Text('Esta loja já tem produtos:',
                style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
            const SizedBox(height: 8),
            _Opcao(
              selecionado: !substituir,
              titulo: 'Mesclar',
              detalhe: 'Mantém os atuais e acrescenta os do arquivo.',
              onTap: () => setState(() => substituir = false),
            ),
            const SizedBox(height: 8),
            _Opcao(
              selecionado: substituir,
              titulo: 'Substituir',
              detalhe: 'Apaga o catálogo atual desta loja.',
              perigo: true,
              onTap: () => setState(() => substituir = true),
            ),
          ],
          const SizedBox(height: 18),
          const _NotaSeguranca(
            'Só nomes e preços são importados. Os QR Codes de cobrança são '
            'gerados com a carteira DESTE aparelho — o dinheiro cai aqui.',
          ),
          const SizedBox(height: 18),
          _Botao(
            icone: Icons.download,
            rotulo: importando ? 'Importando...' : 'Importar',
            principal: true,
            onTap: importando
                ? null
                : () async {
                    setState(() => importando = true);
                    try {
                      final r = await wallet.importMerchantCatalog(
                        controlador.text,
                        substituir: substituir,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) _aviso(context, _resumo(r));
                    } catch (e) {
                      setState(() => importando = false);
                      if (ctx.mounted) {
                        _aviso(ctx, _mensagemDeErro(e), erro: true);
                      }
                    }
                  },
          ),
        ],
      ),
    ),
  );
}

Future<String?> _lerArquivoEscolhido(BuildContext context) async {
  try {
    final resultado = await FilePicker.platform.pickFiles(withData: true);
    if (resultado == null || resultado.files.isEmpty) return null;
    final escolhido = resultado.files.first;

    const limiteBytes = 2 * 1024 * 1024;
    if (escolhido.size > limiteBytes) {
      if (context.mounted) {
        _aviso(context, 'Arquivo grande demais para ser um catálogo.',
            erro: true);
      }
      return null;
    }

    var bytes = escolhido.bytes;
    if (bytes == null && escolhido.path != null) {
      bytes = await File(escolhido.path!).readAsBytes();
    }
    if (bytes == null) {
      if (context.mounted) {
        _aviso(context, 'Não foi possível ler o arquivo escolhido.',
            erro: true);
      }
      return null;
    }

    try {
      return utf8.decode(bytes);
    } catch (_) {
      if (context.mounted) {
        _aviso(context, 'Esse arquivo não é um catálogo em texto.', erro: true);
      }
      return null;
    }
  } catch (e) {
    if (context.mounted) {
      _aviso(context, 'Falha ao abrir o arquivo: $e', erro: true);
    }
    return null;
  }
}

String _resumo(CatalogImportResult r) {
  final partes = <String>[];
  if (r.adicionados > 0) partes.add('${r.adicionados} adicionado(s)');
  if (r.atualizados > 0) partes.add('${r.atualizados} atualizado(s)');
  if (r.ignorados > 0) {
    partes.add('${r.ignorados} ignorado(s) por dado inválido');
  }
  return partes.isEmpty
      ? 'Nada a importar.'
      : 'Catálogo importado: ${partes.join(', ')}.';
}

String _mensagemDeErro(Object e) {
  if (e is FormatException) return e.message;
  if (e is StateError) return e.message;
  return 'Não foi possível importar: $e';
}

void _aviso(BuildContext context, String mensagem, {bool erro = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensagem),
      backgroundColor: erro ? IrisTheme.danger : IrisTheme.s3,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: erro ? 5 : 3),
    ),
  );
}

class _Moldura extends StatelessWidget {
  final String titulo;
  final List<Widget> children;
  const _Moldura({required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: IrisTheme.s1,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _NotaSeguranca extends StatelessWidget {
  final String texto;
  const _NotaSeguranca(this.texto);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IrisTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IrisTheme.success.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 16, color: IrisTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: IrisTheme.textSecondary,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Botao extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final bool principal;
  final VoidCallback? onTap;
  const _Botao({
    required this.icone,
    required this.rotulo,
    required this.onTap,
    this.principal = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: principal
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icone, size: 18),
              label: Text(rotulo),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icone, size: 18),
              label: Text(rotulo),
              style: OutlinedButton.styleFrom(
                foregroundColor: IrisTheme.textPrimary,
                side: const BorderSide(color: IrisTheme.bdr),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
    );
  }
}

class _Opcao extends StatelessWidget {
  final bool selecionado;
  final String titulo;
  final String detalhe;
  final bool perigo;
  final VoidCallback onTap;
  const _Opcao({
    required this.selecionado,
    required this.titulo,
    required this.detalhe,
    required this.onTap,
    this.perigo = false,
  });

  @override
  Widget build(BuildContext context) {
    final cor = perigo ? IrisTheme.danger : IrisTheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selecionado ? cor.withOpacity(0.10) : IrisTheme.s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selecionado ? cor : IrisTheme.bdr),
        ),
        child: Row(
          children: [
            Icon(
              selecionado ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selecionado ? cor : IrisTheme.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(detalhe,
                      style: const TextStyle(
                          fontSize: 11, color: IrisTheme.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
