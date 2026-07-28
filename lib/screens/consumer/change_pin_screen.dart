import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';

enum _Etapa { atual, novo, confirmar }

class ChangePinScreen extends StatefulWidget {
  final bool isMerchant;
  const ChangePinScreen({super.key, this.isMerchant = false});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  _Etapa _etapa = _Etapa.atual;
  String _pin = '';
  String _oldPin = '';
  String _newPin = '';
  String? _erro;
  bool _busy = false;
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

  void _onKeyPress(String key) async {
    final wallet = context.read<WalletService>();
    if (wallet.isPinLocked) return;

    if (key == 'del') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
      return;
    }
    if (_pin.length >= 6) return;
    setState(() {
      _pin += key;
      _erro = null;
    });
    if (_pin.length != 6) return;

    switch (_etapa) {
      case _Etapa.atual:
        _oldPin = _pin;
        setState(() {
          _pin = '';
          _etapa = _Etapa.novo;
        });
        break;
      case _Etapa.novo:
        _newPin = _pin;
        setState(() {
          _pin = '';
          _etapa = _Etapa.confirmar;
        });
        break;
      case _Etapa.confirmar:
        if (_pin != _newPin) {
          setState(() {
            _erro = 'Os PINs não coincidem. Digite o novo PIN de novo.';
            _pin = '';
            _newPin = '';
            _etapa = _Etapa.novo;
          });
          return;
        }
        setState(() => _busy = true);
        final ok = widget.isMerchant
            ? await wallet.changeMerchantPin(_oldPin, _newPin)
            : await wallet.changeConsumerPin(_oldPin, _newPin);
        if (!mounted) return;
        setState(() => _busy = false);
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('PIN alterado com sucesso.'),
                backgroundColor: IrisTheme.success),
          );
          Navigator.pop(context);
        } else {
          final locked = wallet.isPinLocked;
          setState(() {
            _erro = locked
                ? 'Muitas tentativas. Bloqueado por ${_fmtDuration(wallet.pinLockRemaining)}.'
                : 'PIN atual incorreto. Tente de novo.';
            _pin = '';
            _oldPin = '';
            _newPin = '';
            _etapa = _Etapa.atual;
          });
        }
        break;
    }
  }

  String get _titulo {
    switch (_etapa) {
      case _Etapa.atual:
        return 'Digite o PIN atual';
      case _Etapa.novo:
        return 'Crie o novo PIN';
      case _Etapa.confirmar:
        return 'Confirme o novo PIN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final locked = wallet.isPinLocked;

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: IrisTheme.bg,
        elevation: 0,
        title: const Text('Alterar PIN',
            style: TextStyle(color: IrisTheme.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Text(_titulo,
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(_erro!,
                        style: const TextStyle(
                            color: IrisTheme.danger, fontSize: 12),
                        textAlign: TextAlign.center),
                  ),
                ],
                const SizedBox(height: 18),
                _buildDots(),
                const SizedBox(height: 12),
                if (locked) _buildLockBanner(wallet),
                const Spacer(),
                Opacity(
                  opacity: (locked || _busy) ? 0.35 : 1,
                  child: IgnorePointer(
                    ignoring: locked || _busy,
                    child: _buildKeypad(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
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
                width: 2),
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
