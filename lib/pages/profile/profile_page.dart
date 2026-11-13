// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/pages/profile/profile_view.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qr_code_viewer.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  ProfileController createState() => ProfileController();
}

class ProfileController extends State<ProfilePage> {
  final List<StreamSubscription<Client>> _subscriptions = [];
  late Future<Profile> profileFuture;

  Client get client => Matrix.of(context).client;

  bool get hasAccount => Matrix.of(context).activeClientOrNull != null;

  void _reload() => profileFuture = client.getProfileFromUserId(
    client.userID!,
    maxCacheAge: Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    final matrix = Matrix.of(context);
    profileFuture = client.fetchOwnProfile();
    _subscriptions.addAll([
      matrix.onActiveClientChanged.listen((_) => setState(_reload)),
      matrix.onOwnProfileChanged.listen((_) => setState(_reload)),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  List<Client> get accounts => Matrix.of(
    context,
  ).widget.clients.where((client) => client.isLogged()).toList();

  void copyMatrixId() =>
      FluffyShare.share(client.userID!, context, copyOnly: true);

  void showQrCode() => showQrCodeViewer(context, client.userID!);

  void addAccount() => context.go('/settings/addaccount');

  void switchAccount(Client other) {
    if (other == client) return;
    Matrix.of(context).setActiveClient(other);
  }

  @override
  Widget build(BuildContext context) =>
      hasAccount ? ProfileView(this) : const SizedBox.shrink();
}
