import 'dart:async';
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
  const PinScreen(
      {super.key, required this.mode, this.onSuccess, this.isMerchant = false});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String _firstPin = '';
  bool _isConfirming = false;
  bool _verifying = false;
  Timer? _lockTicker;

  @override
  void initState() {
    super.initState();

    _lockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (context.read<WalletService>().isPinLocked) setState(() {});
    });
  }

  @override
  void dispose() {
    _lockTicker?.cancel();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}min';
    if (d.inMinutes >= 1) return '${d.inMinutes}min ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  String _wrongPinMessage(WalletService wallet) {
    if (wallet.autoWipeEnabled) {
      final left = wallet.pinAttemptsRemainingBeforeWipe;
      if (left > 0 && left <= 3) {
        return 'PIN incorreto. Faltam $left tentativa(s) antes de a carteira '
            'ser apagada deste aparelho.';
      }
    }
    return 'PIN incorreto';
  }

  void _initLiquidInBackground() {
    final wallet = context.read<WalletService>();
    final liquid = context.read<LiquidWalletService>();

    final seed = wallet.deviceSeed ??
        (widget.isMerchant ? wallet.merchantSeed : wallet.consumerSeed);
    if (seed != null) {
      liquid.initLiquidWallet(seed, accountId: 'device').catchError((e) {
        debugPrint('Liquid init: $e');
      });
    }
  }

  void _onKeyPress(String key) async {
    if (_verifying) return;

    if (widget.mode == PinMode.unlock &&
        context.read<WalletService>().isPinLocked) {
      return;
    }
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
                setState(() => _verifying = true);
                final success = widget.isMerchant
                    ? await wallet.unlockMerchant(_pin)
                    : await wallet.unlock(_pin);

                if (!mounted) return;
                setState(() => _verifying = false);
                if (success) {
                  _initLiquidInBackground();
                  if (widget.onSuccess != null) {
                    widget.onSuccess!();
                  } else {
                    Navigator.pushReplacementNamed(
                        context,
                        widget.isMerchant
                            ? '/merchant_home'
                            : '/consumer_home');
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Os PINs não coincidem. Tente novamente.'),
                      backgroundColor: IrisTheme.danger),
                );
                setState(() {
                  _pin = '';
                  _firstPin = '';
                  _isConfirming = false;
                });
              }
            }
          } else {
            final wallet = context.read<WalletService>();
            if (widget.onSuccess != null) {
              final ok = widget.isMerchant
                  ? wallet.verifyMerchantPin(_pin)
                  : wallet.verifyConsumerPin(_pin);
              if (ok) {
                widget.onSuccess!();
              } else {
                final locked = wallet.isPinLocked;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(locked
                        ? 'Muitas tentativas. Bloqueado por ${_fmtDuration(wallet.pinLockRemaining)}.'
                        : _wrongPinMessage(wallet)),
                    backgroundColor: IrisTheme.danger,
                  ),
                );
                setState(() => _pin = '');
              }
            } else {
              setState(() => _verifying = true);
              final success = widget.isMerchant
                  ? await wallet.unlockMerchant(_pin)
                  : await wallet.unlock(_pin);
              if (!mounted) return;
              setState(() => _verifying = false);
              if (success) {
                _initLiquidInBackground();
                Navigator.pushNamedAndRemoveUntil(
                    context,
                    widget.isMerchant ? '/merchant_home' : '/consumer_home',
                    (route) => false);
              } else {
                final locked = wallet.isPinLocked;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(locked
                        ? 'Muitas tentativas. Bloqueado por ${_fmtDuration(wallet.pinLockRemaining)}.'
                        : _wrongPinMessage(wallet)),
                    backgroundColor: IrisTheme.danger,
                  ),
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
    final wallet = context.watch<WalletService>();
    final locked = !isCreate && wallet.isPinLocked;
    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: IrisTheme.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: IrisTheme.textPrimary),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
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
                    Text(widget.isMerchant ? '🏪' : '🔐',
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(
                        _isConfirming
                            ? 'Confirme seu PIN'
                            : (widget.isMerchant
                                ? 'Crie um PIN da loja'
                                : (context
                                        .read<WalletService>()
                                        .consumerAccounts
                                        .isNotEmpty
                                    ? 'Crie o PIN da nova carteira'
                                    : 'Crie um PIN de 6 dígitos')),
                        style: Theme.of(context).textTheme.displayMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 3),
                    Text(
                        widget.isMerchant
                            ? 'PIN exclusivo para a área da loja'
                            : (context
                                    .read<WalletService>()
                                    .consumerAccounts
                                    .isNotEmpty
                                ? 'Usado para abrir esta carteira secundária'
                                : 'Usado para abrir o app'),
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                  ] else ...[
                    Text(widget.isMerchant ? '🏪' : '⚡',
                        style: const TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(widget.isMerchant ? 'Entrar na loja' : 'Sua carteira',
                        style: Theme.of(context).textTheme.displayMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 2),
                    Text(
                        widget.isMerchant
                            ? 'Digite o PIN da loja'
                            : 'Digite o seu PIN pessoal',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 18),
                  _buildDots(),
                  const SizedBox(height: 12),
                  if (_verifying)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: IrisTheme.primary),
                          ),
                          SizedBox(width: 8),
                          Text('Verificando…',
                              style: TextStyle(
                                  color: IrisTheme.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  if (locked) _buildLockBanner(wallet),
                  const Spacer(),
                  Opacity(
                    opacity: (locked || _verifying) ? 0.35 : 1,
                    child: IgnorePointer(
                        ignoring: locked || _verifying, child: _buildKeypad()),
                  ),
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

  Widget _buildLockBanner(WalletService wallet) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: IrisTheme.danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IrisTheme.danger.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_clock, color: IrisTheme.danger, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Muitas tentativas. Tente de novo em ${_fmtDuration(wallet.pinLockRemaining)}.',
              style: const TextStyle(
                  color: IrisTheme.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
        Navigator.of(context).popUntil((route) =>
            route.settings.name == '/consumer_home' ||
            route.settings.name == '/welcome' ||
            route.isFirst);
      },
      style: TextButton.styleFrom(
        foregroundColor: IrisTheme.danger,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: const Text('Cancelar e Voltar',
          style: TextStyle(fontWeight: FontWeight.bold)),
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
