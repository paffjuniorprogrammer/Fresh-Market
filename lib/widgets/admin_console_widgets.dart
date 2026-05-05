import 'package:flutter/material.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/widgets/badge_icon.dart';

class AdminSidebarItemData {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const AdminSidebarItemData({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });
}

class AdminOverviewCardData {
  final String eyebrow;
  final String value;
  final String caption;
  final IconData icon;
  final Color startColor;
  final Color endColor;

  const AdminOverviewCardData({
    required this.eyebrow,
    required this.value,
    required this.caption,
    required this.icon,
    required this.startColor,
    required this.endColor,
  });
}

class AdminRecentOrderData {
  final String customer;
  final String product;
  final String dateLabel;
  final String amountLabel;

  const AdminRecentOrderData({
    required this.customer,
    required this.product,
    required this.dateLabel,
    required this.amountLabel,
  });
}

class AdminTopProductData {
  final String name;
  final String subtitle;
  final String priceLabel;
  final String? imageUrl;

  const AdminTopProductData({
    required this.name,
    required this.subtitle,
    required this.priceLabel,
    this.imageUrl,
  });
}

class AdminConsoleSidebar extends StatelessWidget {
  final List<AdminSidebarItemData> items;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final VoidCallback onSignOut;

  const AdminConsoleSidebar({
    super.key,
    required this.items,
    required this.isCollapsed,
    required this.onToggle,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = isCollapsed ? 72.0 : 120.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: sidebarWidth,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7BC655), Color(0xFF3E9438)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppUi.primary.withAlpha(45),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withAlpha(65)),
                    ),
                    child: Center(
                      child: Image.asset('assets/logo.png', width: 44, height: 44),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.white.withAlpha(28),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 34,
                      height: 58,
                      child: Icon(
                        isCollapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AdminSidebarButton(
                          item: item,
                          isCollapsed: isCollapsed,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: Material(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onSignOut,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: isCollapsed
                      ? const Icon(Icons.logout_rounded, color: Colors.white, size: 20)
                      : const Column(
                          children: [
                            Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                            SizedBox(height: 4),
                            Text(
                              'Logout',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSidebarButton extends StatelessWidget {
  final AdminSidebarItemData item;
  final bool isCollapsed;

  const _AdminSidebarButton({required this.item, required this.isCollapsed});

  @override
  Widget build(BuildContext context) {
    final Color background = item.isActive
        ? Colors.white.withAlpha(45)
        : Colors.transparent;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: 10,
            horizontal: isCollapsed ? 6 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.isActive
                  ? Colors.white.withAlpha(70)
                  : Colors.transparent,
            ),
          ),
          child: Tooltip(
            message: item.label,
            child: Column(
              children: [
                Icon(item.icon, color: Colors.white, size: 20),
                if (!isCollapsed) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: item.isActive ? FontWeight.w800 : FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminConsoleHeader extends StatelessWidget {
  final int pendingOrdersCount;
  final VoidCallback onBrowseInventory;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenSettings;
  final VoidCallback onRefresh;

  const AdminConsoleHeader({
    super.key,
    required this.pendingOrdersCount,
    required this.onBrowseInventory,
    required this.onOpenOrders,
    required this.onOpenSettings,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        final actionRow = compact
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: [
                  _HeaderCircleButton(
                    icon: Icons.search_rounded,
                    onPressed: onBrowseInventory,
                    tooltip: 'Browse products',
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: BadgeIcon(
                        icon: Icons.receipt_long_rounded,
                        count: pendingOrdersCount,
                        color: AppUi.primary,
                        size: 20,
                        onTap: onOpenOrders,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onOpenSettings,
                    child: CircleAvatar(
                      radius: 19,
                      backgroundColor: const Color(0xFFE7F1DE),
                      child: const Icon(Icons.person_rounded, color: AppUi.primary),
                    ),
                  ),
                  _HeaderCircleButton(
                    icon: Icons.refresh_rounded,
                    onPressed: onRefresh,
                    tooltip: 'Refresh',
                  ),
                ],
              )
            : Row(
                children: [
                  _HeaderCircleButton(
                    icon: Icons.search_rounded,
                    onPressed: onBrowseInventory,
                    tooltip: 'Browse products',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: BadgeIcon(
                        icon: Icons.receipt_long_rounded,
                        count: pendingOrdersCount,
                        color: AppUi.primary,
                        size: 20,
                        onTap: onOpenOrders,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onOpenSettings,
                    child: CircleAvatar(
                      radius: 19,
                      backgroundColor: const Color(0xFFE7F1DE),
                      child: const Icon(Icons.person_rounded, color: AppUi.primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _HeaderCircleButton(
                    icon: Icons.refresh_rounded,
                    onPressed: onRefresh,
                    tooltip: 'Refresh',
                  ),
                ],
              );

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(238),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withAlpha(220)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAF2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset('assets/logo.png'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fresh Market',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppUi.primary,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Admin dashboard',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFF6F7669),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    actionRow,
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAF2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.asset('assets/logo.png'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fresh Market',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppUi.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Admin dashboard',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF6F7669),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    actionRow,
                  ],
                ),
        );
      },
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _HeaderCircleButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F7F0),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: AppUi.primary, size: 20),
          ),
        ),
      ),
    );
  }
}

class AdminOverviewCard extends StatelessWidget {
  final AdminOverviewCardData data;

  const AdminOverviewCard({super.key, required this.data});

  ({String label, IconData icon, Color color}) _toneForCard() {
    final text = data.eyebrow.toLowerCase();
    if (text.contains('purchase')) {
      return (
        label: 'Cost',
        icon: Icons.trending_down_rounded,
        color: const Color(0xFFB45309),
      );
    }
    if (text.contains('profit')) {
      return (
        label: 'Up',
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF2E7D32),
      );
    }
    if (text.contains('sales')) {
      return (
        label: 'Flow',
        icon: Icons.insights_rounded,
        color: const Color(0xFF1E88E5),
      );
    }
    return (
      label: 'Live',
      icon: Icons.auto_graph_rounded,
      color: AppUi.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tone = _toneForCard();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [data.startColor, data.endColor],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: data.endColor.withAlpha(36),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.eyebrow,
                        style: TextStyle(
                          color: Colors.black.withAlpha(130),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: tone.color.withAlpha(28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(tone.icon, size: 13, color: tone.color),
                          const SizedBox(width: 4),
                          Text(
                            tone.label,
                            style: TextStyle(
                              color: tone.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data.value,
                  style: const TextStyle(
                    color: AppUi.dark,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MiniTrendBars(color: tone.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.caption,
                        style: TextStyle(
                          color: Colors.black.withAlpha(155),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(110),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(data.icon, color: AppUi.primary, size: 30),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tone.color.withAlpha(220),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTrendBars extends StatelessWidget {
  final Color color;

  const _MiniTrendBars({required this.color});

  @override
  Widget build(BuildContext context) {
    final shades = [
      color.withAlpha(120),
      color.withAlpha(170),
      color.withAlpha(220),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            width: 5,
            height: 8 + (i * 4),
            decoration: BoxDecoration(
              color: shades[i],
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i != 2) const SizedBox(width: 3),
        ],
      ],
    );
  }
}
class AdminRecentOrdersPanel extends StatelessWidget {
  final List<AdminRecentOrderData> orders;
  final VoidCallback onViewAll;

  const AdminRecentOrdersPanel({
    super.key,
    required this.orders,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminPanelShell(
      title: 'Recent Orders',
      actionLabel: 'View all',
      onAction: onViewAll,
      child: orders.isEmpty
          ? const _EmptyPanelMessage(message: 'No orders available yet.')
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'Customer / Product',
                          style: TextStyle(
                            color: Color(0xFF7A7F74),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Date',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF7A7F74),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Total',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Color(0xFF7A7F74),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...orders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8F3),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.customer,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppUi.dark,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  order.product,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF6E7469),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              order.dateLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF58614F),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              order.amountLabel,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: AppUi.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class AdminTopProductsPanel extends StatelessWidget {
  final List<AdminTopProductData> products;
  final VoidCallback onViewAll;

  const AdminTopProductsPanel({
    super.key,
    required this.products,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminPanelShell(
      title: 'Top Selling Products',
      actionLabel: 'Manage',
      onAction: onViewAll,
      child: products.isEmpty
          ? const _EmptyPanelMessage(message: 'Sales data will appear here once orders are placed.')
          : Column(
              children: products
                  .map(
                    (product) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8F3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 56,
                                height: 56,
                                color: const Color(0xFFE8EEDC),
                                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                                    ? Image.network(
                                        product.imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => const Icon(
                                          Icons.local_grocery_store_rounded,
                                          color: AppUi.primary,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.local_grocery_store_rounded,
                                        color: AppUi.primary,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppUi.dark,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    product.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF6E7469),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              product.priceLabel,
                              style: const TextStyle(
                                color: AppUi.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF98A08E),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _AdminPanelShell extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  const _AdminPanelShell({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EDE2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppUi.dark,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    color: AppUi.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  final String message;

  const _EmptyPanelMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF6E7469),
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }
}



