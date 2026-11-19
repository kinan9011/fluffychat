// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/config/setting_keys.dart';

enum DocsPage { push, encryption, stickers }

/// Help pages live on the website of the app, never on a page of another
/// project or person.
Uri docsUrl(DocsPage page) => Uri.https(
  Uri.tryParse(AppSettings.website.value)?.host ?? '',
  '/docs/${page.name}',
);
