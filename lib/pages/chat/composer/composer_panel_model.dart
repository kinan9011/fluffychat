// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

enum ComposerPanel { none, format, attach }

/// Which panel is open around the composer; opening one closes the other.
class ComposerPanelModel extends ValueNotifier<ComposerPanel> {
  ComposerPanelModel() : super(ComposerPanel.none);

  void toggle(ComposerPanel panel) =>
      value = value == panel ? ComposerPanel.none : panel;

  void close() => value = ComposerPanel.none;
}
