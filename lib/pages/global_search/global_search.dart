// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/global_search/global_search_view.dart';
import 'package:odango/pages/global_search/search_filter_sheet.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/matrix_room_id.dart';
import 'package:odango/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:odango/utils/retention/retention_policy.dart';
import 'package:odango/utils/route_path.dart';
import 'package:odango/utils/search/chat_matcher.dart';
import 'package:odango/utils/search/index_feeder.dart';
import 'package:odango/utils/search/local_search.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/utils/search/public_directory.dart';
import 'package:odango/utils/search/search_filter.dart';
import 'package:odango/utils/search/search_query.dart';
import 'package:odango/utils/search/search_sections.dart';
import 'package:odango/utils/search/server_search.dart';
import 'package:odango/utils/search/unencrypted_scan.dart';
import 'package:odango/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:odango/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:odango/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:odango/widgets/matrix.dart';

enum SourceStatus { idle, loading, done, error }

class GlobalSearch extends StatefulWidget {
  final SearchSection initialSection;

  const GlobalSearch({this.initialSection = SearchSection.all, super.key});

  @override
  GlobalSearchController createState() => GlobalSearchController();
}

class GlobalSearchController extends State<GlobalSearch> {
  static const debounce = Duration(milliseconds: 300);
  static const serverStoreKey = 'com.swovo.odango.search.server';
  static const maxPublicPages = 5;
  static const maxPublicRooms = 100;
  static const publicPageSize = 20;

  final searchController = TextEditingController();
  final focusNode = FocusNode();

  @visibleForTesting
  UnencryptedScan Function(Client) scanFor = UnencryptedScan.new;

  @visibleForTesting
  static Future<int> Function(Client, CancelFlag) catchUpFor =
      (client, cancel) => IndexFeeder.of(client).catchUp(cancel: cancel);

  SearchSection section = SearchSection.all;
  MessageSearchFilter filter = MessageSearchFilter.none;
  SearchQuery query = SearchQuery.empty;

  List<ChatMatch> chats = const [];
  List<SearchHit> localHits = const [];
  List<SearchHit> serverHits = const [];
  List<SearchHit> scanHits = const [];
  List<Profile> people = const [];
  List<PublishedRoomsChunk> publicRooms = const [];
  String? serverNextBatch;
  int serverPage = 0;
  String? publicNextBatch;
  int publicPage = 0;
  String? searchServer;

  SourceStatus serverStatus = SourceStatus.idle;
  SourceStatus peopleStatus = SourceStatus.idle;
  SourceStatus publicStatus = SourceStatus.idle;

  var _generation = 0;
  Timer? _timer;
  final _cancelCatchUp = CancelFlag();

  Client get _client => Matrix.of(context).client;

  bool get hasSearch => !query.isEmpty || !filter.isEmpty;

  bool get showsMessages => switch (section) {
    SearchSection.chats || SearchSection.publicRooms => false,
    _ => true,
  };

  bool get showsChats =>
      section == SearchSection.all || section == SearchSection.chats;

  bool get showsPeople =>
      showsChats && searchController.text.trim().length >= 2;

  bool get showsPublicRooms =>
      section == SearchSection.all || section == SearchSection.publicRooms;

  bool get browsesPublic => section == SearchSection.publicRooms && !hasSearch;

  bool get wantsPublicRooms =>
      showsPublicRooms &&
      (searchController.text.trim().isNotEmpty ||
          section == SearchSection.publicRooms);

  bool get publicPending =>
      wantsPublicRooms && publicStatus == SourceStatus.idle;

  bool get canLoadMorePublic =>
      publicNextBatch != null &&
      publicPage < maxPublicPages &&
      publicRooms.length < maxPublicRooms &&
      publicStatus != SourceStatus.loading;

  List<PublishedRoomsChunk> get publicSpaces =>
      publicRooms.where((room) => room.roomType == 'm.space').toList();

  List<PublishedRoomsChunk> get publicChats =>
      publicRooms.where((room) => room.roomType != 'm.space').toList();

  List<SearchHit> get messages =>
      SearchSections.mergeMessages(localHits, [...serverHits, ...scanHits]);

