import 'package:flutter/material.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../lock_copy.dart';
import 'lock_fields.dart';
import 'lock_parts.dart';

class LockDangerGate extends StatelessWidget {
  const LockDangerGate({
    super.key,
    required this.headline,
    required this.confirmController,
    required this.isConfirmed,
    required this.backupController,
    required this.onBackupChanged,
    required this.onSaveCopy,
    required this.backupBusy,
    required this.backupDone,
    required this.backupError,
    required this.onConfirmChanged,
  });

  final String headline;
  final TextEditingController confirmController;
  final bool isConfirmed;
  final TextEditingController backupController;
  final ValueChanged<String> onBackupChanged;
  final VoidCallback onSaveCopy;
  final bool backupBusy;
  final bool backupDone;
  final String? backupError;
  final ValueChanged<String> onConfirmChanged;

  static String savedText() => skyCalmText(BackupMessages.rescueSaved);

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final body = SkyType.bodySmall.copyWith(color: t.text);
    final inner = t.isNight ? const Color(0xD9110F33) : SkyTokens.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.isNight
            ? Color.alphaBlend(t.roseSoft, const Color(0xF0141238))
            : Color.alphaBlend(t.roseSoft, t.surface),
        borderRadius: SkyRadii.all(SkyRadii.card),
        border: Border.all(color: t.rose.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SkyIcon(SkyIcons.alert, size: 20, color: t.rose),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LockCopy.dangerLabel.toUpperCase(), style: SkyType.label.copyWith(color: t.rose)),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$headline${LockCopy.dangerBodyMiddle}'),
                          const TextSpan(text: LockCopy.dangerBodyStrong, style: lockStrong),
                          const TextSpan(text: LockCopy.dangerBodyRest),
                        ],
                      ),
                      style: body,
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(text: LockCopy.dangerStopLead),
                          TextSpan(text: LockCopy.dangerStopStrong, style: lockStrong),
                          TextSpan(text: LockCopy.dangerStopRest),
                        ],
                      ),
                      style: body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: inner,
              borderRadius: SkyRadii.all(SkyRadii.tile),
              border: Border.all(color: t.chipBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SkyIcon(SkyIcons.box, size: 16, color: t.gold),
                    const SizedBox(width: 8),
                    Text(LockCopy.saveFirstTitle, style: SkyType.bodyStrong.copyWith(color: t.text, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(LockCopy.saveFirstBody, style: SkyType.small.copyWith(color: t.muted)),
                const SizedBox(height: 10),
                LockField(
                  controller: backupController,
                  hint: LockCopy.saveFirstHint,
                  obscure: true,
                  revealToggle: false,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: onBackupChanged,
                  semanticLabel: LockCopy.saveFirstHint,
                ),
                const SizedBox(height: 10),
                SkyButton(
                  label: LockCopy.saveFirstButton,
                  busyLabel: LockCopy.saving,
                  busy: backupBusy,
                  variant: SkyButtonVariant.gold,
                  icon: SkyIcons.box,
                  height: SkySizes.buttonCompact,
                  onPressed: onSaveCopy,
                ),
                if (backupDone) ...[
                  const SizedBox(height: 10),
                  SkyEntrance(
                    child: _Status(text: savedText(), icon: SkyIcons.check, color: t.gold),
                  ),
                ],
                if (backupError != null) ...[
                  const SizedBox(height: 10),
                  SkyEntrance(
                    child: _Status(text: skyCalmText(backupError!), icon: SkyIcons.alert, color: t.rose),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: LockCopy.typeLead),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.roseSoft,
                        borderRadius: SkyRadii.all(SkyRadii.xs),
                        border: Border.all(color: t.roseBorder),
                      ),
                      child: Text(
                        destroyConfirmationPhrase,
                        style: SkyType.sans(11, weight: FontWeight.w700, letterSpacing: 0.8).copyWith(color: t.rose),
                      ),
                    ),
                  ),
                  const TextSpan(text: LockCopy.typeRest),
                ],
              ),
              style: SkyType.sans(12.5, weight: FontWeight.w600).copyWith(color: t.text),
            ),
          ),
          LockField(
            controller: confirmController,
            hint: destroyConfirmationPhrase,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            phrase: true,
            highlight: isConfirmed,
            onChanged: onConfirmChanged,
            semanticLabel: '${LockCopy.typeLead}$destroyConfirmationPhrase${LockCopy.typeRest}',
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text, required this.icon, required this.color});

  final String text;
  final SkyIcons icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SkyIcon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: SkyType.sans(12, weight: FontWeight.w600).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
