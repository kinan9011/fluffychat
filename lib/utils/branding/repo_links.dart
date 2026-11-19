// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/config/setting_keys.dart';

/// Every address derived from the project repository. Only a plain GitHub
/// https repository is accepted, so a bad setting can never steer the update
/// check, the issue search or the homeserver list to another host.
class RepoLinks {
  const RepoLinks._(this.owner, this.name);

  final String owner;
  final String name;

  static const defaultRepo = RepoLinks._('swovo', 'odango');

  static final _segment = RegExp(r'^[A-Za-z0-9._-]{1,100}$');

  static RepoLinks? parse(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      return null;
    }
    if (uri.hasPort || uri.hasQuery || uri.hasFragment) return null;
    if (uri.userInfo.isNotEmpty) return null;
    final segments = [...uri.pathSegments];
    if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
    if (segments.length != 2) return null;
    final owner = segments.first;
    final name = segments.last.replaceFirst(RegExp(r'\.git$'), '');
    for (final segment in [owner, name]) {
      if (!_segment.hasMatch(segment) || segment.replaceAll('.', '').isEmpty) {
        return null;
      }
    }
    return RepoLinks._(owner, name);
  }

  /// The configured repository, or null when the setting is not valid.
  static RepoLinks? fromSettings() => parse(AppSettings.repositoryUrl.value);

  /// The repository for requests the app makes on its own (update check,
  /// homeserver list, issue search). The built-in repository is only assumed
  /// to belong to the owner, so nothing is requested until `repositoryConfirmed`
  /// says the owner verified it.
  static RepoLinks? confirmed() =>
      AppSettings.repositoryConfirmed.value ? fromSettings() : null;

  /// For links the user opens by hand: falls back to the default repository.
  static RepoLinks get configured => fromSettings() ?? defaultRepo;

  Uri get page => Uri.https('github.com', '/$owner/$name');
  Uri get issues => Uri.https('github.com', '/$owner/$name/issues');
  Uri get newIssue => Uri.https('github.com', '/$owner/$name/issues/new');
  Uri get releases => Uri.https('github.com', '/$owner/$name/releases');
  Uri get latestReleaseApi =>
      Uri.https('api.github.com', '/repos/$owner/$name/releases/latest');
  Uri get homeserverList => Uri.https(
    'raw.githubusercontent.com',
    '/$owner/$name/refs/heads/main/recommended_homeservers.json',
  );

  Uri searchIssues(String hash) => Uri(
    scheme: 'https',
    host: 'api.github.com',
    path: '/search/issues',
    query:
        'q=repo:$owner/$name+is:issue+${hash.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '')}',
  );
}