  bool get canLoadMoreServer =>
      serverNextBatch != null &&
      serverPage < ServerSearch.maxPages &&
      serverHits.length < ServerSearch.maxResults &&
      serverStatus != SourceStatus.loading;

  MessageIndex get index => MessageIndex.of(_client);

  @override
  void initState() {
    super.initState();
    section = widget.initialSection;
    final client = Matrix.of(context).client;
    searchServer = Matrix.of(context).store.getString(serverStoreKey);
    unawaited(_catchUp(client));
    _accountSub = Matrix.of(context).onActiveClientChanged.listen((_) {
      if (mounted) context.go('/rooms');
    });
  }

  StreamSubscription<Client>? _accountSub;

  var _chatsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chatsLoaded) return;
    _chatsLoaded = true;
    _refreshChats();
    if (!wantsPublicRooms) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run(_generation));
    });
  }

  Future<void> _catchUp(Client client) async {
    await catchUpFor(client, _cancelCatchUp);
    if (!mounted || _cancelCatchUp.cancelled) return;
    final policyOf = _retentionOf(client);
    MessageIndex.of(client).pruneRetention(policyOf, DateTime.now());
    if (hasSearch) setState(_runLocal);
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _cancelCatchUp.cancel();
    unawaited(_accountSub?.cancel());
    searchController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  RetentionPolicy? Function(String) _retentionOf(Client client) => (roomId) {
    final room = client.getRoomById(roomId);
    return room == null ? null : RetentionPolicy.forRoom(room);
  };

  void _refreshChats() {
    final l10n = L10n.of(context);
    final locals = MatrixLocals(l10n);
    chats = ChatMatcher.run(
      _client.rooms,
      query,
      nameOf: (room) => room.getLocalizedDisplayname(locals),
    );
  }

  void onChanged(String text) {
    _generation++;
    _timer?.cancel();
    setState(() {
      query = SearchQuery.parse(text);
      _refreshChats();
      _resetResults();
    });
    final generation = _generation;
    _timer = Timer(debounce, () => unawaited(_run(generation)));
  }

  void clearQuery() {
    searchController.clear();
    onChanged('');
    focusNode.requestFocus();
  }

  void _resetResults() {
    localHits = serverHits = scanHits = const [];
    people = const [];
    publicRooms = const [];
    serverNextBatch = null;
    serverPage = 0;
    publicNextBatch = null;
    publicPage = 0;
    serverStatus = peopleStatus = publicStatus = SourceStatus.idle;
    if (hasSearch) _runLocal();
  }

  void selectSection(SearchSection selected) {
    final next = SearchSections.select(selected, filter, section);
    _applyFacets(next, selected);
  }

  Future<void> openFilters() async {
    focusNode.unfocus();
    final result = await showSearchFilterSheet(
      context,
      initial: filter,
      suggestions: _senderSuggestions(),
    );
    if (result == null || !mounted) return;
    _applyFacets(result, SearchSections.after(result, section));
  }

  void _applyFacets(MessageSearchFilter next, SearchSection nextSection) {
    _generation++;
    _timer?.cancel();
    setState(() {
      filter = next;
      section = nextSection;
      _resetResults();
    });
    if (!hasSearch && !wantsPublicRooms) return;
    final generation = _generation;
    unawaited(_run(generation));
  }

  /// The people the filter sheet offers: the senders in the index, most
  /// frequent first.
  List<String> _senderSuggestions() {
    final counts = <String, int>{};
    for (final entry in index.snapshot()) {
      counts.update(entry.senderId, (n) => n + 1, ifAbsent: () => 1);
    }
    final ids = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return ids.take(8).toList();
  }

  void _runLocal() {
    final client = _client;
    localHits = LocalSearch.run(
      index.snapshot(),
      query,
      filter,
      now: DateTime.now(),
      retentionOf: _retentionOf(client),
      roomVisible: (id) =>
          client.getRoomById(id)?.membership == Membership.join,
    );
  }

  Future<void> _run(int generation) async {
    final client = _client;
    final text = searchController.text.trim();
    final capturedQuery = query;
    final capturedFilter = filter;
    final futures = <Future<void>>[];
    if (showsMessages && !capturedQuery.isEmpty) {
      futures.add(
        _loadServer(generation, client, capturedQuery, capturedFilter),
      );
    }
    if (showsMessages && capturedQuery.isEmpty && !capturedFilter.isEmpty) {
      futures.add(_loadScan(generation, client, capturedFilter));
    }
    if (showsPeople) {
      futures.add(_loadPeople(generation, client, text));
    }
    if (wantsPublicRooms) {
      futures.add(_loadPublicRooms(generation, client, text));
    }
    await Future.wait(futures);
  }

  Future<void> _loadServer(
    int generation,
    Client client,
    SearchQuery capturedQuery,
    MessageSearchFilter capturedFilter,
  ) async {
    setState(() => serverStatus = SourceStatus.loading);
    try {
      final page = await ServerSearch(client).search(
        capturedQuery,
        capturedFilter,
        nextBatch: serverNextBatch,
        page: serverPage,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        serverHits = [...serverHits, ...page.hits];
        serverNextBatch = page.nextBatch;
        serverPage++;
        serverStatus = SourceStatus.done;
      });
    } catch (_) {
      Logs().w('[Search] server search failed');
      if (!mounted || generation != _generation) return;
      setState(() => serverStatus = SourceStatus.error);
    }
  }

  Future<void> loadMoreServer() async {
    if (!canLoadMoreServer) return;
    await _loadServer(_generation, _client, query, filter);
  }

  Future<void> retryServer() async {
    if (serverStatus != SourceStatus.error) return;
    if (query.isEmpty) {
      await _loadScan(_generation, _client, filter);
      return;
    }
    await _loadServer(_generation, _client, query, filter);
  }

  Future<void> _loadScan(
    int generation,
    Client client,
    MessageSearchFilter capturedFilter,
  ) async {
    setState(() => serverStatus = SourceStatus.loading);
    try {
      final hits = await scanFor(client).run(capturedFilter);
      if (!mounted || generation != _generation) return;
      setState(() {
        scanHits = hits;
        serverStatus = SourceStatus.done;
      });
    } catch (_) {
      Logs().w('[Search] scan failed');
      if (!mounted || generation != _generation) return;
      setState(() => serverStatus = SourceStatus.error);
    }
  }

  Future<void> _loadPeople(int generation, Client client, String text) async {
    setState(() => peopleStatus = SourceStatus.loading);
    try {
      final result = await client.searchUserDirectory(text, limit: 20);
      if (!mounted || generation != _generation) return;
      final found = result.results
          .where((profile) => profile.userId.startsWith('@'))
          .toList();
      final typedId = text.isValidMatrixIdStrict() && text.sigil == '@';
      setState(() {
        people = [
          if (typedId && !found.any((profile) => profile.userId == text))
            Profile(userId: text),
          ...found,
        ];
        peopleStatus = SourceStatus.done;
      });
    } catch (_) {
      Logs().w('[Search] people search failed');
      if (!mounted || generation != _generation) return;
      setState(() => peopleStatus = SourceStatus.error);
    }
  }

  Future<void> _loadPublicRooms(
    int generation,
    Client client,
    String text, {
    bool more = false,
  }) async {
    setState(() => publicStatus = SourceStatus.loading);
    final fromServer = section == SearchSection.publicRooms
        ? searchServer
        : null;
    try {
      final result = await queryPublicDirectory(
        client,
        server: fromServer,
        term: text,
        limit: publicPageSize,
        since: more ? publicNextBatch : null,
      );
      final chunks = [...result.chunk];
      final aliasLookup =
          !more &&
          text.isValidMatrixIdStrict() &&
          text.sigil == '#' &&
          !chunks.any((room) => room.canonicalAlias == text);
      if (aliasLookup) {
        try {
          final resolved = await client.getRoomIdByAlias(text);
          final roomId = resolved.roomId;
          if (roomId != null) {
            chunks.add(
              PublishedRoomsChunk(
                name: text,
                guestCanJoin: false,
                numJoinedMembers: 0,
                roomId: roomId,
                worldReadable: false,
                canonicalAlias: text,
              ),
            );
          }
        } catch (_) {
          Logs().w('[Search] alias lookup failed');
        }
      }
      if (!mounted || generation != _generation) return;
      final known = {for (final room in publicRooms) room.roomId};
      final fresh = <PublishedRoomsChunk>[];
      for (final room in chunks) {
        if (!isMatrixRoomId(room.roomId) || !known.add(room.roomId)) continue;
        fresh.add(room);
      }
      setState(() {
        publicRooms = [...publicRooms, ...fresh].take(maxPublicRooms).toList();
        publicNextBatch = result.nextBatch;
        publicPage++;
        publicStatus = SourceStatus.done;
      });
    } catch (_) {
      Logs().w('[Search] public rooms failed');
      if (!mounted || generation != _generation) return;
      setState(() => publicStatus = SourceStatus.error);
    }
  }

  Future<void> loadMorePublic() async {
    if (!canLoadMorePublic) return;
    await _loadPublicRooms(
      _generation,
      _client,
      searchController.text.trim(),
      more: true,
    );
  }

  Future<void> retryPublic() async {
    if (publicStatus != SourceStatus.error) return;
    final more = publicNextBatch != null;
    await _loadPublicRooms(
      _generation,
      _client,
      searchController.text.trim(),
      more: more,
    );
  }

  Future<void> changeServer() async {
    final matrix = Matrix.of(context);
    final l10n = L10n.of(context);
    final server = await showTextInputDialog(
      useRootNavigator: false,
      title: l10n.changeTheHomeserver,
      context: context,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      prefixText: 'https://',
      hintText: matrix.client.homeserver?.host,
      initialText: searchServer,
      keyboardType: TextInputType.url,
      autocorrect: false,
      validator: (value) => value.contains('.') ? null : l10n.invalidServerName,
    );
    if (server == null || !mounted) return;
    await matrix.store.setString(serverStoreKey, server);
    if (!mounted) return;
    _generation++;
    setState(() {
      searchServer = server;
      publicRooms = const [];
      publicNextBatch = null;
      publicPage = 0;
      publicStatus = SourceStatus.idle;
    });
    if (!wantsPublicRooms) return;
    unawaited(
      _loadPublicRooms(_generation, _client, searchController.text.trim()),
    );
  }

  void openMessage(SearchHit hit) {
    final roomId = hit.message.roomId;
    final eventId = hit.message.eventId;
    if (!isMatrixRoomId(roomId) || !isMatrixEventId(eventId)) return;
    context.go(routePath(['rooms', roomId], query: {'event': eventId}));
  }

  void openChat(Room room) {
    if (!isMatrixRoomId(room.id)) return;
    context.go(routePath(['rooms', room.id]));
  }

  void openPerson(Profile profile) =>
      UserDialog.show(context: context, profile: profile);

  void openPublicRoom(PublishedRoomsChunk chunk) {
    unawaited(
      showAdaptiveDialog(
        context: context,
        builder: (_) => PublicRoomDialog(
          roomAlias: chunk.canonicalAlias ?? chunk.roomId,
          chunk: chunk,
        ),
      ),
    );
  }

  Room? roomOf(String roomId) => _client.getRoomById(roomId);

  String get serverLabel => searchServer ?? _client.homeserver?.host ?? '';

  String? directoryNotice(L10n l10n) => searchController.text.trim().isNotEmpty
      ? l10n.searchNoticeDirectory(serverLabel)
      : null;

  /// What the user should know about where the messages come from.
  List<String> notices(L10n l10n) => [
    if (showsMessages && hasSearch)
      index.persistent
          ? l10n.searchNoticePersistent(index.length)
          : l10n.searchNoticeMemoryOnly,
    if (showsMessages &&
        !query.isEmpty &&
        ServerSearch(_client).eligibleRooms().isNotEmpty)
      l10n.searchNoticeServer,
    if (showsMessages && query.isEmpty && !filter.isEmpty)
      l10n.searchNoticeFilterOnly,
  ];

  String senderName(SearchHit hit) {
    final room = _client.getRoomById(hit.message.roomId);
    final name = room
        ?.unsafeGetUserFromMemoryOrFallback(hit.message.senderId)
        .calcDisplayname();
    return safeDisplayText(name ?? hit.message.senderId);
  }

  String chatName(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return '';
    return safeDisplayText(
      room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
    );
  }

  @override
  Widget build(BuildContext context) => GlobalSearchView(this);
}
