// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:odango/utils/branding/repo_links.dart';

const windowsInstallerAssetName = 'odango-windows-x64-setup.exe';

class AvailableUpdate {
  const AvailableUpdate(this.version, this.downloadUrl);

  final String version;
  final String downloadUrl;
}

List<int>? _numbers(String version) {
  final parts = version
      .split(RegExp('[+-]'))
      .first
      .split('.')
      .map(int.tryParse)
      .toList();
  return parts.contains(null) ? null : parts.cast<int>();
}

bool _isNewer(String latest, String current) {
  final latestParts = _numbers(latest);
  final currentParts = _numbers(current);
  if (latestParts == null || currentParts == null) return false;
  final length = latestParts.length > currentParts.length
      ? latestParts.length
      : currentParts.length;
  for (var i = 0; i < length; i++) {
    final a = i < latestParts.length ? latestParts[i] : 0;
    final b = i < currentParts.length ? currentParts[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Asks the latest release of the configured repository whether a newer
/// Windows installer exists. Without a valid repository nothing is requested.
Future<AvailableUpdate?> checkForUpdate({
  required http.Client client,
  required RepoLinks? repo,
  required String currentVersion,
}) async {
  if (repo == null) return null;
  try {
    final response = await client.get(
      repo.latestReleaseApi,
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) return null;
    final release = jsonDecode(response.body) as Map<String, Object?>;
    final version = (release['tag_name'] as String).replaceFirst(
      RegExp('^v'),
      '',
    );
    final installer = (release['assets'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((asset) => asset['name'] == windowsInstallerAssetName);
    final downloadUrl = installer['browser_download_url'] as String;
    final download = Uri.parse(downloadUrl);
    final trusted =
        download.scheme == 'https' &&
        download.host == 'github.com' &&
        download.path.startsWith(
          '/${repo.owner}/${repo.name}/releases/download/',
        );
    if (!trusted || !_isNewer(version, currentVersion)) return null;
    return AvailableUpdate(version, downloadUrl);
  } catch (e, s) {
    Logs().w('Unable to check for updates', e, s);
    return null;
  }
}
