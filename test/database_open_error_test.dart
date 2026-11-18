// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/database_open_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/src/utils/client_init_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/sqflite_ffi_exception.dart';

DatabaseException _withCode(int code) => SqfliteFfiException(
  code: 'sqlite_error',
  message: 'error',
  resultCode: code,
);

void main() {
  group('only an explicit SQLITE_CORRUPT is a corrupt database', () {
    // primary code and extended codes (primary | (n << 8))
    for (final code in [11, 267, 523, 779, 1035, 11 | (9 << 8)]) {
      test('result code $code', () {
        expect(
          classifyDatabaseOpenError(_withCode(code)),
          DatabaseOpenFailure.corrupt,
        );
      });
    }
  });

  group('everything else is left alone', () {
    const names = {
      0: 'OK',
      1: 'ERROR',
      2: 'INTERNAL',
      3: 'PERM',
      4: 'ABORT',
      5: 'BUSY',
      6: 'LOCKED',
      7: 'NOMEM',
      8: 'READONLY',
      9: 'INTERRUPT',
      10: 'IOERR',
      12: 'NOTFOUND',
      13: 'FULL',
      14: 'CANTOPEN',
      15: 'PROTOCOL',
      16: 'EMPTY',
      17: 'SCHEMA',
      18: 'TOOBIG',
      19: 'CONSTRAINT',
      20: 'MISMATCH',
      21: 'MISUSE',
      22: 'NOLFS',
      23: 'AUTH',
      24: 'FORMAT',
      25: 'RANGE',
      26: 'NOTADB (a wrong key looks the same)',
      27: 'NOTICE',
      28: 'WARNING',
      261: 'BUSY_RECOVERY',
      517: 'BUSY_SNAPSHOT',
      262: 'LOCKED_SHAREDCACHE',
      266: 'IOERR_READ',
      522: 'IOERR_SHORT_READ',
      778: 'IOERR_WRITE',
      3338: 'IOERR_FSYNC',
      3850: 'IOERR_NOMEM',
      3082: 'IOERR_VNODE',
      270: 'CANTOPEN_ISDIR',
      1038: 'CANTOPEN_NOTEMPDIR',
      1032: 'READONLY_DBMOVED',
      13 | (1 << 8): 'FULL_x',
      100: 'ROW',
      101: 'DONE',
    };
    for (final entry in names.entries) {
      test('result code ${entry.key} ${entry.value}', () {
        expect(
          classifyDatabaseOpenError(_withCode(entry.key)),
          DatabaseOpenFailure.other,
        );
      });
    }

    test('a negative code is not read as its low byte', () {
      expect(
        classifyDatabaseOpenError(_withCode(-245)),
        DatabaseOpenFailure.other,
      );
    });

    test('a code in the message is read like a result code', () {
      expect(
        classifyDatabaseOpenError(
          SqfliteFfiException(
            code: 'sqlite_error',
            message: 'disk image (sqlite code 11)',
          ),
        ),
        DatabaseOpenFailure.corrupt,
      );
      expect(
        classifyDatabaseOpenError(
          SqfliteFfiException(
            code: 'sqlite_error',
            message: 'database is locked (sqlite code 5)',
          ),
        ),
        DatabaseOpenFailure.other,
      );
    });

    for (final error in <Object>[
      StateError('database disk image is malformed'),
      Exception('SQLITE_CORRUPT'),
      'sqlite code 11',
      SqfliteFfiException(
        code: 'sqlite_error',
        message: 'database disk image is malformed',
      ),
      SqfliteFfiException(code: 'sqlite_error', message: 'error'),
      const FormatException('x'),
    ]) {
      test('unclassified: $error', () {
        expect(classifyDatabaseOpenError(error), DatabaseOpenFailure.other);
      });
    }
  });

  group('set-aside is offered only when the file itself is unusable (F7)', () {
    bool offered(Object error) =>
        DatabaseOpenFailedException('a', error).setAsideMayHelp;

    test('not a database and corrupt files', () {
      expect(offered(_withCode(26)), isTrue);
      expect(offered(_withCode(11)), isTrue);
      expect(offered(_withCode(267)), isTrue);
      expect(offered(ClientInitException(_withCode(26))), isTrue);
    });

    test('busy, full, I/O, network and unknown causes only offer Retry', () {
      for (final code in [1, 5, 6, 8, 10, 13, 14]) {
        expect(offered(_withCode(code)), isFalse, reason: 'code $code');
      }
      for (final error in <Object>[
        const SocketException('x'),
        const FileSystemException('x'),
        TimeoutException('x'),
        http.ClientException('x'),
        PlatformException(code: 'keystore'),
        SqfliteFfiException(code: 'sqlite_error', message: 'x'),
        ClientInitException(const SocketException('x')),
        StateError('x'),
      ]) {
        expect(offered(error), isFalse, reason: error.runtimeType.toString());
      }
    });

    test('main hands the account to the page only when it is offered', () {
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('e.setAsideMayHelp'),
      );
    });
  });
}
