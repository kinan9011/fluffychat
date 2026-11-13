// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The OFL requires the notice to ship with every copy of the fonts.
void registerFontLicenses() => LicenseRegistry.addLicense(() async* {
  for (final (name, asset) in const [
    ('Figtree', 'assets/fonts/Figtree-OFL.txt'),
    ('JetBrains Mono', 'assets/fonts/JetBrainsMono-OFL.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks([
      name,
    ], await rootBundle.loadString(asset));
  }
});
