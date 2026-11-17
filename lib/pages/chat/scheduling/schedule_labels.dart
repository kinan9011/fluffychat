// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/scheduling/scheduled_messages.dart';
import 'package:fluffychat/utils/scheduling/scheduled_store.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

String _language(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// "Today", "Tomorrow", then a short date such as "Fri, Nov 14".
String scheduleDayLabel(BuildContext context, DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(day.year, day.month, day.day);
  final diff = DateTime.utc(
    target.year,
    target.month,
    target.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (diff == 0) return L10n.of(context).today;
  if (diff == 1) return L10n.of(context).tomorrow;
  return DateFormat.MMMEd(_language(context)).format(target);
}

/// "Fri, Nov 14, 09:00".
String scheduleFullLabel(BuildContext context, DateTime at) =>
    '${DateFormat.MMMEd(_language(context)).format(at)}, '
    '${at.localizedTimeOfDay(context)}';

/// A preset's second line: the time today, the weekday and time otherwise.
String schedulePresetSubtitle(BuildContext context, DateTime at, DateTime now) {
  final time = at.localizedTimeOfDay(context);
  if (at.sameDay(now)) return time;
  return '${DateFormat.E(_language(context)).format(at)} $time';
}

String scheduleErrorMessage(L10n l10n, ScheduleException error) =>
    switch (error.error) {
      ScheduleError.tooSoon => l10n.scheduleTooSoon,
      ScheduleError.tooFar =>
        error.maxDays == null
            ? l10n.scheduleTooFar
            : l10n.scheduleTooFarDays(error.maxDays!),
      ScheduleError.unsupported => l10n.scheduleUnsupported,
      ScheduleError.tooMany => l10n.scheduledTooMany,
      ScheduleError.encryptionUnavailable => l10n.scheduleEncryptionUnavailable,
      ScheduleError.storageUnavailable => l10n.scheduleStorageUnavailable,
      ScheduleError.alreadySent => l10n.scheduleAlreadySent,
      ScheduleError.failed => l10n.scheduleFailed,
    };

/// Why a failed entry was not sent. An entry stored without a reason, or with
/// a time-based one but no time, is shown as a send failure.
String scheduleFailureMessage(BuildContext context, ScheduledEntry entry) {
  final l10n = L10n.of(context);
  final at = entry.sendAt;
  return switch (entry.reason) {
    ScheduledFailure.late when at != null => l10n.scheduledMissed(
      at.localizedTimeOfDay(context),
    ),
    ScheduledFailure.roomUnavailable => l10n.scheduledRoomUnavailable,
    ScheduledFailure.rescheduleFailed => l10n.scheduledRescheduleFailed,
    ScheduledFailure.expired => l10n.scheduledExpired,
    _ => l10n.scheduledSendFailed,
  };
}

/// "Fri, Nov 14".
String scheduleDateLabel(BuildContext context, DateTime day) =>
    DateFormat.MMMEd(_language(context)).format(day);
