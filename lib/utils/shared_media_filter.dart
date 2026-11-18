// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

const sharedMediaDirName = 'receive_sharing_intent';
const maxSharedFileBytes = 512 * 1024 * 1024;

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The patched share plugin copies every shared file to
/// `<shareRoot>/<uuid>/<name>`. Nothing else the plugin reports is trusted:
/// not raw paths, not the app's own files, not links that lead elsewhere.
@visibleForTesting
bool isPluginShareCopy(String canonicalPath, {required String shareRoot}) {
  final file = p.posix.normalize(canonicalPath);
  if (!p.posix.isAbsolute(file)) return false;
  final dir = p.posix.dirname(file);
  return p.posix.equals(p.posix.dirname(dir), p.posix.normalize(shareRoot)) &&
      _uuid.hasMatch(p.posix.basename(dir));
}

Future<String?> canonicalSharedPath(String path) async {
  try {
    return await File(path).resolveSymbolicLinks();
  } catch (_) {
    return null;
  }
}

Future<int?> sharedFileSize(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return null;
  }
}

Future<List<SharedMediaFile>> filterSharedMedia(
  List<SharedMediaFile> files, {
  required String? shareRoot,
  required Future<String?> Function(String path) canonicalize,
  required Future<int?> Function(String path) fileSize,
}) async {
  final result = <SharedMediaFile>[];
  var dropped = 0;
  for (final file in files) {
    if ({SharedMediaType.text, SharedMediaType.url}.contains(file.type)) {
      result.add(file);
      continue;
    }
    final root = shareRoot;
    final raw = file.path.startsWith('file://')
        ? file.path.substring('file://'.length)
        : file.path;
    final canonical = root == null ? null : await canonicalize(raw);
    if (root == null ||
        canonical == null ||
        !isPluginShareCopy(canonical, shareRoot: root)) {
      dropped++;
      continue;
    }
    final size = await fileSize(canonical);
    if (size == null || size > maxSharedFileBytes) {
      dropped++;
      continue;
    }
    result.add(
      SharedMediaFile(
        path: canonical,
        duration: file.duration,
        type: file.type,
        mimeType: file.mimeType,
        message: file.message,
      ),
    );
  }
  if (dropped > 0) Logs().w('[ShareIntent] dropped $dropped shared files');
  return result;
}

Future<String?> sharedMediaRoot() async {
  final base = PlatformInfos.isIOS
      ? await PathProviderFoundation().getContainerPath(
          appGroupIdentifier: AppConfig.appleAppGroupId,
        )
      : (await getTemporaryDirectory()).path;
  if (base == null) return null;
  final root = await Directory(
    p.join(base, sharedMediaDirName),
  ).create(recursive: true);
  return root.resolveSymbolicLinks();
}

Future<List<SharedMediaFile>> filterSharedFiles(
  List<SharedMediaFile> files, {
  Future<String?> Function() resolveRoot = sharedMediaRoot,
}) async {
  String? root;
  try {
    root = await resolveRoot();
  } catch (e) {
    Logs().w('[ShareIntent] no share directory: ${e.runtimeType}');
  }
  return filterSharedMedia(
    files,
    shareRoot: root,
    canonicalize: canonicalSharedPath,
    fileSize: sharedFileSize,
  );
}

/// Every share leaves a fresh directory behind. Anything the plugin did not
/// put there (links, loose files) is removed whatever its age.
Future<int> deleteStaleSharedCopies(
  String shareRoot, {
  required DateTime cutoff,
}) async {
  var removed = 0;
  await for (final entry in Directory(shareRoot).list(followLinks: false)) {
    final stale =
        entry is! Directory || (await entry.stat()).modified.isBefore(cutoff);
    if (!stale) continue;
    await entry.delete(recursive: true);
    removed++;
  }
  return removed;
}

Future<void> deleteOldSharedCopies({
  Future<String?> Function() resolveRoot = sharedMediaRoot,
}) async {
  try {
    final root = await resolveRoot();
    if (root == null) return;
    await deleteStaleSharedCopies(
      root,
      cutoff: DateTime.now().subtract(const Duration(days: 1)),
    );
  } catch (e) {
    Logs().w(
      '[ShareIntent] unable to clean up old shared files: ${e.runtimeType}',
    );
  }
}
