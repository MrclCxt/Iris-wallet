import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallet_service.dart';
import '../services/liquid_wallet_service.dart';
import '../core/theme.dart';

enum PinMode { unlock, create }

class PinScreen extends StatefulWidget {
  final PinMode mode;
  final VoidCallback? onSuccess;
  final bool isMerchant;
  const PinScreen({super.key, required this.mode, this.onSuccess, this.isMerchant = false});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String _firstPin = '';
  bool _isConfirming = false;

  /// Inicializa a carteira Liquid (sidechain) com a mesma seed do perfil,
  /// em segundo plano, após o desbloqueio.
  void _initLiquidInBackground() {
    final wallet = context.read<WalletService>();
    final liquid = context.read<LiquidWalletService>();
    final seed = widget.isMerchant ? wallet.merchantSeed : wallet.consumerSeed;
    if (seed != null && !liquid.isRunning) {
      liquid.initLiquidWallet(seed).catchError((e) {
        debugPrint('Liquid init: $e');
      });
    }
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
          if (widget.mode == PinMode.create) {
            if (!_isConfirming) {
              setState(() {
                _firstPin = _pin;
                _pin = '';
                _isConfirming = true;
              });
            } else {
              if (_pin == _firstPin) {
                final wallet = context.read<WalletService>();
                final success = widget.isMerchant ? await wallet.unlockMerchant(_pin) : await wallet.unlock(_pin);
                if (success) {
                  _initLiquidInBackground();
                  if (widget.onSuccess != null) {
                    widget.onSuccess!();
                  } else {
                    Navigator.pushReplacementNamed(context, widget.isMerchant ? '/merchant_home' : '/consumer_home');
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Os PINs não coincidem. Tente novamente.'), backgroundColor: IrisTheme.danger),
                );
                setState(() {
                  _pin = '';
                  _firstPin = '';
                  _isConfirming = false;
                });
              }
            }
          } else {
            // Unlock mode
            final wallet = context.read<WalletService>();
            if (widget.onSuccess != null) {
              // Confirmação (ex.: pagamento): apenas VERIFICA o PIN, sem
              // mexer na sessão — evita qualquer efeito de "deslogar".
              final ok = widget.isMerchant
                  ? wallet.verifyMerchantPin(_pin)
                  : wallet.verifyConsumerPin(_pin);
              if (ok) {
                widget.onSuccess!();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN incorreto'), backgroundColor: IrisTheme.danger),
                );
                setState(() => _pin = '');
              }
            } else {
              // Desbloqueio de sessão de verdade
              final success = widget.isMerchant ? await wallet.unlockMerchant(_pin) : await wallet.unlock(_pin);
              if (success) {
                _initLiquidInBackground();
                Navigator.pushNamedAndRemoveUntil(context, widget.isMerchant ? '/merchant_home' : '/consumer_home', (route) => false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN incorreto'), backgroundColor: IrisTheme.danger),
                );
                setState(() => _pin = '');
              }
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == PinMode.create;
    final canPop = Navigator.canPop(context);
    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: IrisTheme.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: canPop ? IconButton(
            icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ) : null,
        ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                if (isCreate) ...[
                  Text(widget.isMerchant ? '🏪' : '🔐', style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(
                    _isConfirming 
                      ? 'Confirme seu PIN' 
                      : (widget.isMerchant 
                        ? 'Crie um PIN da loja' 
                        : (context.read<WalletService>().consumerAccounts.isNotEmpty ? 'Crie o PIN da nova carteira' : 'Crie um PIN de 6 dígitos')), 
                    style: Theme.of(context).textTheme.displayMedium, 
                    textAlign: TextAlign.center
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.isMerchant 
                      ? 'PIN exclusivo para a área da loja' 
                      : (context.read<WalletService>().consumerAccounts.isNotEmpty ? 'Usado para abrir esta carteira secundária' : 'Usado para abrir o app'), 
                    style: Theme.of(context).textTheme.bodyMedium, 
                    textAlign: TextAlign.center
                  ),
                ] else ...[
                  Text(widget.isMerchant ? '🏪' : '⚡', style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(widget.isMerchant ? 'Entrar na loja' : 'Sua carteira', style: Theme.of(context).textTheme.displayMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 2),
                  Text(widget.isMerchant ? 'Digite o PIN da loja' : 'Digite o seu PIN pessoal', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 18),
                _buildDots(),
                const SizedBox(height: 12),
                const Spacer(),
                _buildKeypad(),
                if (isCreate) ...[
                  const SizedBox(height: 16),
                  _buildCancelBtn(),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      ),
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

  Widget _buildCancelBtn() {
    final wallet = context.watch<WalletService>();
    if (wallet.consumerAccounts.isEmpty && wallet.merchantAccounts.isEmpty) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: () {
        context.read<WalletService>().cancelWalletCreation();
        Navigator.of(context).popUntil((route) => route.settings.name == '/consumer_home' || route.settings.name == '/welcome' || route.isFirst);
      },
      style: TextButton.styleFrom(
        foregroundColor: IrisTheme.danger,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: const Text('Cancelar e Voltar', style: TextStyle(fontWeight: FontWeight.bold)),
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
