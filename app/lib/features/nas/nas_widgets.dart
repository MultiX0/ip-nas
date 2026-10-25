// Small shared pieces of the NAS screens: cards, state chips, dialogs and number formatting.
import 'package:flutter/material.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_charts.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';

String formatBytes(num? b, {int digits = 1}) {
  if (b == null) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : digits)} ${units[i]}';
}

String formatUptime(num? seconds) {
  if (seconds == null) return '-';
  final d = Duration(seconds: seconds.toInt());
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

void showSnack(BuildContext context, String text) => showNurToast(context, text, kind: toastKindOf(text));

Future<bool> confirmDialog(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: danger ? const Icon(NurIcons.warning, color: NurColors.danger, size: 26) : null,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: NurColors.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

class NurCard extends StatelessWidget {
  const NurCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return NurPressable(
      onTap: onTap,
      color: dark ? NurColors.g850.withValues(alpha: 0.55) : Colors.white,
      hoverColor: dark ? NurColors.g800 : NurColors.g50,
      borderRadius: BorderRadius.circular(NurRadius.card),
      border: Border.all(color: scheme.outlineVariant),
      pressedScale: 0.99,
      padding: padding,
      child: child,
    );
  }
}

class StateChip extends StatelessWidget {
  const StateChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.nur.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

class Meter extends StatelessWidget {
  const Meter({super.key, required this.value, this.height = 6});
  final double value;
  final double height;
  @override
  Widget build(BuildContext context) => UsageBar(value: value, height: height);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action, this.tone});
  final Color? tone;
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => NurEmptyState(icon: icon, title: title, body: body, action: action, tone: tone);
}

class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: NurPressable(
              onTap: () => onChanged(i),
              borderRadius: BorderRadius.circular(NurRadius.pill),
              color: i == index ? scheme.primary : Colors.transparent,
              hoverColor: i == index ? scheme.primary : null,
              border: Border.all(color: i == index ? scheme.primary : scheme.outlineVariant),
              pressedScale: 0.96,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: NurMotion.base,
                style: TextStyle(
                  fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  fontFamilyFallback: DefaultTextStyle.of(context).style.fontFamilyFallback,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: i == index ? scheme.onPrimary : scheme.onSurface,
                ),
                child: Text(labels[i]),
              ),
            ),
          ),
      ]),
    );
  }
}
