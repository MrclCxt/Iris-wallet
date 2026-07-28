import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chroma_service.dart';

class IrisButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double verticalPadding;
  final Widget? icon;

  const IrisButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.verticalPadding = 16,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final chroma = context.watch<ChromaService>();
    final gradient = chroma.buttonGradient;
    final primary = chroma.primary;

    return AnimatedContainer(
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.38),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? icon! : const SizedBox.shrink(),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 0),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class IrisLogo extends StatelessWidget {
  final double size;
  const IrisLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/icon_1024.png',
      width: size,
      height: size,
    );
  }
}

class IrisAppBarTitle extends StatelessWidget {
  const IrisAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final chroma = context.watch<ChromaService>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const IrisLogo(size: 28),
        const SizedBox(width: 8),
        ShaderMask(
          shaderCallback: (b) => chroma.brandGradient.createShader(b),
          child: const Text(
            'IRIS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
