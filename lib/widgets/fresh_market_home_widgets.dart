import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:potato_app/models/product.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/formatters.dart';
import 'package:shimmer/shimmer.dart';

class FreshMarketHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badgeText;
  final String imageUrl;
  final VoidCallback onPressed;

  const FreshMarketHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.imageUrl,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 216,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7ECDC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              left: -34,
              bottom: -34,
              child: Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: -6,
              bottom: -12,
              child: Opacity(
                opacity: 0.10,
                child: Image.asset(
                  'assets/logo.png',
                  width: 165,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                              color: Color(0xFF3C8A3F),
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppUi.dark,
                            fontSize: 22,
                            height: 1.04,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: onPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppUi.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Order Now',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                height: double.infinity,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                memCacheWidth: 800,
                                placeholder: (context, url) => Shimmer.fromColors(
                                  baseColor: Colors.grey.shade200,
                                  highlightColor: Colors.white,
                                  child: Container(color: Colors.white),
                                ),
                                errorWidget: (context, url, error) =>
                                    const _HeroArtworkFallback(),
                              )
                            : const _HeroArtworkFallback(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FreshMarketProductHeroCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const FreshMarketProductHeroCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final discountPercent = product.hasDiscount
        ? ((1 - (product.discountPrice! / (product.price <= 0 ? 1 : product.price))) * 100).round()
        : null;
    final displayPrice = product.hasDiscount ? product.discountPrice! : product.price;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 220,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0052CC), Color(0xFF1B8049)], // Blue to deep green
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0052CC).withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Opacity(
                  opacity: 0.1,
                  child: Image.asset(
                    'assets/logo.png',
                    width: 180,
                  ),
                ),
              ),
              Positioned(
                left: -30,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (discountPercent != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'SAVE $discountPercent%',
                                style: const TextStyle(
                                  color: Color(0xFF0052CC),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                              ),
                              child: const Text(
                                'FRESH PICK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                moneyLabel(displayPrice),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '/${product.unit}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (product.hasDiscount)
                            Text(
                              moneyLabel(product.price),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Order Now',
                              style: TextStyle(
                                color: Color(0xFF0052CC),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      flex: 5,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(23),
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrl,
                            fit: BoxFit.cover,
                            height: double.infinity,
                            placeholder: (context, url) => Shimmer.fromColors(
                              baseColor: Colors.white.withValues(alpha: 0.1),
                              highlightColor: Colors.white.withValues(alpha: 0.3),
                              child: Container(color: Colors.white),
                            ),
                            errorWidget: (context, url, error) => Image.asset('assets/logo.png'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroArtworkFallback extends StatelessWidget {
  const _HeroArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 162,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(26),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Image.asset('assets/logo.png'),
      ),
    );
  }
}

class FreshMarketCategoryChip extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final bool isSelected;
  final Color accentColor;
  final IconData icon;

  const FreshMarketCategoryChip({
    super.key,
    required this.label,
    required this.imageUrl,
    required this.isSelected,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isSelected ? AppUi.primary : accentColor;
    final textColor = isSelected ? AppUi.primary : Colors.grey.shade700;

    return SizedBox(
      width: 74,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 60,
            width: 60,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: isSelected
                    ? [const Color(0xFF4AA74A), const Color(0xFF2E7D32)]
                    : [cardColor, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? AppUi.primary : accentColor).withValues(
                    alpha: 0.22,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade200,
                        highlightColor: Colors.white,
                        child: Container(color: Colors.white),
                      ),
                      errorWidget: (context, url, error) => Icon(
                        icon,
                        color: isSelected ? Colors.white : AppUi.primary,
                        size: 26,
                      ),
                    )
                  : Icon(
                      icon,
                      color: isSelected ? Colors.white : AppUi.primary,
                      size: 26,
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class FreshMarketProductCard extends StatelessWidget {
  final Product product;
  final double qtyInCart;
  final String badgeText;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const FreshMarketProductCard({
    super.key,
    required this.product,
    required this.qtyInCart,
    required this.badgeText,
    required this.onAdd,
    required this.onRemove,
  });

  int? _discountPercent() {
    if (!product.hasDiscount) return null;
    final basePrice = product.price <= 0 ? 1 : product.price;
    return ((1 - (product.discountPrice! / basePrice)) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final discountPercent = _discountPercent();
    final displayPrice = product.hasDiscount
        ? product.discountPrice!
        : product.price;
    final showBadge = product.hasDiscount && badgeText.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 180;
        final actionHeight = isCompact ? 42.0 : 38.0;

        return RepaintBoundary(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE7ECDC)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: isCompact ? 5 : 6,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: Colors.white,
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 600,
                            placeholder: (context, url) => Shimmer.fromColors(
                              baseColor: Colors.grey.shade200,
                              highlightColor: Colors.white,
                              child: Container(color: Colors.white),
                            ),
                            errorWidget: (context, url, error) => Center(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (showBadge && discountPercent != null)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5E3),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '-$discountPercent%',
                              style: const TextStyle(
                                color: AppUi.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2D372F),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              moneyLabel(displayPrice),
                              style: const TextStyle(
                                color: AppUi.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '/${product.unit}',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (product.hasDiscount) ...[
                          const SizedBox(height: 4),
                          Text(
                            moneyLabel(product.price),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          badgeText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: SizedBox(
                    height: actionHeight,
                    width: double.infinity,
                    child: qtyInCart == 0
                        ? ElevatedButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(
                              Icons.shopping_cart_outlined,
                              size: 16,
                            ),
                            label: const Text(
                              'Order',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppUi.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: AppUi.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: IconButton(
                                    onPressed: onRemove,
                                    icon: const Icon(
                                      Icons.remove_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                                Text(
                                  qtyLabel(qtyInCart, product.unit),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.5,
                                  ),
                                ),
                                Expanded(
                                  child: IconButton(
                                    onPressed: onAdd,
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
