import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_date_field.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'milestone_copy.dart';

Future<bool?> showTogetherDateSheet(BuildContext context, {required String startDate}) {
  return showSkySheet<bool>(
    context: context,
    builder: (_) => TogetherDateSheet(startDate: startDate),
  );
}

class TogetherDateSheet extends StatefulWidget {
  const TogetherDateSheet({super.key, required this.startDate});

  final String startDate;

  @override
  State<TogetherDateSheet> createState() => _TogetherDateSheetState();
}

class _TogetherDateSheetState extends State<TogetherDateSheet> {
  late String _date = widget.startDate;
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    final vault = context.read<VaultService>();
    final notices = context.read<AppNotices>();
    setState(() => _busy = true);
    final result = await vault.updateSettings(startDate: _date);
    final error = result.error;
    if (!result.ok && error != null) notices.showVaultWarning(error);
    if (!mounted) return;
    Navigator.of(context).pop(result.ok);
    AppHaptics.celebration();
  }

  @override
  Widget build(BuildContext context) {
    return UsSheetFrame(
      kicker: MilestoneCopy.dayKicker,
      title: MilestoneCopy.dayTitle,
      message: MilestoneCopy.dayMessage,
      children: [
        UsDateField(
          key: UsKeys.togetherDate,
          label: MilestoneCopy.dayField,
          helpText: MilestoneCopy.dayField,
          value: _date,
          onChanged: (date) => setState(() => _date = date),
        ),
        UsSheetActions(
          primary: SkyButton(
            key: UsKeys.togetherSave,
            label: MilestoneCopy.saveDay,
            icon: SkyIcons.heart,
            busy: _busy,
            onPressed: () => unawaited(_save()),
          ),
          secondary: SkyButton(
            label: MilestoneCopy.notNow,
            variant: SkyButtonVariant.ghost,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
