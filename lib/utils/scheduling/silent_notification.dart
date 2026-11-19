// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/utils/scheduling/scheduled_content.dart';

/// Whether a notification for [event] is shown without sound or vibration.
///
/// The flag only ever lowers the volume of a plain message: a message that
/// highlights me (mention, keyword), a call, or anything this client could
/// not read stays loud, and the notification itself is never hidden. Any
/// sender can set the flag, so it must never be able to do more than that.
bool notifySilently(Event event, {required bool highlight}) =>
    !highlight &&
    event.type == EventTypes.Message &&
    ScheduledContent.isSilent(event.content);
