// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/link_scheme_policy.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

export 'package:url_launcher/url_launcher.dart' show LaunchMode;

bool isLaunchableWebUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      linkSchemeAction(uri) == LinkSchemeAction.web &&
      uri.host.isNotEmpty;
}

/// For URLs from a server, a config file or a remote API, opened without a
/// dialog. Only web URLs are launched.
Future<bool> launchWebUrl(
  String url, {
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  if (!isLaunchableWebUrl(url)) {
    Logs().w('Refused to open a non-web URL');
    return false;
  }
  return launchUrl(Uri.parse(url), mode: mode);
}
