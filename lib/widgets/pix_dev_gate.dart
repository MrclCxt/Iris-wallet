import 'package:flutter/material.dart';
import '../screens/consumer/ativar_pix_screen.dart';

/// Atalho de desenvolvimento para a área de Pix, que ainda não foi publicada.
///
/// O item "Pix / Reais · em breve" das Configurações continua se comportando
/// como antes para quem só toca uma vez. Dez toques em sequência abrem a
/// [AtivarPixScreen] para teste e visualização prévia.
///
/// A contagem zera após [_janela] sem toques, para que toques avulsos ao longo
/// do dia não somem até destravar sozinhos.
class PixDevGate {
  PixDevGate._();

  static const int _toquesNecessarios = 10;
  static const int _avisaApartirDe = 5;
  static const Duration _janela = Duration(seconds: 2);

  static int _toques = 0;
  static DateTime? _ultimoToque;

  static void aoTocar(
    BuildContext context, {
    required String mensagemEmBreve,
  }) {
    final agora = DateTime.now();
    final ultimo = _ultimoToque;
    if (ultimo == null || agora.difference(ultimo) > _janela) {
      _toques = 0;
    }
    _ultimoToque = agora;
    _toques++;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (_toques >= _toquesNecessarios) {
      _toques = 0;
      _ultimoToque = null;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AtivarPixScreen()),
      );
      return;
    }

    if (_toques >= _avisaApartirDe) {
      final faltam = _toquesNecessarios - _toques;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 600),
          content: Text(faltam == 1
              ? 'Falta 1 toque para abrir a prévia do Pix.'
              : 'Faltam $faltam toques para abrir a prévia do Pix.'),
        ),
      );
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text(mensagemEmBreve)));
  }
}
