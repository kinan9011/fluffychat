<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
SPDX-FileCopyrightText: 2026-Present Odango contributors

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Notice

Odango is a fork of [FluffyChat](https://github.com/krille-chan/fluffychat), copyright 2019-Present Christian Kußowski and the FluffyChat contributors.

## Licence

Odango is free software under the **GNU Affero General Public License, version 3 or later** (`AGPL-3.0-or-later`), the same licence as the FluffyChat project. The full text is in [LICENSE](LICENSE) and `LICENSES/`. The upstream copyright and SPDX headers of every file stay as they are. Files and changes added by Odango carry an additional `2026-Present Odango contributors` line, and `REUSE.toml` records the fork for files that cannot hold a header.

If you run a modified version of Odango as a network service you must offer its users the corresponding source, as the AGPL requires.

## What is different

- The app is named Odango, has the app id `com.swovo.odango`, and uses its own storage, URL schemes, notification and push identifiers. It does not share data with a FluffyChat installation and is not a drop-in update of it.
- The visual design, navigation and several features are new (see the README).
- The FluffyChat logo, mascot and banner are **not** part of Odango: they were removed because their licences (CC-BY-4.0, all rights reserved) do not fit a fork. The Odango logo and icons are original artwork of the Odango contributors.
- No upstream infrastructure is used: Odango does not send crash reports to, check releases of, or request push gateways or homeserver lists from the FluffyChat project or its hosts. Help buttons open pages of the Odango website; the only link to the FluffyChat project is its source repository, shown as credit.

## Not affiliated

Odango is an independent project. It is not affiliated with, endorsed by or supported by the FluffyChat project, its maintainers or Matrix.org. FluffyChat is a name of its respective owners.

## Third party

Third party components keep their own licences (see `LICENSES/`, `REUSE.toml` and `licenses.yaml`).
