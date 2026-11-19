// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/scheduling/schedule_labels.dart';
import 'package:odango/utils/adaptive_bottom_sheet.dart';
import 'package:odango/utils/scheduling/schedule_time.dart';
import 'package:odango/utils/scheduling/scheduled_store.dart';

/// The schedule picker (mockup screen 04): presets, three wheels and one
/// button. Resolves with the chosen time, or null when closed.
Future<DateTime?> showScheduleSheet(
  BuildContext context, {
  required String preview,
  required ScheduledMode mode,
  required bool encrypted,
  DateTime? initial,
  DateTime Function()? now,
}) => showAdaptiveBottomSheet<DateTime>(
  context: context,
  maxHeight: AppSchedule.sheetMaxHeight,
  builder: (context) => ScheduleSheet(
    preview: preview,
    mode: mode,
    encrypted: encrypted,
    initial: initial,
    now: now,
  ),
);

class ScheduleSheet extends StatefulWidget {
  const ScheduleSheet({
    required this.preview,
    required this.mode,
    required this.encrypted,
    this.initial,
    this.now,
    super.key,
  });

  final String preview;
  final ScheduledMode mode;
  final bool encrypted;
  final DateTime? initial;
  final DateTime Function()? now;

  @override
  State<ScheduleSheet> createState() => ScheduleSheetController();
}

class ScheduleSheetController extends State<ScheduleSheet> {
  static const dayCount = ScheduleRules.maxDays + 1;
  static const hourCount = 24;
  static const minuteCount = 60 ~/ ScheduleRules.minuteStep;

  late final DateTime opened;
  late final FixedExtentScrollController dayWheel;
  late final FixedExtentScrollController hourWheel;
  late final FixedExtentScrollController minuteWheel;
  late int _day;
  late int _hour;
  late int _minute;
  SchedulePreset? preset;
  var stale = false;

  DateTime now() => (widget.now ?? DateTime.now)();

  DateTime get at => ScheduleRules.fromWheel(
    opened,
    day: _day,
    hour: _hour,
    minuteIndex: _minute,
  );

  ScheduleValidity get validity => ScheduleRules.validate(at, now());

