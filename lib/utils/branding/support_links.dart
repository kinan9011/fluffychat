// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/config/setting_keys.dart';

/// The donation links of this build. A link that is empty or not a plain
/// https address does not exist, so its button is never shown.
class SupportLinks {
  const SupportLinks._(this.koFi, this.buyMeACoffee);

  factory SupportLinks.from({
    required String koFi,
    required String buyMeACoffee,
  }) => SupportLinks._(_parse(koFi), _parse(buyMeACoffee));

  factory SupportLinks.fromSettings() => SupportLinks.from(
    koFi: AppSettings.koFiUrl.value,
    buyMeACoffee: AppSettings.buyMeACoffeeUrl.value,
  );

  final Uri? koFi;
  final Uri? buyMeACoffee;

  bool get hasAny => koFi != null || buyMeACoffee != null;
}

Uri? _parse(String raw) {
  if (raw.isEmpty || raw.length > 2048 || raw != raw.trim()) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri;
}

bool isAcceptableSupportUrl(Object? value) =>
    value is String && (value.isEmpty || _parse(value) != null);
