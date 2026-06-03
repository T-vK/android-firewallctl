/*
 * App-private allowlist (root watcher also reads this path).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

final class LocalAllowlist {

    private static final String TAG = "FirewallNotify";
    private static final String FILENAME = "allowlist.txt";

    private LocalAllowlist() {
    }

    static File file(Context ctx) {
        return new File(ctx.getFilesDir(), FILENAME);
    }

    static void add(Context ctx, String pkg) {
        if (ctx == null || pkg == null || pkg.isEmpty()) {
            return;
        }
        try {
            File file = file(ctx);
            File parent = file.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            FileOutputStream fos = new FileOutputStream(file, true);
            fos.write((pkg + "\n").getBytes(StandardCharsets.UTF_8));
            fos.close();
            Log.i(TAG, "local allowlist: added " + pkg);
        } catch (Throwable t) {
            Log.w(TAG, "local allowlist: " + t.getMessage());
        }
    }
}
