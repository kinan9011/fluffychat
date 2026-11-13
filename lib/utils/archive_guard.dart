// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

class ArchiveLimits {
  final int maxArchiveBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;

  /// Max uncompressed/compressed ratio. Already compressed media is ~1:1, so
  /// a high ratio means a zip bomb.
  final int maxRatio;

  const ArchiveLimits({
    required this.maxArchiveBytes,
    required this.maxEntries,
    required this.maxEntryBytes,
    required this.maxTotalBytes,
    required this.maxRatio,
  });

  /// Matches the 10 MB upload limit of the app database file store.
  static const emotes = ArchiveLimits(
    maxArchiveBytes: 64 * 1024 * 1024,
    maxEntries: 500,
    maxEntryBytes: 10 * 1024 * 1024,
    maxTotalBytes: 128 * 1024 * 1024,
    maxRatio: 100,
  );
}

enum ArchiveGuardError { tooLarge, tooManyEntries, unsafePaths, invalid }

class ArchiveGuardException implements Exception {
  final ArchiveGuardError error;

  const ArchiveGuardException(this.error);

  @override
  String toString() => 'ArchiveGuardException(${error.name})';
}

class ArchiveEntryBytes {
  final String name;
  final Uint8List bytes;

  const ArchiveEntryBytes(this.name, this.bytes);
}

const _maxEntryNameLength = 1024;

/// Floor so tiny but legitimate archives are not rejected by the ratio check.
const _minTotalBytes = 1024 * 1024;

final _reservedWindowsNames = RegExp(
  r'^(con|prn|aux|nul|conin\$|conout\$|(com|lpt)[0-9¹²³])$',
  caseSensitive: false,
);

/// Safe to join onto a directory on Linux, macOS and Windows.
bool isSafeArchiveEntryName(String name) {
  if (name.isEmpty || name.length > _maxEntryNameLength) return false;
  if (name.contains('\u0000') || name.contains(':')) return false;
  if (name.startsWith('/') || name.startsWith('\\')) return false;
  return name.split(RegExp(r'[/\\]')).every(_isSafeSegment);
}

bool _isSafeSegment(String segment) {
  if (segment.isEmpty || segment == '.') return true;
  // Windows drops trailing dots and spaces, so `.. ` would become `..`.
  if (segment.endsWith('.') || segment.endsWith(' ')) return false;
  return !_reservedWindowsNames.hasMatch(segment.split('.').first.trimRight());
}

Future<List<ArchiveEntryBytes>> readArchiveFile(XFile file) async {
  if (await file.length() > ArchiveLimits.emotes.maxArchiveBytes) {
    throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
  }
  return compute(extractArchiveSafely, await file.readAsBytes());
}

List<ArchiveEntryBytes> extractArchiveSafely(
  Uint8List bytes, [
  ArchiveLimits limits = ArchiveLimits.emotes,
]) {
  if (bytes.length > limits.maxArchiveBytes) {
    throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
  }

  _checkCentralDirectory(bytes, limits);

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, throwOnError: true);
  } catch (_) {
    throw const ArchiveGuardException(ArchiveGuardError.invalid);
  }

  if (archive.length > limits.maxEntries) {
    throw const ArchiveGuardException(ArchiveGuardError.tooManyEntries);
  }
  if (archive.any((e) => !isSafeArchiveEntryName(e.name) || e.isSymbolicLink)) {
    throw const ArchiveGuardException(ArchiveGuardError.unsafePaths);
  }

  final files = archive.where((e) => e.isFile).toList();
  final maxTotal = min(
    limits.maxTotalBytes,
    max(bytes.length * limits.maxRatio, _minTotalBytes),
  );
  var declaredTotal = 0;
  for (final file in files) {
    if (file.size > limits.maxEntryBytes) {
      throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
    }
    declaredTotal += file.size;
    if (declaredTotal > maxTotal) {
      throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
    }
  }

  var actualTotal = 0;
  final entries = <ArchiveEntryBytes>[];
  for (final file in files) {
    try {
      final entryBytes = file.readBytes() ?? Uint8List(0);
      actualTotal += entryBytes.length;
      if (entryBytes.length > limits.maxEntryBytes || actualTotal > maxTotal) {
        throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
      }
      entries.add(ArchiveEntryBytes(file.name, entryBytes));
    } on ArchiveGuardException {
      rethrow;
    } on ArchiveLimitException {
      throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
    } catch (_) {
      throw const ArchiveGuardException(ArchiveGuardError.invalid);
    }
  }
  return entries;
}

const _eocdSignature = 0x06054b50;
const _directorySignature = 0x02014b50;
const _eocdMinLength = 22;
const _directoryRecordMinLength = 46;
const _maxEocdCommentLength = 0xFFFF;
const _maxCentralDirectoryBytesPerEntry = 2048;
const _unixCreator = 3;
const _unixSymlinkType = 0xa000;
const _unixFileTypeMask = 0xf000;

/// The zip decoder reads central directory records until the directory ends,
/// not by the declared count, and it inflates symlink entries while decoding.
/// Both happen before any other limit could be checked, so the directory is
/// validated here first.
void _checkCentralDirectory(Uint8List bytes, ArchiveLimits limits) {
  final data = ByteData.sublistView(bytes);
  final lowest = max(0, bytes.length - _eocdMinLength - _maxEocdCommentLength);
  for (var eocd = bytes.length - _eocdMinLength; eocd >= lowest; eocd--) {
    if (data.getUint32(eocd, Endian.little) != _eocdSignature) continue;
    final entries = data.getUint16(eocd + 10, Endian.little);
    final directoryBytes = data.getUint32(eocd + 12, Endian.little);
    final directoryOffset = data.getUint32(eocd + 16, Endian.little);
    if (entries > limits.maxEntries ||
        directoryBytes >
            limits.maxEntries * _maxCentralDirectoryBytesPerEntry) {
      throw const ArchiveGuardException(ArchiveGuardError.tooManyEntries);
    }
    final start = [directoryOffset, eocd - directoryBytes].firstWhere(
      (offset) =>
          offset >= 0 &&
          offset + 4 <= bytes.length &&
          data.getUint32(offset, Endian.little) == _directorySignature,
      orElse: () => -1,
    );
    if (start < 0) {
      if (entries == 0) return;
      throw const ArchiveGuardException(ArchiveGuardError.invalid);
    }
    _checkDirectoryRecords(data, start, entries, limits);
    return;
  }
  throw const ArchiveGuardException(ArchiveGuardError.invalid);
}

void _checkDirectoryRecords(
  ByteData data,
  int start,
  int entries,
  ArchiveLimits limits,
) {
  var offset = start;
  for (var i = 0; i < entries; i++) {
    if (offset + _directoryRecordMinLength > data.lengthInBytes ||
        data.getUint32(offset, Endian.little) != _directorySignature) {
      throw const ArchiveGuardException(ArchiveGuardError.invalid);
    }
    final versionMadeBy = data.getUint16(offset + 4, Endian.little);
    final uncompressedSize = data.getUint32(offset + 24, Endian.little);
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    final attributes = data.getUint32(offset + 38, Endian.little);

    final isUnixSymlink =
        versionMadeBy >> 8 == _unixCreator &&
        (attributes >> 16) & _unixFileTypeMask == _unixSymlinkType;
    if (isUnixSymlink) {
      throw const ArchiveGuardException(ArchiveGuardError.unsafePaths);
    }
    if (uncompressedSize > limits.maxEntryBytes) {
      throw const ArchiveGuardException(ArchiveGuardError.tooLarge);
    }
    offset +=
        _directoryRecordMinLength + nameLength + extraLength + commentLength;
  }
}
