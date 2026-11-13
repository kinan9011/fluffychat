// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class OwnAvatar extends StatefulWidget {
  final double size;

  const OwnAvatar({this.size = Avatar.defaultSize, super.key});

  @override
  State<OwnAvatar> createState() => _OwnAvatarState();
}

class _OwnAvatarState extends State<OwnAvatar> {
  final List<StreamSubscription<Client>> _subscriptions = [];
  Future<Profile>? _profile;

  @override
  void initState() {
    super.initState();
    final matrix = Matrix.of(context);
    _subscriptions.addAll([
      matrix.onActiveClientChanged.listen((_) => setState(_reload)),
      matrix.onOwnProfileChanged.listen(
        (_) => setState(() => _reload(fromServer: true)),
      ),
    ]);
    _reload();
  }

  void _reload({bool fromServer = false}) {
    final client = Matrix.of(context).activeClientOrNull;
    _profile = client == null || !client.isLogged()
        ? null
        : fromServer
        ? client.getProfileFromUserId(
            client.userID!,
            maxCacheAge: Duration.zero,
          )
        : client.fetchOwnProfile();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).activeClientOrNull;
    if (client == null) return SizedBox.square(dimension: widget.size);
    return FutureBuilder<Profile>(
      future: _profile,
      builder: (context, snapshot) => Avatar(
        mxContent: snapshot.data?.avatarUrl,
        name: snapshot.data?.displayName ?? client.userID?.localpart,
        colorSeed: client.userID,
        size: widget.size,
      ),
    );
  }
}
