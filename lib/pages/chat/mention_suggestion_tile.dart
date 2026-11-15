// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A user or room in the mention suggestions. The avatar colour comes from the
/// Matrix ID: the display name belongs to whoever set it.
class MentionSuggestionTile extends StatelessWidget {
  final Map<String, String?> suggestion;
  final Client? client;
  final double size;
  final VoidCallback onTap;

  const MentionSuggestionTile({
    required this.suggestion,
    required this.client,
    required this.size,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final mxid = suggestion['mxid'];
    return ListTile(
      onTap: onTap,
      leading: Avatar(
        mxContent: Uri.tryParse(suggestion['avatar_url'] ?? ''),
        name: suggestion['displayname'] ?? mxid,
        colorSeed: mxid,
        size: size,
        client: client,
      ),
      title: Text(suggestion['displayname'] ?? mxid ?? ''),
    );
  }
}
