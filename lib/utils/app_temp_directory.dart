// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const appTempDirName = 'fluffychat_tmp';

/// On Linux the temporary directory is the shared /tmp, where another user
/// could have created the directory first and read the decrypted media.
Future<Directory> _defaultBase() => PlatformInfos.isLinux
    ? getApplicationCacheDirectory()
    : getTemporaryDirectory();

/// Decrypted audio and video and voice recordings go here, never into the
/// cache root: Reset and every logout delete this directory, and the share
/// filter can tell it from the copies of the system share sheet.
Future<Directory> appTempDirectory({
  @visibleForTesting Future<Directory> Function() base = _defaultBase,
}) async => Directory(
  p.join((await base()).path, appTempDirName),
).create(recursive: true);

Future<Directory?> appTempDirectoryIfExists({
  @visibleForTesting Future<Directory> Function() base = _defaultBase,
}) async {
  final dir = Directory(p.join((await base()).path, appTempDirName));
  return await dir.exists() ? dir : null;
}

Future<void> deleteAppTempDirectory({
  @visibleForTesting Future<Directory> Function() base = _defaultBase,
}) async {
  final dir = await appTempDirectoryIfExists(base: base);
  await dir?.delete(recursive: true);
}

/// Start-up, before any player or recorder runs: decrypted media of an earlier
/// run does not stay on the disk for the whole login lifetime.
Future<void> sweepAppTempDirectory({
  @visibleForTesting Future<Directory> Function() base = _defaultBase,
}) async {
  if (kIsWeb) return;
  try {
    await deleteAppTempDirectory(base: base);
  } catch (e) {
    Logs().w('Unable to sweep the app temp directory', e.runtimeType);
  }
}
