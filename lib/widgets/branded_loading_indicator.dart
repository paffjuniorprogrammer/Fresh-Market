import 'package:flutter/material.dart';
import 'package:potato_app/utils/app_ui.dart';

class BrandedLoadingIndicator extends StatelessWidget {
  final double size;
  final double logoSize;
  final double strokeWidth;
  final String? label;

  const BrandedLoadingIndicator({
    super.key,
    this.size = 86,
    this.logoSize = 42,
    this.strokeWidth = 3,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  strokeWidth: strokeWidth,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppUi.primary),
                ),
              ),
              Container(
                width: logoSize + 16,
                height: logoSize + 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/logo.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 16),
          Text(
            label!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppUi.dark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
