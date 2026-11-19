<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

<img src="assets/logo/mini/logo_mini.png" alt="The Odango logo: three smiling dango on a cherry blossom" width="160">

# Odango

[Odango](https://odango.swovo.de) is an open source [[matrix](https://matrix.org)] client written in [Flutter](https://flutter.dev) for Android, iOS, web, Linux, macOS and Windows. It has a familiar, Telegram-style interface (chat folders, swipe actions, a floating bottom bar) on top of the open Matrix protocol, so it works with any Matrix server and with every other Matrix client.

## A fork of FluffyChat

Odango is a fork of [FluffyChat](https://github.com/krille-chan/fluffychat) by Christian Kußowski and the FluffyChat contributors. It would not exist without their work, and it keeps what makes that work free:

- **Licence:** [AGPL-3.0-or-later](LICENSE), like the FluffyChat project. The upstream copyright and SPDX headers are untouched, and new files add an Odango line.
- **Attribution:** see [NOTICE.md](NOTICE.md). Odango is not affiliated with, endorsed by or supported by the FluffyChat project.
- **Upstream:** Odango is no longer a GitHub fork but still follows FluffyChat: new upstream commits are reported by a daily check and brought in by review. See [docs/UPSTREAM.md](docs/UPSTREAM.md).
- **Support:** the in-app *Support Odango* entry explains that part of the support goes on to the FluffyChat source Odango is built on.

Odango is a **new app** with its own app id, `com.swovo.odango`. It does not read the data of a FluffyChat installation and there is no migration: sign in again and your chats come back from your homeserver.

## Links

- 🌐 Website: <https://odango.swovo.de>
- 💻 Source and issues: <https://github.com/swovo/odango>
- 🙏 Upstream: <https://github.com/krille-chan/fluffychat>

## Features

Everything FluffyChat does (end to end encryption with encrypted backups, emoji verification and cross signing, spaces, custom emotes and stickers, voice messages, location sharing, moderation tools) plus the Odango redesign:

- 🗂️ Chat folders, spaces as tabs or as a switcher, archive and pinned chats
- 👆 Swipe actions and a peek into a chat without marking it read
- ✍️ A rich text composer, edit history, scheduled sending and silent messages
- 🔍 Global search, including an encrypted on-device index for encrypted rooms
- 🧵 Topics, polls, mentions and disappearing messages
- 🔒 Privacy settings for read receipts, typing and online status
- 🎨 Appearance per chat, accent colour, text size and wallpapers
- 📤 Chat export and a screen that shows what your homeserver supports
- 📞 Calls via Matrix RTC. The Calls tab is hidden when your server does not support them.

## Installation

Release builds will be published at <https://github.com/swovo/odango/releases>. Until then, build it yourself (see below).

## How to build

1. You need [Flutter](https://flutter.dev) (the version is pinned in `.fvmrc`) and [Rust](https://www.rust-lang.org/tools/install).
2. Clone the repo:
```sh
git clone https://github.com/swovo/odango.git
cd odango
```
3. Run it on your platform with `flutter run`.

### Web

Execute once before you run or build:

```sh
./scripts/prepare-web.sh # To install Vodozemac
flutter build web
```

## Configuration and Mobile Device Management (MDM)

Odango can be configured via MDM on Android and iOS and via a `config.json` file on web. The MDM keys for Android are in `android/app/src/main/res/xml/app_restrictions.xml`. An example for `config.json` is `config.sample.json`. All values are optional, so only set the ones you need. For example, to change only the default homeserver, set only `defaultHomeserver`.

A `config.json` is not authenticated, so the web app applies only branding and harmless keys from it:

- Keys that could redirect data (`pushNotificationsGatewayUrl`, `pushNotificationsPusherFormat`, `fallbackLiveKitInstance`), runtime state keys and unknown keys are ignored (a warning with the key name is logged).
- Privacy settings (`sendTypingNotifications`, `sendPublicReadReceipts`, `autoSendErrorReports`, `shareKeysWith`) can only be made more private.
- `website`, `logoUrl`, `privacyPolicy` and `tos` must be `https` URLs.
- `repositoryUrl` must be a plain `https://github.com/<owner>/<repo>` address. Source, issue and release links follow it. The built-in address is only assumed to be yours, so the app makes **no automatic request** to it (recommended homeserver list, issue search, update check) until you set `repositoryConfirmed` to `true` after checking that you own that repository.
- `koFiUrl` and `buyMeACoffeeUrl` are the donation links of the *Support Odango* dialog. They must be `https` URLs; an empty value hides that button.

On Android and iOS the MDM configuration is not restricted except for runtime state keys.

### Push notifications

A push gateway knows the apps it serves, and the gateway of another app will not work for `com.swovo.odango`. This build therefore ships **without** a push gateway: push through Firebase or APNs needs your own Matrix push gateway (for example [Sygnal](https://github.com/matrix-org/sygnal)) and your own Firebase or Apple push setup, configured with the MDM key `pushNotificationsGatewayUrl`. UnifiedPush uses the public UnifiedPush Matrix gateway and needs no setup of your own.

### Crash reports and update checks

Odango never sends crash reports on its own (`autoSendErrorReports` is off), and the report dialog only opens a prefilled issue on your configured repository after you tap *Report*. Once `repositoryConfirmed` is `true`, the report dialog also searches that repository for an existing issue, the sign-in page loads its recommended homeserver list, and on Windows Odango checks its releases once a day for a new installer (turn that off with `checkForUpdates`). While it is `false` none of this happens: the sign-in page offers only the default homeserver and what you type.

### Sign-in with a Matrix account server (OIDC)

Native OIDC sign-in registers the client with `client_uri` set to the `website` setting (`https://odango.swovo.de` by default) and the redirect `de.swovo.odango:/login`. The redirect scheme is the reverse DNS name of the `client_uri` host, as the client registration rules of Matrix Authentication Service require. If you change `website`, change `AppConfig.appSsoUrlScheme` and the scheme in the Android manifest to the reverse of the new host.

## How to run integration tests

You need to have docker installed locally! Run the preparation script before every test run:

```sh
./scripts/prepare_integration_test.sh
```

Then run all tests with:

```sh
flutter test integration_test/mobile_test.dart
```

## Special thanks

- Christian Kußowski, the FluffyChat contributors and all the people behind [FluffyChat](https://github.com/krille-chan/fluffychat). Odango is built on their work.
- The Matrix Foundation for making and maintaining the [emoji translations](https://github.com/matrix-org/matrix-spec/blob/main/data-definitions/sas-emoji.json) used for emoji verification, licensed Apache 2.0.
- Everyone who translated the upstream app: those translations are still theirs.
