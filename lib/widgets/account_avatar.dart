import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/avatar_image_store.dart';
import '../services/wallet_service.dart';
import '../screens/consumer/profile_screen.dart';
import 'iris_widgets.dart';

class AvatarCircle extends StatelessWidget {
  final String? accountId;
  final String? colorHex;
  final double size;
  const AvatarCircle(
      {super.key, this.accountId, this.colorHex, this.size = 36});

  Color get _ringColor {
    final h = colorHex;
    if (h == null || !h.startsWith('#') || h.length != 7) return IrisTheme.bdr2;
    return Color(int.parse('FF${h.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final id = accountId;
    if (id != null && AvatarImageStore.existe(id)) {
      final caminho = AvatarImageStore.caminhoDe(id)!;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _ringColor, width: 2),
        ),
        child: ClipOval(
          child: Image.file(
            File(caminho),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return IrisLogo(size: size);
  }
}

class AccountAvatar extends StatelessWidget {
  final bool isMerchant;
  final double size;
  const AccountAvatar({super.key, required this.isMerchant, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final p = isMerchant ? wallet.activeMerchant : wallet.activeConsumer;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProfileScreen(isMerchant: isMerchant)),
      ),
      child:
          AvatarCircle(accountId: p?.id, colorHex: p?.avatarColor, size: size),
    );
  }
}
