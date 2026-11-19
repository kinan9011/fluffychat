// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/archive/archive.dart';
import 'package:fluffychat/pages/bootstrap/bootstrap_page.dart';
import 'package:fluffychat/pages/calls/calls_page.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/scheduling/scheduled_messages_page.dart';
import 'package:fluffychat/pages/chat_access_settings/chat_access_settings_controller.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_encryption_settings/chat_encryption_settings.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_members/chat_members.dart';
import 'package:fluffychat/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:fluffychat/pages/chat_search/chat_search_page.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/pages/export/export_page.dart';
import 'package:fluffychat/pages/global_search/global_search.dart';
import 'package:fluffychat/pages/intro/intro_page_presenter.dart';
import 'package:fluffychat/pages/invitation_selection/invitation_selection.dart';
import 'package:fluffychat/pages/login/login.dart';
import 'package:fluffychat/pages/new_group/new_group.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/profile/profile_page.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/pages/settings_appearance/settings_appearance.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:fluffychat/pages/settings_data/settings_data.dart';
import 'package:fluffychat/pages/settings_emotes/settings_emotes.dart';
import 'package:fluffychat/pages/settings_folders/folder_editor.dart';
import 'package:fluffychat/pages/settings_folders/settings_folders.dart';
import 'package:fluffychat/pages/settings_homeserver/homeserver_details.dart';
import 'package:fluffychat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:fluffychat/pages/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/pages/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/pages/settings_password/settings_password.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/pages/sign_in/sign_in_page.dart';
import 'package:fluffychat/pages/space_overview/space_overview.dart';
import 'package:fluffychat/pages/topics/topics_page.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:fluffychat/utils/search/search_sections.dart';
import 'package:fluffychat/utils/spaces/space_hierarchy.dart';
import 'package:fluffychat/utils/spaces/space_trail.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/database_quarantine_banner.dart';
import 'package:fluffychat/widgets/database_unencrypted_warning.dart';
import 'package:fluffychat/widgets/layouts/app_shell.dart';
import 'package:fluffychat/widgets/layouts/app_tab.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/log_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

final _matrixUriId = RegExp(r'^[^/?#%\\\s\x00-\x1f\x7f]{1,255}$');

abstract class AppRoutes {
  static bool _matrixIsLoggedIn(BuildContext context) =>
      Matrix.of(context).widget.clients.any((client) => client.isLogged());

  @visibleForTesting
  static const defaultIsLoggedIn = _matrixIsLoggedIn;

