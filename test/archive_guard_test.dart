// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluffychat/utils/archive_guard.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List zipOf(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void expectRejected(Uint8List bytes, ArchiveGuardError error, [limits]) {
  expect(
    () => extractArchiveSafely(bytes, limits ?? ArchiveLimits.emotes),
    throwsA(
      isA<ArchiveGuardException>().having((e) => e.error, 'error', error),
    ),
  );
}

void main() {
  group('isSafeArchiveEntryName', () {
    const safe = [
      'a.png',
      'dir/a.png',
      'dir/sub/a b.png',
      'dir/',
      '..a.png',
      'console.png',
      'communication/a.png',
      'com10.png',
      'a.b.png',
      '.hidden.png',
      './a.png',
    ];
    const unsafe = [
      '',
      '../evil.png',
      'a/../../evil.png',
      '..\\evil.png',
      '/abs/evil.png',
      '\\\\server\\share\\x.png',
      'C:\\Windows\\x.png',
      'c:/x.png',
      'a:b.png',
      'ab:c.png',
      'file.png:stream',
      'dir/file.png::\$DATA',
      'a.png.',
      'a.png ',
      'dir./a.png',
      'dir /a.png',
      '.. /x.png',
      '.. ',
      '..',
      'CON',
      'con.png',
      'NUL.txt',
      'aux',
      'Prn.tar.gz',
      'dir/COM1',
      'dir/lpt9.png',
      'COM\u00B9.png',
      'CONIN\$',
      'a\\COM3.png',
      'a\u0000.png',
      './../x.png',
    ];
    for (final name in safe) {
      test('safe: "$name"', () => expect(isSafeArchiveEntryName(name), isTrue));
    }
    for (final name in unsafe) {
      test(
        'unsafe: "${name.replaceAll('\u0000', '\\0')}"',
        () => expect(isSafeArchiveEntryName(name), isFalse),
      );
    }
    test('overlong name is unsafe', () {
      expect(isSafeArchiveEntryName('a' * 5000), isFalse);
    });
  });

  group('extractArchiveSafely', () {
    test('extracts a normal archive, skipping directories', () {
      final entries = extractArchiveSafely(
        zipOf({
          'a.png': [1, 2, 3],
          'dir/b.png': List.filled(100, 7),
        }),
        ArchiveLimits.emotes,
      );
      expect(entries.map((e) => e.name).toSet(), {'a.png', 'dir/b.png'});
      expect(entries.firstWhere((e) => e.name == 'a.png').bytes, [1, 2, 3]);
    });

    test('rejects non-zip data', () {
      expectRejected(
        Uint8List.fromList(List.filled(64, 0x41)),
        ArchiveGuardError.invalid,
      );
    });

    test('rejects an archive larger than the archive limit', () {
      final bytes = zipOf({'a.png': List.generate(2000, (i) => i % 251)});
      expectRejected(
        bytes,
        ArchiveGuardError.tooLarge,
        const ArchiveLimits(
          maxArchiveBytes: 100,
          maxEntries: 10,
          maxEntryBytes: 1 << 20,
          maxTotalBytes: 1 << 20,
          maxRatio: 100,
        ),
      );
    });

    test('rejects too many entries', () {
      final bytes = zipOf({
        for (var i = 0; i < 11; i++) 'f$i.png': [i],
      });
      expectRejected(
        bytes,
        ArchiveGuardError.tooManyEntries,
        const ArchiveLimits(
          maxArchiveBytes: 1 << 20,
          maxEntries: 10,
          maxEntryBytes: 1 << 20,
          maxTotalBytes: 1 << 20,
          maxRatio: 100,
        ),
      );
    });

    test('rejects a zip bomb by ratio (small archive, huge content)', () {
      final bytes = zipOf({'zeros.png': Uint8List(8 * 1024 * 1024)});
      expect(bytes.length, lessThan(100 * 1024));
      expectRejected(bytes, ArchiveGuardError.tooLarge);
    });

    test('rejects a single entry above the per-entry limit', () {
      final random = List.generate(4000, (i) => (i * 7919) % 256);
      expectRejected(
        zipOf({'big.png': random}),
        ArchiveGuardError.tooLarge,
        const ArchiveLimits(
          maxArchiveBytes: 1 << 20,
          maxEntries: 10,
          maxEntryBytes: 1000,
          maxTotalBytes: 1 << 20,
          maxRatio: 100,
        ),
      );
    });

    test('rejects when the total of many entries exceeds the total limit', () {
      final files = {
        for (var i = 0; i < 5; i++)
          'f$i.png': List.generate(1000, (j) => (j * 31 + i * 17) % 256),
      };
      expectRejected(
        zipOf(files),
        ArchiveGuardError.tooLarge,
        const ArchiveLimits(
          maxArchiveBytes: 1 << 20,
          maxEntries: 10,
          maxEntryBytes: 2000,
          maxTotalBytes: 4000,
          maxRatio: 100,
        ),
      );
    });

    test('rejects path traversal entries', () {
      for (final name in ['../evil.png', '/etc/evil.png', 'a/../../b.png']) {
        expectRejected(
          zipOf({
            name: [1],
          }),
          ArchiveGuardError.unsafePaths,
        );
      }
    });

    test('rejects an archive whose header lies about the size', () {
      final bytes = zipOf({'a.png': Uint8List(4 * 1024 * 1024)});
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 4; i++) {
        final sig = data.getUint32(i, Endian.little);
        if (sig == 0x04034b50) data.setUint32(i + 22, 10, Endian.little);
        if (sig == 0x02014b50) data.setUint32(i + 24, 10, Endian.little);
      }
      expectRejected(bytes, ArchiveGuardError.tooLarge);
    });

    test('rejects a declared entry count above the limit before decoding', () {
      final bytes = zipOf({
        'a.png': [1],
      });
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      expect(data.getUint32(eocd, Endian.little), 0x06054b50);
      data.setUint16(eocd + 10, 60000, Endian.little);
      expectRejected(bytes, ArchiveGuardError.tooManyEntries);
    });

    test('rejects an oversized central directory before decoding', () {
      final bytes = zipOf({
        'a.png': [1],
      });
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      data.setUint32(eocd + 12, 0x7fffffff, Endian.little);
      expectRejected(bytes, ArchiveGuardError.tooManyEntries);
    });

    test('rejects a directory whose entry count is lower than its records', () {
      final bytes = zipOf({
        'a.png': [1],
        'b.png': [2],
      });
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      expect(data.getUint32(eocd, Endian.little), 0x06054b50);
      data.setUint16(eocd + 8, 1, Endian.little);
      data.setUint16(eocd + 10, 1, Endian.little);
      expectRejected(bytes, ArchiveGuardError.invalid);
    });

    test('rejects a directory size that does not match its records', () {
      final bytes = zipOf({
        'a.png': [1],
        'b.png': [2],
      });
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      final size = data.getUint32(eocd + 12, Endian.little);
      data.setUint32(eocd + 12, size - 1, Endian.little);
      expectRejected(bytes, ArchiveGuardError.invalid);
    });

    test('rejects a zip64 end of central directory locator', () {
      final original = zipOf({
        'a.png': [1],
      });
      final eocd = original.length - 22;
      final source = ByteData.sublistView(original);
      final directoryBytes = source.getUint32(eocd + 12, Endian.little);
      final directoryOffset = source.getUint32(eocd + 16, Endian.little);

      final zip64 = ByteData(76);
      zip64.setUint32(0, 0x06064b50, Endian.little);
      zip64.setUint64(4, 44, Endian.little);
      zip64.setUint16(12, 45, Endian.little);
      zip64.setUint16(14, 45, Endian.little);
      zip64.setUint64(24, 1, Endian.little);
      zip64.setUint64(32, 1, Endian.little);
      zip64.setUint64(40, directoryBytes, Endian.little);
      zip64.setUint64(48, directoryOffset, Endian.little);
      zip64.setUint32(56, 0x07064b50, Endian.little);
      zip64.setUint64(64, eocd, Endian.little);
      zip64.setUint32(72, 1, Endian.little);

      final bytes = Uint8List.fromList([
        ...original.sublist(0, eocd),
        ...zip64.buffer.asUint8List(),
        ...original.sublist(eocd),
      ]);
      expectRejected(bytes, ArchiveGuardError.invalid);
    });

    group('checkZipCentralDirectory (the guard alone, before the decoder)', () {
      void expectInvalid(Uint8List bytes) => expect(
        () => checkZipCentralDirectory(bytes, ArchiveLimits.emotes),
        throwsA(
          isA<ArchiveGuardException>().having(
            (e) => e.error,
            'error',
            ArchiveGuardError.invalid,
          ),
        ),
      );

      Uint8List twoEntries() => zipOf({
        'a.png': [1],
        'b.png': [2],
      });

      test('accepts a normal archive', () {
        checkZipCentralDirectory(twoEntries(), ArchiveLimits.emotes);
      });

      test('rejects a count lower than the number of records', () {
        final bytes = twoEntries();
        final data = ByteData.sublistView(bytes);
        final eocd = bytes.length - 22;
        data.setUint16(eocd + 10, 1, Endian.little);
        expectInvalid(bytes);
      });

      test('rejects a directory size that cuts a record', () {
        final bytes = twoEntries();
        final data = ByteData.sublistView(bytes);
        final eocd = bytes.length - 22;
        final size = data.getUint32(eocd + 12, Endian.little);
        data.setUint32(eocd + 12, size - 1, Endian.little);
        expectInvalid(bytes);
      });

      test('rejects a directory size beyond the end record', () {
        final bytes = twoEntries();
        final data = ByteData.sublistView(bytes);
        final eocd = bytes.length - 22;
        final size = data.getUint32(eocd + 12, Endian.little);
        data.setUint32(eocd + 12, size + 4, Endian.little);
        expectInvalid(bytes);
      });

      for (final offset in [20, 42]) {
        test('rejects a zip64 marker at record offset $offset', () {
          final bytes = twoEntries();
          final data = ByteData.sublistView(bytes);
          final eocd = bytes.length - 22;
          final directory = data.getUint32(eocd + 16, Endian.little);
          data.setUint32(directory + offset, 0xFFFFFFFF, Endian.little);
          expectInvalid(bytes);
        });
      }

      for (final field in [12, 16]) {
        test('rejects a zip64 marker in the end record at $field', () {
          final bytes = twoEntries();
          final data = ByteData.sublistView(bytes);
          final eocd = bytes.length - 22;
          data.setUint32(eocd + field, 0xFFFFFFFF, Endian.little);
          expectInvalid(bytes);
        });
      }
    });

    test('rejects symlink entries', () {
      final bytes = zipOf({'link.png': List.filled(10, 0x41)});
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      final directory = data.getUint32(eocd + 16, Endian.little);
      expect(data.getUint32(directory, Endian.little), 0x02014b50);
      data.setUint16(directory + 4, 0x031e, Endian.little);
      data.setUint32(directory + 38, 0xA1FF << 16, Endian.little);
      expectRejected(bytes, ArchiveGuardError.unsafePaths);
    });

    test(
      'rejects a symlink entry with a huge declared size before decoding',
      () {
        final bytes = zipOf({'link.png': List.filled(10, 0x41)});
        final data = ByteData.sublistView(bytes);
        final eocd = bytes.length - 22;
        final directory = data.getUint32(eocd + 16, Endian.little);
        data.setUint16(directory + 4, 0x031e, Endian.little);
        data.setUint32(directory + 38, 0xA1FF << 16, Endian.little);
        data.setUint32(directory + 24, 0x7fffffff, Endian.little);
        expectRejected(bytes, ArchiveGuardError.unsafePaths);
      },
    );

    test('rejects an oversized declared entry in the directory', () {
      final bytes = zipOf({
        'a.png': [1],
      });
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      final directory = data.getUint32(eocd + 16, Endian.little);
      data.setUint32(directory + 24, 0x7fffffff, Endian.little);
      expectRejected(bytes, ArchiveGuardError.tooLarge);
    });

    test('accepts an empty archive', () {
      expect(extractArchiveSafely(zipOf({})), isEmpty);
    });

    test('rejects data without an end of central directory record', () {
      expectRejected(Uint8List(10), ArchiveGuardError.invalid);
    });
  });
}
