// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart' show IterableExtension;
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/link_scheme_policy.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:punycode/punycode.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../widgets/adaptive_dialogs/public_room_dialog.dart';
import 'platform_infos.dart';

const _maxSnackBarUrlLength = 200;

const _invisibleRuneRanges = <(int, int)>[
  (0x0000, 0x001F),
  (0x007F, 0x009F),
  (0x00AD, 0x00AD),
  (0x034F, 0x034F),
  (0x061C, 0x061C),
  (0x115F, 0x1160),
  (0x17B4, 0x17B5),
  (0x180B, 0x180E),
  (0x200B, 0x200F),
  (0x2028, 0x202E),
  (0x2060, 0x2069),
  (0x3164, 0x3164),
  (0xFE00, 0xFE0F),
  (0xFEFF, 0xFEFF),
  (0xFFA0, 0xFFA0),
  (0xFFF9, 0xFFFB),
  (0xE0000, 0xE007F),
];

String punycodeHost(String host) {
  try {
    return host
        .split('.')
        .map((hostPartEncoded) {
          final hostPart = Uri.decodeComponent(hostPartEncoded);
          final hostPartPunycode = punycodeEncode(hostPart);
          return hostPartPunycode != '$hostPart-'
              ? 'xn--$hostPartPunycode'
              : hostPart;
        })
        .join('.');
  } catch (_) {
    return host;
  }
}

