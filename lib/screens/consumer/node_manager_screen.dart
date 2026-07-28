import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import '../../services/wallet_service.dart';
import '../../services/node_backend.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../widgets/tx_status.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';

/// Cache em memória dos últimos dados do nó, para reabrir a tela sem spinner
/// de tela cheia (a busca real hita o nó e pode demorar). Vive enquanto o app
/// vive; não é dado sensível (endereço público, saldo, canais).
class _NodeCache {
  static bool hasData = false;
  static int onChainBalance = 0;
  static String onChainAddress = '';
  static List<ChannelSummary> channels = [];
  static String myNodeId = '';
  static List<String> localIps = [];
}

class NodeManagerScreen extends StatefulWidget {
  const NodeManagerScreen({super.key});

  @override
  State<NodeManagerScreen> createState() => _NodeManagerScreenState();
}

class _NodeManagerScreenState extends State<NodeManagerScreen> {
  int _onChainBalance = 0;
  String _onChainAddress = '';
  List<ChannelSummary> _channels = [];
  String _myNodeId = '';
  List<String> _localIps = [];
  bool _isLoading = true;
  bool _deepScanRodando = false;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    // Mostra os últimos dados carregados na hora (sem spinner de tela cheia),
    // e atualiza em segundo plano — reabrir a tela deixa de "travar".
    if (_NodeCache.hasData) {
      _onChainAddress = _NodeCache.onChainAddress;
      _onChainBalance = _NodeCache.onChainBalance;
      _channels = _NodeCache.channels;
      _myNodeId = _NodeCache.myNodeId;
      _localIps = _NodeCache.localIps;
      _isLoading = false;
    }
    _loadNodeData();
    // Atualização periódica mais espaçada — 30s deixava a tela "sempre
    // atualizando"; 90s é suficiente para saldo/canais on-chain.
    _syncTimer =
        Timer.periodic(const Duration(seconds: 90), (_) => _syncNode());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNodeData() async {
    // Só bloqueia com spinner se ainda não há nada em cache para mostrar.
    if (!_NodeCache.hasData && mounted) setState(() => _isLoading = true);
    try {
      final wallet = context.read<WalletService>();
      final address = await wallet.getOnchainAddress();
      final balance = await wallet.getOnchainBalance();
      final channels = await wallet.getChannels();
      String nodeId = '';
      try {
        nodeId = await wallet.getMyNodeId();
      } catch (e) {
        debugPrint('getMyNodeId: $e');
      }
      final localIps = await wallet.getLocalNetworkAddresses();

      _NodeCache.onChainAddress = address;
      _NodeCache.onChainBalance = balance;
      _NodeCache.channels = channels;
      _NodeCache.myNodeId = nodeId;
      _NodeCache.localIps = localIps;
      _NodeCache.hasData = true;

      if (!mounted) return;
      setState(() {
        _onChainAddress = address;
        _onChainBalance = balance;
        _channels = channels;
        _myNodeId = nodeId;
        _localIps = localIps;
      });
    } catch (e) {
      debugPrint('Failed to load node data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncNode() async {
    try {
      await context.read<WalletService>().syncNode();
      await _loadNodeData();
    } catch (e) {
      debugPrint('Failed to sync node: $e');
    }
  }

  void _showOpenChannelDialog() {
    final pubkeyCtrl = TextEditingController();
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9735');
    final amountCtrl = TextEditingController();
    bool isOpening = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: IrisTheme.s1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (context, setStateModal) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Abrir Novo Canal',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: IrisTheme.textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: pubkeyCtrl,
                style: const TextStyle(color: IrisTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Node PubKey (Hex)',
                  labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                  filled: true,
                  fillColor: IrisTheme.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: hostCtrl,
                      style: const TextStyle(color: IrisTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Host (IP ou Tor)',
                        labelStyle:
                            const TextStyle(color: IrisTheme.textSecondary),
                        filled: true,
                        fillColor: IrisTheme.bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: IrisTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Porta',
                        labelStyle:
                            const TextStyle(color: IrisTheme.textSecondary),
                        filled: true,
                        fillColor: IrisTheme.bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: IrisTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Capacidade do Canal (Sats)',
                  labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                  filled: true,
                  fillColor: IrisTheme.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  helperText:
                      'Saldo disponível: $_onChainBalance sats · mínimo 5.000 sats',
                  helperStyle: const TextStyle(color: IrisTheme.primary),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isOpening
                    ? null
                    : () async {
                        try {
                          setStateModal(() => isOpening = true);
                          final sats = int.tryParse(amountCtrl.text) ?? 0;
                          // Não é limite do protocolo Lightning (o LDK não
                          // impõe um mínimo alto) — é só uma margem de
                          // segurança do app para o canal não nascer perto
                          // demais do limite de "dust"/reserva e virar
                          // praticamente inutilizável.
                          if (sats < 5000) {
                            throw Exception('Capacidade mínima é 5.000 sats');
                          }

                          await context.read<WalletService>().openChannel(
                                pubKeyHex: pubkeyCtrl.text.trim(),
                                host: hostCtrl.text.trim(),
                                port: int.parse(portCtrl.text.trim()),
                                amountSats: sats,
                              );

                          // Abrir canal é demorado: a tela pode ter saído.
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Sinal de abertura de canal enviado! Aguarde a confirmação on-chain.'),
                                backgroundColor: IrisTheme.success),
                          );
                          _loadNodeData();
                        } catch (e) {
                          if (!mounted) return;
                          setStateModal(() => isOpening = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Erro: $e'),
                                backgroundColor: IrisTheme.danger),
                          );
                        }
                      },
                child: isOpening
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Solicitar Abertura de Canal'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  /// Configuração do backend: nó embarcado (padrão) ou daemon local
  /// iris-noded via REST em 127.0.0.1 (arquitetura híbrida A+B).
  void _showBackendDialog() {
    final wallet = context.read<WalletService>();
    final urlCtrl = TextEditingController(text: wallet.consumerDaemonUrl ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: IrisTheme.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: IrisTheme.bdr),
        ),
        title: const Text('Backend do nó',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modo atual: ${wallet.isConsumerNodeRemote ? 'Daemon local (RPC)' : 'Embarcado (FFI)'}',
              style:
                  const TextStyle(color: IrisTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style:
                  const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'URL do daemon (vazio = embarcado)',
                hintText: 'http://127.0.0.1:8380',
                labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                filled: true,
                fillColor: IrisTheme.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O daemon (iris-noded) roda o nó como serviço neste dispositivo, sempre em 127.0.0.1. A mudança vale no próximo desbloqueio.',
              style: TextStyle(
                  color: IrisTheme.textTertiary, fontSize: 11, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: IrisTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await wallet.setDaemonUrl(urlCtrl.text, forMerchant: false);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Backend salvo. Bloqueie e desbloqueie a carteira para aplicar.')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncDegraded = context.watch<WalletService>().nodeSyncDegraded;
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.s1,
        title: const Text('Carteira Bitcoin e Canais ⚡',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 18)),
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4.0),
            child: Center(child: CurrencyToggleBtn()),
          ),
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Backend do nó (embarcado ou daemon local)',
            onPressed: _showBackendDialog,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar Nós',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Sincronizando nó com a Testnet4...')));
              _syncNode();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _syncNode,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (syncDegraded) ...[
                    _buildSyncDegradedBanner(),
                    const SizedBox(height: 16),
                  ],
                  _buildNodeIdentityCard(),
                  const SizedBox(height: 16),
                  if (!kIsWeb && Platform.isAndroid) ...[
                    _buildBackgroundServiceCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildOnChainSection(),
                  const SizedBox(height: 24),
                  _buildChannelsSection(),
                ],
              ),
            ),
    );
  }

  /// Só Android: liga/desliga o serviço em primeiro plano que impede o
  /// sistema de suspender o app quando ele é minimizado — sem isso, o nó
  /// para de sincronizar assim que o app sai da tela. Opt-in (mostra uma
  /// notificação persistente).
  /// A "identidade" do nó deste dispositivo: a chave pública (Node ID) que
  /// OUTRO dispositivo precisa saber para se conectar a ele e abrir um canal.
  /// Sem isto visível, não tem como dois dispositivos se acharem na rede —
  /// era exatamente a peça que faltava antes desta tela.
  /// Recupera saldo parado em endereços de índice alto — o caso de quem
  /// recebeu num endereço antigo e depois teve a carteira recriada do zero.
  Widget _buildDeepScanCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.travel_explore, size: 18, color: IrisTheme.primary),
              SizedBox(width: 8),
              Text('Não achou um saldo que você recebeu?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: IrisTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'A varredura profunda procura em endereços mais antigos da sua '
            'carteira. Use se você recebeu num endereço que o app não mostra '
            'mais. Sua frase semente não muda.',
            style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deepScanRodando ? null : _rodarVarreduraProfunda,
              icon: _deepScanRodando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, size: 18),
              label: Text(_deepScanRodando
                  ? 'Procurando…'
                  : 'Fazer varredura profunda'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: IrisTheme.bdr2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rodarVarreduraProfunda() async {
    setState(() => _deepScanRodando = true);
    final wallet = context.read<WalletService>();
    final antes = wallet.consumerOnchainSats;
    try {
      await wallet.deepScan();
      final depois = wallet.consumerOnchainSats;
      if (!mounted) return;
      final achou = depois > antes;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(achou
            ? 'Encontrado! ${depois - antes} sats a mais no seu saldo.'
            : 'Nenhum saldo novo encontrado nos endereços antigos.'),
      ));
      await _loadNodeData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha na varredura: $e')));
    } finally {
      if (mounted) setState(() => _deepScanRodando = false);
    }
  }

  Widget _buildNodeIdentityCard() {
    const port = 9735; // porta do nó pessoal (a loja usa 9736)
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fingerprint, color: IrisTheme.primary, size: 20),
              SizedBox(width: 8),
              Text('Identidade deste nó',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: IrisTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          _copyableRow(
            label: 'Node ID',
            value: _myNodeId.isEmpty ? 'Indisponível' : _myNodeId,
          ),
          const SizedBox(height: 8),
          if (_localIps.isNotEmpty)
            _copyableRow(
              label: 'Endereço na rede local',
              value: '${_localIps.first}:$port',
            ),
        ],
      ),
    );
  }

  Widget _copyableRow(
      {required String label, required String value, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: IrisTheme.textSecondary)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: IrisTheme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy,
                  size: 16, color: IrisTheme.textTertiary),
              tooltip: 'Copiar',
              onPressed: value.isEmpty || value.contains('Indisponível')
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$label copiado')),
                      );
                    },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint,
              style:
                  const TextStyle(fontSize: 10, color: IrisTheme.textTertiary)),
        ],
      ],
    );
  }

  Widget _buildBackgroundServiceCard() {
    final wallet = context.watch<WalletService>();
    final enabled = wallet.keepNodeAliveInBackground;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_alt, color: IrisTheme.primary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manter nó ativo em segundo plano',
                    style: TextStyle(
                        color: IrisTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeColor: IrisTheme.primary,
            onChanged: (v) => wallet.setKeepNodeAliveInBackground(v),
          ),
        ],
      ),
    );
  }

  /// Aparece quando o backend Esplora escolhido no boot do nó parou de
  /// responder bem (ex.: rate-limit) — o app já está tentando se recuperar
  /// sozinho (reiniciando o nó para escolher outro backend), isto só avisa
  /// que a sincronização está temporariamente atrasada.
  Widget _buildSyncDegradedBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IrisTheme.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IrisTheme.danger.withOpacity(0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync_problem, color: IrisTheme.danger, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sincronização instável — tentando reconectar a outro servidor '
              'automaticamente. Seus fundos não são afetados.',
              style:
                  TextStyle(color: IrisTheme.danger, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnChainSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IrisTheme.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IrisTheme.bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet, color: IrisTheme.primary),
              SizedBox(width: 8),
              Text('Cofre (On-chain)',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: IrisTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final rate = context.watch<ExchangeRateService>();
            final wallet = context.watch<WalletService>();
            final hide = wallet.hideBalance;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PendingBanner(
                  pendingSats: wallet.pendingOnchainSats(isMerchant: false),
                  hide: hide,
                  format: CurrencyFormatter.formatBtcOrSats,
                ),
                Text(
                  hide
                      ? '••••••'
                      : (rate.isSatsDisplay
                          ? CurrencyFormatter.formatBtcOrSats(_onChainBalance)
                          : 'R\$ ${CurrencyFormatter.formatBrlCompact(rate.satsToBrl(_onChainBalance))}'),
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: IrisTheme.textPrimary),
                ),
                if (!hide)
                  Text(
                    rate.isSatsDisplay
                        ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(rate.satsToBrl(_onChainBalance))}'
                        : '≈ ${CurrencyFormatter.formatBtcOrSats(_onChainBalance)}',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: IrisTheme.textTertiary),
                  ),
              ],
            );
          }),
          const Text('Disponível para abrir novos canais',
              style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
          const SizedBox(height: 12),
          _buildDeepScanCard(),
          const SizedBox(height: 24),
          if (_onChainAddress.isNotEmpty) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: QrImageView(
                  data: _onChainAddress,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
                child: Text('Endereço Testnet4 (SegWit)',
                    style: TextStyle(
                        color: IrisTheme.textSecondary, fontSize: 12))),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _onChainAddress));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Endereço copiado!')));
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: IrisTheme.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _onChainAddress,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            color: IrisTheme.primaryLight,
                            fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Icon(Icons.copy,
                        size: 16, color: IrisTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use um faucet de TESTNET4 neste endereço. Confira no explorador do faucet se o link é /testnet4/ — endereços de testnet3 e testnet4 são idênticos, e enviar na rede errada some com as moedas.',
              style: TextStyle(
                  color: IrisTheme.textTertiary,
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildChannelsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Canais Lightning',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: IrisTheme.textPrimary)),
            TextButton.icon(
              onPressed: _showOpenChannelDialog,
              icon: const Icon(Icons.add),
              label: const Text('Abrir Canal'),
              style: TextButton.styleFrom(foregroundColor: IrisTheme.primary),
            )
          ],
        ),
        const SizedBox(height: 8),
        if (_channels.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: IrisTheme.s1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: IrisTheme.bdr),
            ),
            child: const Center(
              child: Text(
                'Nenhum canal aberto.\nVocê precisa depositar fundos On-chain e abrir um canal para começar a transacionar via Lightning.',
                textAlign: TextAlign.center,
                style: TextStyle(color: IrisTheme.textSecondary),
              ),
            ),
          )
        else
          ..._channels.map((ch) {
            final capacity = ch.capacitySats;
            final inbound = ch.inboundSats;
            final outbound = ch.outboundSats;
            final isUsable = ch.isUsable;
            final hide = context.watch<WalletService>().hideBalance;
            String fmtSats(int sats) {
              if (hide) return '••••';
              final r = context.watch<ExchangeRateService>();
              return r.isSatsDisplay
                  ? CurrencyFormatter.formatBtcOrSats(sats)
                  : 'R\$ ${CurrencyFormatter.formatBrlCompact(r.satsToBrl(sats))}';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: IrisTheme.s1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isUsable
                        ? IrisTheme.primary.withOpacity(0.5)
                        : IrisTheme.bdr),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Canal com ${ch.counterpartyNodeId.length >= 8 ? ch.counterpartyNodeId.substring(0, 8) : ch.counterpartyNodeId}...',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: IrisTheme.textPrimary),
                      ),
                      Row(
                        children: [
                          if (ch.isPublic)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: IrisTheme.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Público',
                                style: TextStyle(
                                    color: IrisTheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isUsable
                                  ? IrisTheme.success.withOpacity(0.2)
                                  : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isUsable ? 'Ativo' : 'Pendente/Inativo',
                              style: TextStyle(
                                  color: isUsable
                                      ? IrisTheme.success
                                      : Colors.orange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Posso Enviar',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: IrisTheme.textSecondary)),
                            Text(fmtSats(outbound),
                                style: const TextStyle(
                                    color: IrisTheme.primaryLight,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Capacidade',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: IrisTheme.textSecondary)),
                            Text(fmtSats(capacity),
                                style: const TextStyle(
                                    color: IrisTheme.textPrimary,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Posso Receber',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: IrisTheme.textSecondary)),
                            Text(fmtSats(inbound),
                                style: const TextStyle(
                                    color: IrisTheme.success,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Barra de liquidez visual
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        if (capacity > 0)
                          Expanded(
                            flex: outbound,
                            child: Container(
                              height: 8,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        if (capacity > 0)
                          Expanded(
                            flex: inbound,
                            child: Container(
                              height: 8,
                              color: Colors.grey[800],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Editor de taxa de roteamento removido: o app deixou de
                  // perseguir a ideia de o usuário ganhar roteando (o nó de um
                  // celular não roteia — fica atrás de CGNAT e não aceita
                  // conexão de entrada). Ajustar ppm aqui só daria a impressão
                  // de uma receita que não existe.
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

}
