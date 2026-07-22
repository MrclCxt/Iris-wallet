import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import '../../services/wallet_service.dart';
import '../../services/node_backend.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';

class NodeManagerScreen extends StatefulWidget {
  const NodeManagerScreen({super.key});

  @override
  State<NodeManagerScreen> createState() => _NodeManagerScreenState();
}

class _NodeManagerScreenState extends State<NodeManagerScreen> {
  int _onChainBalance = 0;
  String _onChainAddress = '';
  List<ChannelSummary> _channels = [];
  bool _isLoading = true;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadNodeData();
    // Auto-sync a cada 30 segundos enquanto estiver nesta tela
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _syncNode());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNodeData() async {
    setState(() => _isLoading = true);
    try {
      final wallet = context.read<WalletService>();
      final address = await wallet.getOnchainAddress();
      final balance = await wallet.getOnchainBalance();
      final channels = await wallet.getChannels();
      
      setState(() {
        _onChainAddress = address;
        _onChainBalance = balance;
        _channels = channels;
      });
    } catch (e) {
      debugPrint('Failed to load node data: $e');
    } finally {
      setState(() => _isLoading = false);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Abrir Novo Canal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: IrisTheme.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                  controller: pubkeyCtrl,
                  style: const TextStyle(color: IrisTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Node PubKey (Hex)',
                    labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                    filled: true,
                    fillColor: IrisTheme.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                          labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                          filled: true,
                          fillColor: IrisTheme.bg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                          labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                          filled: true,
                          fillColor: IrisTheme.bg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    helperText: 'Saldo disponível: $_onChainBalance sats',
                    helperStyle: const TextStyle(color: IrisTheme.primary),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isOpening ? null : () async {
                    try {
                      setStateModal(() => isOpening = true);
                      final sats = int.tryParse(amountCtrl.text) ?? 0;
                      if (sats < 20000) throw Exception('Capacidade mínima é 20,000 sats');
                      
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
                        const SnackBar(content: Text('Sinal de abertura de canal enviado! Aguarde a confirmação on-chain.'), backgroundColor: IrisTheme.success),
                      );
                      _loadNodeData();
                    } catch (e) {
                      if (!mounted) return;
                      setStateModal(() => isOpening = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e'), backgroundColor: IrisTheme.danger),
                      );
                    }
                  },
                  child: isOpening ? const CircularProgressIndicator(color: Colors.white) : const Text('Solicitar Abertura de Canal'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      ),
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
        title: const Text('Backend do nó', style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modo atual: ${wallet.isConsumerNodeRemote ? 'Daemon local (RPC)' : 'Embarcado (FFI)'}',
              style: const TextStyle(color: IrisTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: IrisTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'URL do daemon (vazio = embarcado)',
                hintText: 'http://127.0.0.1:8380',
                labelStyle: const TextStyle(color: IrisTheme.textSecondary),
                hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                filled: true,
                fillColor: IrisTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O daemon (iris-noded) roda o nó como serviço neste dispositivo, sempre em 127.0.0.1. A mudança vale no próximo desbloqueio.',
              style: TextStyle(color: IrisTheme.textTertiary, fontSize: 11, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: IrisTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await wallet.setDaemonUrl(urlCtrl.text, forMerchant: false);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backend salvo. Bloqueie e desbloqueie a carteira para aplicar.')),
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
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.s1,
        title: const Text('Gestão do Nó Nativo ⚡', style: TextStyle(color: IrisTheme.textPrimary, fontSize: 18)),
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronizando nó com a Testnet...')));
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
                _buildOnChainSection(),
                const SizedBox(height: 24),
                _buildChannelsSection(),
              ],
            ),
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
              Text('Cofre (On-chain)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: IrisTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final rate = context.watch<ExchangeRateService>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rate.isSatsDisplay
                      ? CurrencyFormatter.formatBtcOrSats(_onChainBalance)
                      : 'R\$ ${CurrencyFormatter.formatBrlCompact(rate.satsToBrl(_onChainBalance))}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: IrisTheme.textPrimary),
                ),
                Text(
                  rate.isSatsDisplay
                      ? '≈ R\$ ${CurrencyFormatter.formatBrlCompact(rate.satsToBrl(_onChainBalance))}'
                      : '≈ ${CurrencyFormatter.formatBtcOrSats(_onChainBalance)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: IrisTheme.textTertiary),
                ),
              ],
            );
          }),
          const Text('Disponível para abrir novos canais', style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
          const SizedBox(height: 24),
          
          if (_onChainAddress.isNotEmpty) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(
                  data: _onChainAddress,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(child: Text('Endereço Testnet (SegWit)', style: TextStyle(color: IrisTheme.textSecondary, fontSize: 12))),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _onChainAddress));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endereço copiado!')));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: IrisTheme.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _onChainAddress,
                        style: const TextStyle(fontFamily: 'monospace', color: IrisTheme.primaryLight, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Icon(Icons.copy, size: 16, color: IrisTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dica: Use um Faucet (ex: bitcoinfaucet.uo1.net) para receber moedas de teste grátis neste endereço.',
              style: TextStyle(color: IrisTheme.textTertiary, fontSize: 11, fontStyle: FontStyle.italic),
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
            const Text('Canais Lightning', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: IrisTheme.textPrimary)),
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
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: IrisTheme.s1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isUsable ? IrisTheme.primary.withOpacity(0.5) : IrisTheme.bdr),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Canal com ${ch.counterpartyNodeId.length >= 8 ? ch.counterpartyNodeId.substring(0, 8) : ch.counterpartyNodeId}...',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: IrisTheme.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isUsable ? IrisTheme.success.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isUsable ? 'Ativo' : 'Pendente/Inativo',
                          style: TextStyle(color: isUsable ? IrisTheme.success : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
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
                            const Text('Posso Enviar', style: TextStyle(fontSize: 10, color: IrisTheme.textSecondary)),
                            Text(
                                context.watch<ExchangeRateService>().isSatsDisplay
                                    ? CurrencyFormatter.formatBtcOrSats(outbound)
                                    : 'R\$ ${CurrencyFormatter.formatBrlCompact(context.watch<ExchangeRateService>().satsToBrl(outbound))}',
                                style: const TextStyle(color: IrisTheme.primaryLight, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Capacidade', style: TextStyle(fontSize: 10, color: IrisTheme.textSecondary)),
                            Text(
                                context.watch<ExchangeRateService>().isSatsDisplay
                                    ? CurrencyFormatter.formatBtcOrSats(capacity)
                                    : 'R\$ ${CurrencyFormatter.formatBrlCompact(context.watch<ExchangeRateService>().satsToBrl(capacity))}',
                                style: const TextStyle(color: IrisTheme.textPrimary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Posso Receber', style: TextStyle(fontSize: 10, color: IrisTheme.textSecondary)),
                            Text(
                                context.watch<ExchangeRateService>().isSatsDisplay
                                    ? CurrencyFormatter.formatBtcOrSats(inbound)
                                    : 'R\$ ${CurrencyFormatter.formatBrlCompact(context.watch<ExchangeRateService>().satsToBrl(inbound))}',
                                style: const TextStyle(color: IrisTheme.success, fontWeight: FontWeight.bold)),
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
                  )
                ],
              ),
            );
          }).toList(),
      ],
    );
  }
}
