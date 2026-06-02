/*
 * Transparent trampoline: allow network for a blocked package.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.os.Bundle;

public final class AllowActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String pkg = getIntent().getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg != null && !pkg.isEmpty()) {
            runAllowScript(pkg);
            NotifyHelper.cancel(this, pkg);
        }
        finish();
    }

    private static void runAllowScript(String pkg) {
        try {
            Process p = new ProcessBuilder("/system/bin/su", "0",
                    "/system/bin/firewall-allow-app", pkg)
                    .redirectErrorStream(true)
                    .start();
            p.waitFor();
        } catch (Throwable t) {
            try {
                Process p = new ProcessBuilder("/system/bin/firewall-allow-app", pkg)
                        .redirectErrorStream(true)
                        .start();
                p.waitFor();
            } catch (Throwable ignored) {
                /* logged by script / watcher if needed */
            }
        }
    }
}