  bool get reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    opened = now();
    final wanted = widget.initial;
    final start =
        wanted == null || ScheduleRules.validate(wanted, opened) != .ok
        ? ScheduleRules.initial(opened)
        : wanted;
    final wheel = ScheduleRules.toWheel(opened, start);
    _day = wheel.day.clamp(0, dayCount - 1);
    _hour = wheel.hour;
    _minute = wheel.minuteIndex;
    dayWheel = FixedExtentScrollController(initialItem: _day);
    hourWheel = FixedExtentScrollController(initialItem: _hour);
    minuteWheel = FixedExtentScrollController(initialItem: _minute);
    preset = _presetOf(at);
  }

  @override
  void dispose() {
    dayWheel.dispose();
    hourWheel.dispose();
    minuteWheel.dispose();
    super.dispose();
  }

  SchedulePreset? _presetOf(DateTime time) {
    for (final entry in ScheduleRules.presets(now()).entries) {
      if (entry.value == time) return entry.key;
    }
    return null;
  }

  void onDayChanged(int value) => _changed(() => _day = value);
  void onHourChanged(int value) => _changed(() => _hour = value);
  void onMinuteChanged(int value) => _changed(() => _minute = value);

  void _changed(VoidCallback update) => setState(() {
    update();
    preset = _presetOf(at);
    stale = false;
  });

  void selectPreset(SchedulePreset value) {
    final target = ScheduleRules.presets(now())[value];
    if (target == null) return;
    final wheel = ScheduleRules.toWheel(opened, target);
    _move(dayWheel, wheel.day.clamp(0, dayCount - 1));
    _move(hourWheel, wheel.hour);
    _move(minuteWheel, wheel.minuteIndex);
    setState(() => preset = value);
  }

  void _move(FixedExtentScrollController wheel, int item) {
    if (reduceMotion) return wheel.jumpToItem(item);
    wheel.animateToItem(
      item,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void close() => Navigator.of(context).pop();

  void confirm() {
    if (validity != .ok) {
      setState(() => stale = true);
      return;
    }
    Navigator.of(context).pop(at);
  }

  @override
  Widget build(BuildContext context) => ScheduleSheetView(this);
}

class ScheduleSheetView extends StatelessWidget {
  const ScheduleSheetView(this.controller, {super.key});

  final ScheduleSheetController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final widget = c.widget;
    final now = c.now();
    final validity = c.validity;
    final presets = ScheduleRules.presets(now);
    final labels = {
      SchedulePreset.inOneHour: l10n.scheduleIn1Hour,
      SchedulePreset.thisEvening: l10n.scheduleThisEvening,
      SchedulePreset.tomorrowMorning: l10n.scheduleTomorrowMorning,
      SchedulePreset.nextWeek: l10n.scheduleNextWeek,
    };
    final warning = switch (validity) {
      ScheduleValidity.tooSoon => l10n.scheduleTooSoon,
      ScheduleValidity.tooFar => l10n.scheduleTooFar,
      ScheduleValidity.ok => null,
    };
    return Material(
      color: tokens.surf,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.only(
            start: 16,
            end: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: AppSchedule.sheetHandleWidth,
                  height: AppSchedule.sheetHandleHeight,
                  margin: const EdgeInsetsDirectional.only(top: 10, bottom: 12),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.scheduleMessage,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: l10n.close,
                      onTap: c.close,
                      excludeSemantics: true,
                      child: InkResponse(
                        key: const ValueKey('schedule_close'),
                        onTap: c.close,
                        radius: 22,
                        child: SizedBox.square(
                          dimension: 44,
                          child: Center(
                            child: Container(
                              width: AppSchedule.closeButton,
                              height: AppSchedule.closeButton,
                              decoration: BoxDecoration(
                                color: tokens.surf2,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: tokens.fg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 4,
                  end: 4,
                  bottom: 14,
                ),
                child: Text(
                  '"${widget.preview}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.mut, fontSize: 13.5),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 16),
                child: Wrap(
                  spacing: AppSchedule.presetGap,
                  runSpacing: AppSchedule.presetGap,
                  children: [
                    for (final entry in presets.entries)
                      _PresetChip(
                        key: ValueKey('schedule_preset_${entry.key.name}'),
                        title: labels[entry.key]!,
                        subtitle: schedulePresetSubtitle(
                          context,
                          entry.value,
                          now,
                        ),
                        selected: c.preset == entry.key,
                        onTap: () => c.selectPreset(entry.key),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 4,
                  end: 4,
                  bottom: 6,
                ),
                child: Text(
                  l10n.scheduleCustom.toUpperCase(),
                  style: TextStyle(
                    color: tokens.mut,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.48,
                  ),
                ),
              ),
              _Wheels(controller: c),
              _InfoRow(
                icon: widget.mode == ScheduledMode.server
                    ? Icons.info_outline_rounded
                    : Icons.warning_amber_rounded,
                iconColor: widget.mode == ScheduledMode.server
                    ? tokens.mut
                    : tokens.warn,
                text: widget.mode == ScheduledMode.server
                    ? l10n.scheduleServerNote
                    : l10n.scheduleDeviceNote,
              ),
              if (widget.mode == ScheduledMode.server && widget.encrypted)
                _InfoRow(
                  icon: Icons.lock_outline_rounded,
                  iconColor: tokens.mut,
                  text: l10n.scheduleEncryptedNote,
                ),
              if (warning != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 4,
                    end: 4,
                    bottom: 10,
                  ),
                  child: Text(
                    warning,
                    key: const ValueKey('schedule_warning'),
                    style: TextStyle(color: tokens.red, fontSize: 13),
                  ),
                ),
              _PrimaryButton(
                label: l10n.scheduleForDate(scheduleFullLabel(context, c.at)),
                enabled: validity == ScheduleValidity.ok,
                onTap: c.confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final width =
        (MediaQuery.sizeOf(context).width.clamp(0, 480) -
            32 -
            AppSchedule.presetGap) /
        2;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? tokens.accs : tokens.surf2,
        borderRadius: BorderRadius.circular(AppSchedule.presetRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSchedule.presetRadius),
          child: Container(
            width: width,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSchedule.presetRadius),
              border: selected
                  ? Border.all(color: tokens.acc, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? tokens.acc : tokens.fg,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: tokens.mut, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wheels extends StatelessWidget {
  const _Wheels({required this.controller});

  final ScheduleSheetController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final now = c.opened;
    return Container(
      height: AppSchedule.wheelRow * AppSchedule.wheelRows + 12,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surf2,
        borderRadius: BorderRadius.circular(AppSchedule.wheelRadius),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: AppSchedule.wheelHighlightHeight,
            decoration: BoxDecoration(
              color: tokens.surf,
              borderRadius: BorderRadius.circular(
                AppSchedule.wheelHighlightRadius,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 16,
                child: _Wheel(
                  key: const ValueKey('schedule_wheel_day'),
                  controller: c.dayWheel,
                  count: ScheduleSheetController.dayCount,
                  fontSize: 16,
                  semanticsLabel: l10n.dayWheel,
                  label: (i) => scheduleDayLabel(
                    context,
                    DateTime(now.year, now.month, now.day + i),
                    now,
                  ),
                  onChanged: c.onDayChanged,
                ),
              ),
              Expanded(
                flex: 10,
                child: _Wheel(
                  key: const ValueKey('schedule_wheel_hour'),
                  controller: c.hourWheel,
                  count: ScheduleSheetController.hourCount,
                  fontSize: 18,
                  semanticsLabel: l10n.hourWheel,
                  label: (i) => i.toString().padLeft(2, '0'),
                  onChanged: c.onHourChanged,
                ),
              ),
              Expanded(
                flex: 10,
                child: _Wheel(
                  key: const ValueKey('schedule_wheel_minute'),
                  controller: c.minuteWheel,
                  count: ScheduleSheetController.minuteCount,
                  fontSize: 18,
                  semanticsLabel: l10n.minuteWheel,
                  label: (i) =>
                      (i * ScheduleRules.minuteStep).toString().padLeft(2, '0'),
                  onChanged: c.onMinuteChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.count,
    required this.fontSize,
    required this.semanticsLabel,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final FixedExtentScrollController controller;
  final int count;
  final double fontSize;
  final String semanticsLabel;
  final String Function(int index) label;
  final ValueChanged<int> onChanged;

  static double opacityFor(double distance) {
    if (distance <= 1) return 1 - 0.55 * distance;
    if (distance <= 2) return 0.45 - 0.25 * (distance - 1);
    return 0.2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    void jump(int delta) {
      final next = (controller.selectedItem + delta).clamp(0, count - 1);
      controller.jumpToItem(next);
    }

    final current = controller.hasClients
        ? controller.selectedItem
        : controller.initialItem;
    return Semantics(
      label: semanticsLabel,
      value: label(current),
      increasedValue: label((current + 1).clamp(0, count - 1)),
      decreasedValue: label((current - 1).clamp(0, count - 1)),
      onIncrease: () => jump(1),
      onDecrease: () => jump(-1),
      child: ExcludeSemantics(
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: AppSchedule.wheelRow,
          physics: const FixedExtentScrollPhysics(),
          diameterRatio: 100,
          perspective: 0.0001,
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count,
            builder: (context, index) => AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final position = controller.hasClients
                    ? controller.offset / AppSchedule.wheelRow
                    : controller.initialItem.toDouble();
                final distance = (index - position).abs();
                return Center(
                  child: Opacity(
                    opacity: opacityFor(distance),
                    child: Text(
                      label(index),
                      style: TextStyle(
                        color: tokens.fg,
                        fontSize: fontSize,
                        fontWeight: distance < 0.5
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 14, end: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.m,
        children: [
          Icon(icon, size: 19, color: iconColor),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tokens.mut, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 14),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        onTap: enabled ? onTap : null,
        child: Material(
          color: enabled ? tokens.acc : tokens.surf2,
          borderRadius: BorderRadius.circular(AppSchedule.primaryButton / 2),
          child: InkWell(
            key: const ValueKey('schedule_confirm'),
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppSchedule.primaryButton / 2),
            child: SizedBox(
              height: AppSchedule.primaryButton,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: AppSpacing.s,
                children: [
                  Icon(
                    Icons.schedule_send_rounded,
                    size: 21,
                    color: enabled ? tokens.onacc : tokens.mut,
                  ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? tokens.onacc : tokens.mut,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
