// Asks the user before a risky tool runs.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/contracts/intelligence.dart';
import '../../../core/layout/desktop.dart';
import '../../../core/theme/nur_theme.dart';
import '../../../core/widgets/nur_icons.dart';
import '../../../core/widgets/nur_ui.dart';
import '../engine/live_store.dart';

String _pretty(String json) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
  } catch (_) {
    return json;
  }
}

Future<bool> showApprovalSheet(BuildContext context, ApprovalRequest r) async {
  final dangerous = r.risk == ToolRisk.dangerous;
  final args = _pretty(r.call.argumentsJson);
  final ok = await showAdaptiveSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconTile(
              dangerous ? NurIcons.warning : NurIcons.shield,
              size: 36,
              color: dangerous ? NurColors.danger : NurColors.warn,
              background: (dangerous ? NurColors.danger : NurColors.warn).withValues(alpha: 0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(dangerous ? 'Allow a risky action?' : 'Allow this action?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Nur wants to run the tool "${r.call.name}".', style: TextStyle(color: c.nur.muted)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.35),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.nur.codeBg, borderRadius: BorderRadius.circular(NurRadius.field), border: Border.all(color: Theme.of(c).colorScheme.outlineVariant)),
              child: SingleChildScrollView(
                child: SelectableText(args, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('Deny')))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: dangerous ? FilledButton.styleFrom(backgroundColor: NurColors.danger, foregroundColor: Colors.white) : null,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Allow'),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
  return ok ?? false;
}
