import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  final String id, title, subtitle;
  final IconData icon;
  final List<Widget> children;
  const SettingsSection({
    super.key,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('settings-section-$id'),
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}
