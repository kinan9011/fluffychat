// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Push needs a gateway that knows this app. Without a valid https gateway
/// push stays off instead of falling back to a host that does not know us.
String? resolvePushGateway(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.path.isEmpty || uri.path == '/') return null;
  return raw;
}
