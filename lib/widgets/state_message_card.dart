import 'package:flutter/material.dart';
import '../utils/app_ui.dart';

class StateMessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<String>? details;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const StateMessageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.details,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: AppUi.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SelectableText(message),
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...details!.map(
                (detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.arrow_right_alt, size: 18),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: SelectableText(detail)),
                    ],
                  ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  onAction!();
                },
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
