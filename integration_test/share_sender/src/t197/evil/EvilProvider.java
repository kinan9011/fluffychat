// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Test fixture: a hostile sender app. Never ship it. It answers _display_name queries with
// path traversal and bidi names so that scripts/test_share_intent.sh can prove they are contained.
package t197.evil;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileOutputStream;

public class EvilProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    private String nameFor(Uri uri) {
        String key = uri.getLastPathSegment();
        if ("trav".equals(key)) return "../files/t197_canary";
        if ("prefs".equals(key)) return "../shared_prefs/t197_canary.xml";
        if ("abs".equals(key)) return "/data/local/tmp/t197_abs";
        if ("rlo".equals(key)) return "invoice\u202Efdp.exe";
        if ("ok".equals(key)) return "holiday photo.txt";
        return null;
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
        MatrixCursor c = new MatrixCursor(new String[] {"_display_name", "_size"});
        c.addRow(new Object[] {nameFor(uri), 8L});
        return c;
    }

    @Override public String getType(Uri uri) { return "text/plain"; }

    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws java.io.FileNotFoundException {
        try {
            File f = new File(getContext().getCacheDir(), "payload.txt");
            try (FileOutputStream o = new FileOutputStream(f)) { o.write("ATTACKER".getBytes()); }
            return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
        } catch (java.io.IOException e) { throw new java.io.FileNotFoundException(e.toString()); }
    }

    @Override public Uri insert(Uri uri, ContentValues v) { return null; }
    @Override public int delete(Uri uri, String s, String[] a) { return 0; }
    @Override public int update(Uri uri, ContentValues v, String s, String[] a) { return 0; }
}
