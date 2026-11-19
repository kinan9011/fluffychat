// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/utils/launch_web_url.dart';

const _maxServiceUrlLength = 2048;

/// The LiveKit service URL comes from the homeserver's well-known or from a
/// call member's state, and an OpenID token is sent to it: only https URLs
/// with a host and no credentials are accepted, plain http only for the local
/// machine.
Uri? safeLiveKitServiceUri(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty || trimmed.length > _maxServiceUrlLength) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  if (!isLaunchableWebUrl(trimmed)) return null;
  if (uri.scheme.toLowerCase() == 'http' && !_isLoopback(uri.host)) return null;
  return uri;
}

bool _isLoopback(String host) =>
    host == 'localhost' ||
    host == '::1' ||
    RegExp(r'^127(\.\d{1,3}){3}$').hasMatch(host);
