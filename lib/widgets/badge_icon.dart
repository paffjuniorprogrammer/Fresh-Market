import 'package:flutter/material.dart';

/// A reusable icon with a red count badge. Shows nothing when [count] is zero.
class BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  const BadgeIcon({
    super.key,
    required this.icon,
    required this.count,
    this.color = Colors.black,
    this.size = 26,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: size, color: color),
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );

    if (onTap != null) {
      return IconButton(
        onPressed: onTap,
        icon: badge,
        tooltip: count > 0 ? '$count pending' : null,
        padding: const EdgeInsets.all(8),
      );
    }
    return badge;
  }
}
