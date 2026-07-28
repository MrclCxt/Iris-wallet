import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/wallet_service.dart';
import '../services/product_image_store.dart';

class ProductThumb extends StatelessWidget {
  final Product product;
  final double tamanho;
  const ProductThumb({super.key, required this.product, this.tamanho = 52});

  @override
  Widget build(BuildContext context) {
    final semFoto = Center(
      child: Icon(
        Icons.inventory_2_outlined,
        size: tamanho * 0.45,
        color: IrisTheme.textTertiary,
      ),
    );

    final caminho = ProductImageStore.caminhoDe(product.image);

    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: IrisTheme.s2,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: caminho == null
          ? semFoto
          : Image.file(
              File(caminho),
              fit: BoxFit.cover,
              width: tamanho,
              height: tamanho,
              errorBuilder: (_, __, ___) => semFoto,
            ),
    );
  }
}
