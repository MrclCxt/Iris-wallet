import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/esplora_servidores.dart';

class EsploraServersDialog extends StatefulWidget {
  const EsploraServersDialog({super.key});

  static Future<void> abrir(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const EsploraServersDialog(),
      );

  @override
  State<EsploraServersDialog> createState() => _EsploraServersDialogState();
}

class _EsploraServersDialogState extends State<EsploraServersDialog> {
  final _urlCtrl = TextEditingController();
  List<String> _proprios = [];
  final Map<String, String> _status = {};
  bool _testando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    EsploraServidores.personalizados().then((l) {
      if (mounted) setState(() => _proprios = [...l]);
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    final url = EsploraServidores.normalizar(_urlCtrl.text);
    if (!EsploraServidores.formatoValido(url)) {
      setState(() => _erro = 'Endereço inválido. Ex.: https://meu-servidor/api');
      return;
    }
    setState(() {
      _testando = true;
      _erro = null;
    });
    final motivo = await EsploraServidores.verificar(url);
    if (!mounted) return;
    if (motivo != null) {
      setState(() {
        _testando = false;
        _erro = 'Servidor $motivo. Não foi adicionado.';
      });
      return;
    }
    final nova = [url, ..._proprios.where((u) => u != url)];
    await EsploraServidores.salvarPersonalizados(nova);
    if (!mounted) return;
    setState(() {
      _proprios = nova;
      _status[url] = 'ok';
      _testando = false;
      _urlCtrl.clear();
    });
  }

  Future<void> _remover(String url) async {
    final nova = _proprios.where((u) => u != url).toList();
    await EsploraServidores.salvarPersonalizados(nova);
    if (mounted) setState(() => _proprios = nova);
  }

  Future<void> _testarTodos() async {
    setState(() => _testando = true);
    for (final url in [..._proprios, ...EsploraServidores.padrao]) {
      final motivo = await EsploraServidores.verificar(url);
      if (!mounted) return;
      setState(() => _status[url] = motivo ?? 'ok');
    }
    if (mounted) setState(() => _testando = false);
  }

  Widget _linha(String url, {required bool removivel}) {
    final st = _status[url];
    final cor = st == null
        ? IrisTheme.textTertiary
        : st == 'ok'
            ? Colors.greenAccent
            : Colors.redAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(url,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary, fontSize: 12)),
                if (st != null && st != 'ok')
                  Text(st,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
              ],
            ),
          ),
          if (removivel)
            IconButton(
              icon: const Icon(Icons.close,
                  size: 18, color: IrisTheme.textSecondary),
              tooltip: 'Remover',
              onPressed: () => _remover(url),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: IrisTheme.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: IrisTheme.bdr),
      ),
      title: const Text('Servidores de dados',
          style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O nó lê a blockchain por estes servidores (Esplora). Se um '
                'cair, o próximo assume sozinho. Os seus entram na frente.',
                style: TextStyle(
                    color: IrisTheme.textTertiary, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 12),
              if (_proprios.isNotEmpty) ...[
                const Text('Seus servidores',
                    style: TextStyle(
                        color: IrisTheme.textSecondary, fontSize: 12)),
                for (final u in _proprios) _linha(u, removivel: true),
                const SizedBox(height: 8),
              ],
              const Text('Padrão',
                  style:
                      TextStyle(color: IrisTheme.textSecondary, fontSize: 12)),
              for (final u in EsploraServidores.padrao)
                _linha(u, removivel: false),
              const SizedBox(height: 12),
              TextField(
                controller: _urlCtrl,
                enabled: !_testando,
                style:
                    const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Adicionar servidor',
                  hintText: 'https://meu-servidor/api',
                  labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                  hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                  filled: true,
                  fillColor: IrisTheme.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _adicionar(),
              ),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_erro!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
                ),
              const SizedBox(height: 8),
              const Text(
                'Antes de entrar, o servidor é testado: precisa estar na mesma '
                'rede da carteira. Vale no próximo desbloqueio.',
                style: TextStyle(
                    color: IrisTheme.textTertiary, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testando ? null : _testarTodos,
          child: const Text('Testar todos',
              style: TextStyle(color: IrisTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar',
              style: TextStyle(color: IrisTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _testando ? null : _adicionar,
          child: _testando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}
