// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/new_private_chat/new_private_chat_view.dart';
import 'package:odango/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:odango/pages/new_private_chat/scan_confirm_sheet.dart';
import 'package:odango/utils/adaptive_bottom_sheet.dart';
import 'package:odango/utils/fluffy_share.dart';
import 'package:odango/utils/links/matrix_link_policy.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/new_message/contact_list.dart';
import 'package:odango/utils/platform_infos.dart';
import 'package:odango/utils/url_launcher.dart';
import 'package:odango/widgets/matrix.dart';

import '../../widgets/adaptive_dialogs/user_dialog.dart';

class NewPrivateChat extends StatefulWidget {
  final String? deeplink;
  const NewPrivateChat({super.key, required this.deeplink});

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();

    final deeplink = widget.deeplink;
    if (deeplink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UrlLauncher(context, deeplink).openMatrixToUrl();
      });
    }
  }

  Future<void> searchUsers([String? input]) async {
    final searchTerm = input ?? controller.text;
    if (searchTerm.isEmpty) {
      _searchCoolDown?.cancel();
      setState(() {
        searchResponse = _searchCoolDown = null;
      });
      return;
    }

    _searchCoolDown?.cancel();
    _searchCoolDown = Timer(_coolDown, () {
      setState(() {
        searchResponse = _searchUser(searchTerm);
      });
    });
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    final result = await Matrix.of(
      context,
    ).client.searchUserDirectory(searchTerm);
    final profiles = result.results;

    if (searchTerm.isValidMatrixIdStrict() &&
        searchTerm.sigil == '@' &&
        !profiles.any((profile) => profile.userId == searchTerm)) {
      profiles.add(Profile(userId: searchTerm));
    }

    return profiles;
  }

  /// The people the user already chats with, from what the client holds.
  List<ContactEntry> get contacts {
    final client = Matrix.of(context).client;
    final locals = MatrixLocals(L10n.of(context));
    return ContactList.build(
      [
        for (final room in client.rooms)
          if (room.membership == Membership.join &&
              room.directChatMatrixID != null)
            ContactSource(
              userId: room.directChatMatrixID!,
              name: room.getLocalizedDisplayname(locals),
              lastActivity: room.latestEventReceivedTime,
            ),
      ],
      // The map only holds what sync delivered. Its replacement,
      // fetchCurrentPresence, asks the server once per person.
      // ignore: deprecated_member_use
      presences: client.presences,
      ownUserId: client.userID ?? '',
    );
  }

  void inviteAction() => FluffyShare.shareInviteLink(context);

  Future<void> openScannerAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (info.version.sdkInt < 21) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.unsupportedAndroidVersionLong)),
        );
        return;
      }
    }
    if (!mounted) return;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (_) => QrScannerModal(onScan: handleScan),
    );
  }

  /// What a scanned code leads to. The text is untrusted: only a plain
  /// Matrix link gets this far, the user is shown where it leads, and only
  /// Open hands it to the same flow that handles links in messages, which
  /// asks again before it joins anything.
  Future<void> handleScan(String raw) async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final target = MatrixLinkPolicy.parse(raw);
    if (target == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.qrNotMatrixLink)),
      );
      return;
    }
    if (!await confirmScannedTarget(context, target) || !mounted) return;
    await UrlLauncher(context, target.normalizedUrl).openMatrixToUrl();
  }

  void openUserModal(Profile profile) =>
      UserDialog.show(context: context, profile: profile);

  @override
  void dispose() {
    _searchCoolDown?.cancel();
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
