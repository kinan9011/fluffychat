// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// An absolute route with every segment escaped, so an id with `!` or `:`
/// (or anything a hostile server put into it) cannot change the path.
String routePath(List<String> segments, {Map<String, String>? query}) =>
    '/${Uri(pathSegments: segments, queryParameters: query)}';
