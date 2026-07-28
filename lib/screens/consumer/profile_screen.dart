import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';
import '../../services/avatar_image_store.dart';
import '../../widgets/max_width_container.dart';
import '../../widgets/iris_widgets.dart';
import '../../widgets/account_avatar.dart';
import '../pin_screen.dart';
import '../merchant/product_image_editor.dart';
import 'profile_transfer.dart';

/// Perfil editável: foto (do dispositivo), cor de destaque, nome, contas e
/// backup. Tudo salva sozinho — sem botão "Salvar". Com foto, ela é sempre o
/// ícone da conta; sem foto, o ícone do app é o que aparece.
class ProfileScreen extends StatefulWidget {
  final bool isMerchant;
  const ProfileScreen({super.key, this.isMerchant = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const List<String> _colors = [
    '#F7931A',
    '#3B82F6',
    '#22C55E',
    '#A855F7',
    '#EF4444',
    '#EAB308',
    '#14B8A6',
    '#EC4899'
  ];

  final _nameCtrl = TextEditingController();
  String? _color;
  Uint8List? _avatarBytes; // preview: foto atual, quando existe
  bool _pickingImage = false;
  bool _loaded = false;
  bool _justSaved = false;
  Timer? _nameDebounce;
  Timer? _savedFlashTimer;

  String? get _accountId {
    final wallet = context.read<WalletService>();
    final p = widget.isMerchant ? wallet.activeMerchant : wallet.activeConsumer;
    return p?.id;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final wallet = context.read<WalletService>();
    final p = widget.isMerchant ? wallet.activeMerchant : wallet.activeConsumer;
    _nameCtrl.text = p?.name ?? '';
    _color = p?.avatarColor;
    _loaded = true;

    final id = p?.id;
    if (id != null && AvatarImageStore.existe(id)) {
      final bytes = await AvatarImageStore.lerBytes(id);
      if (mounted) setState(() => _avatarBytes = bytes);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _savedFlashTimer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  // --- Autosave (nome, cor) ---

  void _flashSaved() {
    if (!mounted) return;
    setState(() => _justSaved = true);
    _savedFlashTimer?.cancel();
    _savedFlashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _justSaved = false);
    });
  }

  Future<void> _persistNow() async {
    await context.read<WalletService>().updateActiveProfile(
          isMerchant: widget.isMerchant,
          name: _nameCtrl.text,
          avatarColor: _color ?? '',
        );
    _flashSaved();
  }

  void _onNameChanged(String _) {
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 600), _persistNow);
  }

  /// Garante que uma edição de nome ainda não salva (debounce pendente) não se
  /// perca ao sair da tela.
  Future<void> _flushPendingSave() async {
    if (_nameDebounce?.isActive ?? false) {
      _nameDebounce!.cancel();
      await _persistNow();
    }
  }

  void _pickColor(String c) {
    setState(() => _color = c);
    _persistNow();
  }

  // --- Foto (do dispositivo) — único ícone da conta quando existe ---

  /// O avatar tem nome de arquivo fixo por conta (AvatarImageStore): sem isto,
  /// widgets que usam `Image.file` no resto do app (cabeçalho da tela
  /// inicial, seletor de contas) continuariam mostrando a imagem antiga em
  /// cache do Flutter depois de trocar/remover a foto.
  Future<void> _evictCache(String id) async {
    final caminho = AvatarImageStore.caminhoDe(id);
    if (caminho == null) return;
    await FileImage(File(caminho)).evict();
  }

  Future<void> _pickImage() async {
    final id = _accountId;
    if (id == null) return;
    setState(() => _pickingImage = true);
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
      if (enquadrada == null) return; // cancelou o enquadramento

      final ok = await AvatarImageStore.salvar(id, enquadrada);
      if (!ok) {
        _mostrarErro('Não foi possível guardar a foto.');
        return;
      }
      await _evictCache(id);
      if (mounted) {
        setState(() => _avatarBytes = enquadrada);
        _flashSaved();
      }
    } catch (e) {
      _mostrarErro('Falha ao carregar a imagem: $e');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _removeImage() async {
    final id = _accountId;
    if (id == null) return;
    await AvatarImageStore.remover(id);
    await _evictCache(id);
    if (mounted) {
      setState(() => _avatarBytes = null);
      _flashSaved();
    }
  }

  void _mostrarErro(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: IrisTheme.danger),
    );
  }

  // --- Trocar de conta/loja ---

  void _showAccountSwitcher(BuildContext context) {
    final wallet = context.read<WalletService>();
    final accounts =
        widget.isMerchant ? wallet.merchantAccounts : wallet.consumerAccounts;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: IrisTheme.bg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      widget.isMerchant
                          ? 'Minhas Lojas'
                          : 'Minhas Carteiras Pessoais',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: IrisTheme.textPrimary)),
                  const SizedBox(height: 16),
                  ...accounts.map((acc) {
                    final activeId = widget.isMerchant
                        ? wallet.activeMerchant?.id
                        : wallet.activeConsumer?.id;
                    final isActive = acc.id == activeId;
                    return ListTile(
                      leading: AvatarCircle(
                          accountId: acc.id,
                          colorHex: acc.avatarColor,
                          size: 32),
                      title: Text(acc.name,
                          style: TextStyle(
                              color: isActive
                                  ? IrisTheme.primary
                                  : IrisTheme.textPrimary,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      trailing: isActive
                          ? const Icon(Icons.check, color: IrisTheme.primary)
                          : null,
                      onTap: () async {
                        if (isActive) return;
                        Navigator.pop(context); // fecha o diálogo
                        if (widget.isMerchant) {
                          await wallet.switchMerchantAccount(acc.id);
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PinScreen(
                                    mode: PinMode.unlock, isMerchant: true),
                              ),
                            );
                          }
                        } else {
                          await wallet.switchConsumerAccount(acc.id);
                          if (context.mounted) {
                            Navigator.pushNamedAndRemoveUntil(
                                context, '/unlock', (route) => false);
                          }
                        }
                      },
                    );
                  }),
                  const Divider(color: IrisTheme.bdr),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline,
                        color: IrisTheme.textPrimary),
                    title: Text(
                        widget.isMerchant
                            ? 'Adicionar nova loja'
                            : 'Adicionar nova carteira',
                        style: const TextStyle(
                            color: IrisTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(context);
                      if (widget.isMerchant) {
                        Navigator.pushNamed(context, '/merchant_setup');
                      } else {
                        // A semente é gerada na tela seguinte, depois da escolha do tamanho.
                        Navigator.pushNamed(context, '/seed_gen');
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Criar nova conta/loja (confirmação) ---

  void _handleCreateNew(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: IrisTheme.bdr)),
        title: Text(
            widget.isMerchant ? 'Criar Nova Loja?' : 'Criar Nova Conta?',
            style: const TextStyle(color: IrisTheme.primary)),
        content: Text(
          widget.isMerchant
              ? 'Isso criará uma nova loja independente. Você poderá alternar '
                  'entre suas lojas pelo menu Trocar de Loja.'
              : 'Isso criará um novo perfil independente. Você poderá alternar '
                  'entre suas contas pelo menu de Trocar de Conta.',
          style: const TextStyle(color: IrisTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: IrisTheme.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: IrisTheme.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              if (widget.isMerchant) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/merchant_setup', (route) => false);
              } else {
                Navigator.pop(context); // fecha o diálogo
                Navigator.pushNamed(context, '/welcome');
              }
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: IrisTheme.bg,
        body:
            Center(child: CircularProgressIndicator(color: IrisTheme.primary)),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushPendingSave();
      },
      child: Scaffold(
        backgroundColor: IrisTheme.bg,
        appBar: AppBar(
          backgroundColor: IrisTheme.bg,
          elevation: 0,
          title: Text(widget.isMerchant ? 'Perfil da loja' : 'Perfil',
              style:
                  const TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
          iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
          actions: [
            AnimatedOpacity(
              opacity: _justSaved ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: IrisTheme.success, size: 16),
                    SizedBox(width: 4),
                    Text('Salvo',
                        style:
                            TextStyle(color: IrisTheme.success, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: MaxWidthContainer(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: _avatarPreview()),
                  const SizedBox(height: 12),
                  Center(child: _avatarActions()),
                  const SizedBox(height: 28),
                  _label('Nome'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    onChanged: _onNameChanged,
                    style: const TextStyle(
                        color: IrisTheme.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: widget.isMerchant
                          ? 'Nome da loja'
                          : 'Nome da carteira',
                    ),
                  ),
                  const SizedBox(height: 24),
                  _label('Cor de destaque'),
                  const SizedBox(height: 8),
                  _hint('Aparece como o anel ao redor da sua foto.'),
                  const SizedBox(height: 8),
                  _colorPicker(),
                  const SizedBox(height: 28),
                  const Divider(color: IrisTheme.bdr),
                  const SizedBox(height: 16),
                  _label(widget.isMerchant ? 'Lojas' : 'Contas'),
                  const SizedBox(height: 12),
                  _actionTile(
                    icon: Icons.switch_account,
                    title: widget.isMerchant
                        ? 'Trocar de Loja'
                        : 'Trocar de Conta',
                    subtitle: widget.isMerchant
                        ? 'Alternar entre perfis de lojas'
                        : 'Alternar entre carteiras',
                    onTap: () => _showAccountSwitcher(context),
                  ),
                  const SizedBox(height: 12),
                  _actionTile(
                    icon: widget.isMerchant
                        ? Icons.add_business
                        : Icons.person_add,
                    title: widget.isMerchant
                        ? 'Criar Nova Loja'
                        : 'Criar Nova Conta',
                    subtitle: widget.isMerchant
                        ? 'Cria uma nova loja independente'
                        : 'Cria uma nova carteira independente',
                    onTap: () => _handleCreateNew(context),
                  ),
                  const SizedBox(height: 28),
                  const Divider(color: IrisTheme.bdr),
                  const SizedBox(height: 16),
                  _label('Backup'),
                  const SizedBox(height: 12),
                  _actionTile(
                    icon: Icons.ios_share,
                    title: 'Exportar perfil',
                    subtitle:
                        'Leve nome, foto e preferências para outro aparelho',
                    onTap: () => showProfileExportSheet(context,
                        isMerchant: widget.isMerchant),
                  ),
                  const SizedBox(height: 12),
                  _actionTile(
                    icon: Icons.download,
                    title: 'Importar perfil',
                    subtitle: 'Aplica um backup exportado a esta conta',
                    onTap: () => showProfileImportDialog(context,
                        isMerchant: widget.isMerchant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarPreview() {
    Widget conteudo;
    if (_avatarBytes != null) {
      conteudo = Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _hex(_color), width: 2),
        ),
        child: ClipOval(
          child: Image.memory(_avatarBytes!,
              width: 88, height: 88, fit: BoxFit.cover),
        ),
      );
    } else {
      // Sem foto: o ícone do app — igual ao que aparece no resto do app.
      conteudo = const IrisLogo(size: 88);
    }

    return Stack(
      children: [
        conteudo,
        if (_pickingImage)
          const Positioned.fill(
            child: DecoratedBox(
              decoration:
                  BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatarActions() {
    return Wrap(
      spacing: 10,
      alignment: WrapAlignment.center,
      children: [
        TextButton.icon(
          onPressed: _pickingImage ? null : _pickImage,
          icon: const Icon(Icons.photo_camera_outlined, size: 16),
          label: Text(_avatarBytes == null ? 'Escolher foto' : 'Trocar foto'),
        ),
        if (_avatarBytes != null)
          TextButton.icon(
            onPressed: _pickingImage ? null : _removeImage,
            icon: const Icon(Icons.delete_outline,
                size: 16, color: IrisTheme.danger),
            label: const Text('Remover foto',
                style: TextStyle(color: IrisTheme.danger)),
          ),
      ],
    );
  }

  Color _hex(String? h) {
    if (h == null || !h.startsWith('#') || h.length != 7) {
      return IrisTheme.bdr2;
    }
    return Color(int.parse('FF${h.substring(1)}', radix: 16));
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          color: IrisTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700));

  Widget _hint(String t) => Text(t,
      style: const TextStyle(
          color: IrisTheme.textTertiary, fontSize: 11, height: 1.4));

  Widget _colorPicker() => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _colors.map((c) {
          final selected = _color == c;
          return InkWell(
            onTap: () => _pickColor(c),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _hex(c),
                shape: BoxShape.circle,
                border: Border.all(
                    color:
                        selected ? IrisTheme.textPrimary : Colors.transparent,
                    width: 3),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
          );
        }).toList(),
      );

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: IrisTheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: IrisTheme.bdr),
        ),
        child: Row(
          children: [
            Icon(icon, color: IrisTheme.primary, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: IrisTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: IrisTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: IrisTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}