  @visibleForTesting
  static bool Function(BuildContext context) isLoggedIn = defaultIsLoggedIn;

  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) => isLoggedIn(context) ? '/rooms' : null;

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) => isLoggedIn(context) ? null : '/home';

  static bool _callsAvailable(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.activeClientOrNull;
    return client != null && matrix.callsAvailableFor(client);
  }

  static const _legacySettingsPath = '/rooms/settings';

  static FutureOr<String?> globalRedirect(
    BuildContext context,
    GoRouterState state,
  ) {
    final target = state.uri;
    if (target.scheme.isEmpty &&
        (target.hasAuthority || target.path.contains('//'))) {
      Logs().w('Ignored a route with an authority or empty segment');
      return '/rooms';
    }

    // Workaround for content sharings passed to go router:
    if ({
      'content',
      'sharemedia-im.fluffychat.app',
    }.contains(state.uri.scheme)) {
      Logs().d('Ignore content sharing handling in go router');
      return '/';
    }

    if (state.uri.scheme == 'matrix' && state.uri.pathSegments.length >= 2) {
      final type = state.uri.pathSegments.first;
      final id = state.uri.pathSegments[1];
      final isRoomOrUser = type == 'r' || type == 'u';
      if ({'roomid', 'r', 'u'}.contains(type) &&
          (!_matrixUriId.hasMatch(id) || (isRoomOrUser && !id.contains(':')))) {
        Logs().w('Ignored malformed matrix: link');
        return '/rooms';
      }
      switch (type) {
        case 'roomid':
          return '/${Uri(pathSegments: ['rooms', '!$id'])}';
        case 'r':
          return Uri(
            path: '/rooms/newprivatechat',
            fragment: '#$id',
          ).toString();
        case 'u':
          return Uri(
            path: '/rooms/newprivatechat',
            fragment: '@$id',
          ).toString();
      }
    }

    // Pass deep links to app:
    if (state.uri.toString().startsWith(AppConfig.deepLinkPrefix)) {
      return '/rooms/newprivatechat#${state.uri}';
    }

    final path = state.uri.path;
    if (path == _legacySettingsPath ||
        path.startsWith('$_legacySettingsPath/')) {
      return state.uri
          .replace(
            path: '/settings${path.substring(_legacySettingsPath.length)}',
          )
          .toString();
    }

    if (AppTab.forPath(path) != null && !isLoggedIn(context)) return '/home';
    return null;
  }

  AppRoutes();

  static final List<RouteBase> routes = [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          Matrix.of(context).widget.clients.any((client) => client.isLogged())
          ? '/rooms'
          : '/home',
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const IntroPagePresenter()),
      redirect: loggedInRedirect,
      routes: [
        GoRoute(
          path: 'sign_in',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInPage(signUp: false)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'sign_up',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInPage(signUp: true)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'login',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            Login(client: state.extra as Client),
          ),
          redirect: loggedInRedirect,
        ),
      ],
    ),
    GoRoute(
      path: '/logs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const LogViewer()),
    ),
    GoRoute(
      path: '/configs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const ConfigViewer()),
    ),
    GoRoute(
      path: '/backup',
      redirect: loggedOutRedirect,
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        BootstrapPage(reset: state.uri.queryParameters['reset'] == 'true'),
      ),
    ),
    StatefulShellRoute.indexedStack(
      // Never use a transition on the shell route. Changing the PageBuilder
      // here based on a MediaQuery causes the child to briefly be rendered
      // twice with the same GlobalKey, blowing up the rendering.
      pageBuilder: (context, state, navigationShell) => noTransitionPageBuilder(
        context,
        state,
        ValueListenableBuilder(
          valueListenable: Matrix.of(context).loggedInAccountCount,
          builder: (context, accountCount, _) {
            final matrix = Matrix.of(context);
            if (matrix.activeClientOrNull == null) {
              return const SizedBox.shrink();
            }
            return DatabaseQuarantineBanner(
              child: DatabaseUnencryptedBanner(
                child: AppShell(
                  navigationShell: navigationShell,
                  location: state.uri.path,
                  accountCount: accountCount,
                  onFirstShown: matrix.runStartupHooksOnce,
                  leftColumn: (context, tab) => switch (tab) {
                    AppTab.chats => ChatList(
                      activeChat: state.pathParameters['roomid'],
                      activeSpace: state.uri.queryParameters['spaceId'],
                    ),
                    AppTab.calls => const CallsPage(),
                    AppTab.settings => const Settings(),
                    AppTab.profile => const ProfilePage(),
                  },
                ),
              ),
            );
          },
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/rooms',
              redirect: loggedOutRedirect,
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? const EmptyPage()
                    : ChatList(
                        activeChat: state.pathParameters['roomid'],
                        activeSpace: state.uri.queryParameters['spaceId'],
                      ),
              ),
              routes: [
                GoRoute(
                  path: 'archive',
                  pageBuilder: (context, state) =>
                      defaultPageBuilder(context, state, const Archive()),
                  routes: [
                    GoRoute(
                      path: ':roomid',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatPage(
                          key: ValueKey(state.uri),
                          roomId: state.pathParameters['roomid']!,
                          eventId: state.uri.queryParameters['event'],
                          timeline: state.extra as Timeline?,
                          action: state.uri.queryParameters['action'],
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'newprivatechat',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    NewPrivateChat(
                      key: ValueKey('new_chat_${state.uri.fragment}'),
                      deeplink: state.uri.fragment,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'newgroup',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    NewGroup(spaceId: state.uri.queryParameters['space_id']),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'newspace',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    NewGroup(
                      createGroupType: CreateGroupType.space,
                      spaceId: state.uri.queryParameters['space_id'],
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'space/:spaceId',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    SpaceOverview(
                      key: ValueKey(state.uri),
                      spaceId: state.pathParameters['spaceId']!,
                      trail: SpaceTrail.parse(
                        state.uri.queryParameters['trail'],
                      ),
                      preview: state.extra is HierarchyChild
                          ? state.extra as HierarchyChild
                          : null,
                    ),
                  ),
                  redirect: (context, state) {
                    final redirect = loggedOutRedirect(context, state);
                    if (redirect != null) return redirect;
                    final id = state.pathParameters['spaceId'];
                    return id != null && SpaceTrail.isSpaceId(id)
                        ? null
                        : '/rooms';
                  },
                ),
                GoRoute(
                  path: 'search',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    GlobalSearch(
                      initialSection:
                          state.uri.queryParameters['section'] == 'public'
                          ? SearchSection.publicRooms
                          : SearchSection.all,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: ':roomid',
                  pageBuilder: (context, state) {
                    final body = state.uri.queryParameters['body'];
                    var shareItems = state.extra is List<ShareItem>
                        ? state.extra as List<ShareItem>
                        : null;
                    if (body != null && body.isNotEmpty) {
                      shareItems ??= [];
                      shareItems.add(PrefillShareItem(body));
                    }
                    return defaultPageBuilder(
                      context,
                      state,
                      ChatPage(
                        key: ValueKey(state.uri),
                        roomId: state.pathParameters['roomid']!,
                        shareItems: shareItems,
                        eventId: state.uri.queryParameters['event'],
                        action: state.uri.queryParameters['action'],
                        threadId: state.uri.queryParameters['thread'],
                      ),
                    );
                  },
                  redirect: loggedOutRedirect,
                  routes: [
                    GoRoute(
                      path: 'search',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatSearchPage(roomId: state.pathParameters['roomid']!),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'topics',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        TopicsPage(roomId: state.pathParameters['roomid']!),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'appearance',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        SettingsAppearance(
                          key: ValueKey(state.pathParameters['roomid']),
                          roomId: state.pathParameters['roomid'],
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'scheduled',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ScheduledMessagesPage(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'encryption',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const ChatEncryptionSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'invite',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        InvitationSelection(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'details',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatDetails(roomId: state.pathParameters['roomid']!),
                      ),
                      routes: [
                        GoRoute(
                          path: 'access',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            ChatAccessSettings(
                              roomId: state.pathParameters['roomid']!,
                            ),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'members',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            ChatMembersPage(
                              roomId: state.pathParameters['roomid']!,
                            ),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'permissions',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const ChatPermissionsSettings(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'invite',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            InvitationSelection(
                              roomId: state.pathParameters['roomid']!,
                            ),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'emotes',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            EmotesSettings(
                              roomId: state.pathParameters['roomid'],
                            ),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                      redirect: loggedOutRedirect,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/calls',
              redirect: (context, state) =>
                  loggedOutRedirect(context, state) ??
                  (_callsAvailable(context) ? null : '/rooms'),
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? const EmptyPage()
                    : const CallsPage(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? const EmptyPage()
                    : const Settings(),
              ),
              routes: [
                GoRoute(
                  path: 'data',
                  pageBuilder: (context, state) =>
                      defaultPageBuilder(context, state, const SettingsData()),
                  redirect: loggedOutRedirect,
                  routes: [
                    GoRoute(
                      path: 'export',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ExportPage(
                          key: ValueKey(state.uri.queryParameters['room']),
                          roomId: state.uri.queryParameters['room'] ?? '',
                        ),
                      ),
                      redirect: (context, state) {
                        final guarded = loggedOutRedirect(context, state);
                        if (guarded != null) return guarded;
                        final room = state.uri.queryParameters['room'];
                        return room != null && isMatrixRoomId(room)
                            ? null
                            : '/settings/data';
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: 'notifications',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const SettingsNotifications(),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'appearance',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const SettingsAppearance(),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'style',
                  redirect: (context, state) =>
                      loggedOutRedirect(context, state) ??
                      '/settings/appearance',
                ),
                GoRoute(
                  path: 'devices',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const DevicesSettings(),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'emotes',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const EmotesSettings(roomId: null),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'chat',
                  pageBuilder: (context, state) =>
                      defaultPageBuilder(context, state, const SettingsChat()),
                  routes: [
                    GoRoute(
                      path: 'emotes',
                      redirect: (context, state) => '/settings/emotes',
                    ),
                    GoRoute(
                      path: 'folders',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsFolders(),
                      ),
                      redirect: loggedOutRedirect,
                      routes: [
                        GoRoute(
                          path: 'edit',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            FolderEditor(
                              key: ValueKey(
                                state.uri.queryParameters['id'] ?? 'new',
                              ),
                              folderId: state.uri.queryParameters['id'],
                            ),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'addaccount',
                  redirect: loggedOutRedirect,
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const IntroPagePresenter(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'sign_in',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        SignInPage(signUp: false),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'sign_up',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        SignInPage(signUp: true),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'login',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        Login(client: state.extra as Client),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                ),
                GoRoute(
                  path: 'homeserver',
                  pageBuilder: (context, state) {
                    return defaultPageBuilder(
                      context,
                      state,
                      const SettingsHomeserver(),
                    );
                  },
                  redirect: loggedOutRedirect,
                  routes: [
                    GoRoute(
                      path: 'details',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const HomeserverDetails(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                ),
                GoRoute(
                  path: 'security',
                  redirect: loggedOutRedirect,
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const SettingsSecurity(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'password',
                      pageBuilder: (context, state) {
                        return defaultPageBuilder(
                          context,
                          state,
                          const SettingsPassword(),
                        );
                      },
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'ignorelist',
                      pageBuilder: (context, state) {
                        return defaultPageBuilder(
                          context,
                          state,
                          SettingsIgnoreList(
                            initialUserId: state.extra?.toString(),
                          ),
                        );
                      },
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: '3pid',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const Settings3Pid(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                ),
              ],
              redirect: loggedOutRedirect,
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              redirect: loggedOutRedirect,
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? const EmptyPage()
                    : const ProfilePage(),
              ),
            ),
          ],
        ),
      ],
    ),
  ];

  static Page noTransitionPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => NoTransitionPage(
    key: state.pageKey,
    restorationId: state.pageKey.value,
    child: child,
  );

  static Page defaultPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) {
    final clientName = state.uri.queryParameters['client'];
    if (clientName != null) {
      final matrix = Matrix.of(context);
      final client = matrix.getClientByName(clientName);
      if (client != null) matrix.setActiveClient(client, resetTabs: false);
    }
    return FluffyThemes.isColumnMode(context)
        ? noTransitionPageBuilder(context, state, child)
        : MaterialPage(
            key: state.pageKey,
            restorationId: state.pageKey.value,
            child: child,
          );
  }
}