/// The URL as it is shown to the user before opening it: web hosts are
/// punycode-encoded like the launched URL, invisible and bidi runes are made
/// visible.
@visibleForTesting
String displayUrl(String url) {
  final uri = Uri.tryParse(url);
  final text =
      uri != null &&
          linkSchemeAction(uri) == LinkSchemeAction.web &&
          uri.host.isNotEmpty
      ? uri.replace(host: punycodeHost(uri.host)).toString()
      : url;
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final invisible = _invisibleRuneRanges.any(
      (r) => rune >= r.$1 && rune <= r.$2,
    );
    if (invisible) {
      buffer.write(
        '<U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}>',
      );
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

String _shortened(String url) => url.length <= _maxSnackBarUrlLength
    ? url
    : '${url.substring(0, _maxSnackBarUrlLength)}…';

class UrlLauncher {
  /// The url to open.
  final String? url;

  /// The visible name in the GUI. For example the name of a markdown link
  /// which may differ from the actual url to open.
  final String? name;

  final BuildContext context;

  const UrlLauncher(this.context, this.url, [this.name]);

  Future<void> launchUrl() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (url == null || url!.trim().isEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.cantOpenUri(displayUrl(url ?? '')))),
      );
      return;
    }
    if (url!.toLowerCase().startsWith(AppConfig.deepLinkPrefix) ||
        url!.toLowerCase().startsWith(AppConfig.inviteLinkPrefix) ||
        {'#', '@', '!', '+', '\$'}.contains(url![0]) ||
        url!.toLowerCase().startsWith(AppConfig.schemePrefix)) {
      return openMatrixToUrl();
    }
    final uri = Uri.tryParse(url!);
    if (uri == null) {
      // we can't open this thing
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.cantOpenUri(displayUrl(url!)))),
      );
      return;
    }

    final action = linkSchemeAction(uri);

    if (action == LinkSchemeAction.block) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.linkSchemeBlocked(_shortened(displayUrl(url!)))),
        ),
      );
      return;
    }

    if (action == LinkSchemeAction.confirm) {
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.openLinkInOtherAppTitle,
        message: l10n.openLinkInOtherAppMessage(displayUrl(url!)),
        okLabel: l10n.open,
        cancelLabel: l10n.cancel,
      );
      if (consent != OkCancelResult.ok) return;
      launchUrlString(url!);
      return;
    }

    if (name != null && url != name) {
      // If there is a name which differs from the url, we need to make sure
      // that the user can see the actual url before opening the browser.
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.openLinkInBrowser,
        message: displayUrl(url!),
        okLabel: l10n.open,
        cancelLabel: l10n.cancel,
      );
      if (consent != OkCancelResult.ok) return;
    }

    if (action != LinkSchemeAction.web) {
      // we need to transmute geo URIs on every platform
      if (action == LinkSchemeAction.geo) {
        final latlong = uri.path
            .split(';')
            .first
            .split(',')
            .map(double.tryParse)
            .toList();
        if (latlong.length == 2 &&
            latlong.first != null &&
            latlong.last != null) {
          if (PlatformInfos.isIOS) {
            // iOS is great at not following standards, so we need to transmute the geo URI
            // to an apple maps thingy
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
            final ll = '${latlong.first},${latlong.last}';
            launchUrlString('https://maps.apple.com/?q=$ll&sll=$ll');
          } else if (PlatformInfos.isAndroid) {
            // Google Maps ignores the coordinates in the path of geo URIs and
            // only shows a pin for the q parameter. The label prevents it from
            // snapping to the nearest place.
            final ll = '${latlong.first},${latlong.last}';
            final label = Uri.encodeComponent(l10n.sharedLocation);
            launchUrlString('geo:$ll?q=$ll($label)');
          } else {
            // transmute geo URIs on desktop to openstreetmap links, as those usually can't handle
            // geo URIs
            launchUrlString(
              'https://www.openstreetmap.org/?mlat=${latlong.first}&mlon=${latlong.last}#map=16/${latlong.first}/${latlong.last}',
            );
          }
          return;
        }
      }
      launchUrlString(url!);
      return;
    }
    if (uri.host.isEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.cantOpenUri(displayUrl(url!)))),
      );
      return;
    }
    // okay, we have either an http or an https URI.
    // As some platforms have issues with opening unicode URLs, we are going to help
    // them out by punycode-encoding them for them ourself.
    final newHost = punycodeHost(uri.host);
    // Force LaunchMode.externalApplication, otherwise url_launcher will default
    // to opening links in a webview on mobile platforms.
    launchUrlString(
      uri.replace(host: newHost).toString(),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> openMatrixToUrl() async {
    final matrix = Matrix.of(context);
    final url = this.url!.replaceFirst(
      AppConfig.deepLinkPrefix,
      AppConfig.inviteLinkPrefix,
    );

    // The identifier might be a matrix.to url and needs escaping. Or, it might have multiple
    // identifiers (room id & event id), or it might also have a query part.
    // All this needs parsing.
    final identityParts =
        url.parseIdentifierIntoParts() ??
        Uri.tryParse(url)?.host.parseIdentifierIntoParts() ??
        Uri.tryParse(url)?.pathSegments
            .lastWhereOrNull((_) => true)
            ?.parseIdentifierIntoParts();
    if (identityParts == null) {
      return; // no match, nothing to do
    }
    if (identityParts.primaryIdentifier.sigil == '#' ||
        identityParts.primaryIdentifier.sigil == '!') {
      // we got a room! Let's open that one
      final roomIdOrAlias = identityParts.primaryIdentifier;
      final event = identityParts.secondaryIdentifier;
      var room =
          matrix.client.getRoomByAlias(roomIdOrAlias) ??
          matrix.client.getRoomById(roomIdOrAlias);
      var roomId = room?.id;
      // we make the servers a set and later on convert to a list, so that we can easily
      // deduplicate servers added via alias lookup and query parameter
      final servers = <String>{};
      if (room == null && roomIdOrAlias.sigil == '#') {
        // we were unable to find the room locally...so resolve it
        final response = await showFutureLoadingDialog(
          context: context,
          future: () => matrix.client.getRoomIdByAlias(roomIdOrAlias),
        );
        final result = response.result;
        if (result != null) {
          roomId = result.roomId;
          servers.addAll(result.servers!);
          room = matrix.client.getRoomById(roomId!);
        }
      }
      servers.addAll(identityParts.via);
      if (!context.mounted) return;
      if (room != null) {
        if (room.isSpace) {
          // TODO: Implement navigate to space
          context.go('/rooms/${room.id}');

          return;
        }
        // we have the room, so....just open it
        if (event != null) {
          context.go(
            '/${Uri(pathSegments: ['rooms', room.id], queryParameters: {'event': event})}',
          );
        } else {
          context.go('/rooms/${room.id}');
        }
        return;
      } else {
        if (!context.mounted) return;
        await showAdaptiveDialog(
          context: context,
          barrierDismissible: true,
          builder: (c) =>
              PublicRoomDialog(roomAlias: identityParts.primaryIdentifier),
        );
      }
      if (roomIdOrAlias.sigil == '!') {
        if (!context.mounted) return;
        if (await showOkCancelAlertDialog(
              useRootNavigator: false,
              context: context,
              title: 'Join room $roomIdOrAlias',
            ) ==
            OkCancelResult.ok) {
          roomId = roomIdOrAlias;
          if (!context.mounted) return;
          final response = await showFutureLoadingDialog(
            context: context,
            future: () => matrix.client.joinRoom(
              roomIdOrAlias,
              via: servers.isNotEmpty ? servers.toList() : null,
            ),
          );
          if (response.error != null) return;
          if (!context.mounted) return;
          // wait for two seconds so that it probably came down /sync
          await showFutureLoadingDialog(
            context: context,
            future: () => Future.delayed(const Duration(seconds: 2)),
          );
          if (!context.mounted) return;
          if (event != null) {
            context.go(
              Uri(
                pathSegments: ['rooms', response.result!],
                queryParameters: {'event': event},
              ).toString(),
            );
          } else {
            context.go('/rooms/${response.result!}');
          }
        }
      }
    } else if (identityParts.primaryIdentifier.sigil == '@') {
      final userId = identityParts.primaryIdentifier;
      var noProfileWarning = false;
      final profileResult = await showFutureLoadingDialog(
        context: context,
        future: () =>
            matrix.client.getProfileFromUserId(userId).catchError((_) {
              noProfileWarning = true;
              return Profile(userId: userId);
            }),
      );
      if (!context.mounted) return;
      await UserDialog.show(
        context: context,
        profile: profileResult.result!,
        noProfileWarning: noProfileWarning,
      );
    }
  }
}
