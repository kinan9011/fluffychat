// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Not zero: an `AnimatedSize` with a zero duration is mutated while it lays
/// out (a Flutter assertion), a millisecond is no visible motion.
const reducedMotionDuration = Duration(milliseconds: 1);

/// [duration], or practically none when the system asks to reduce motion.
Duration motionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? reducedMotionDuration : duration;
