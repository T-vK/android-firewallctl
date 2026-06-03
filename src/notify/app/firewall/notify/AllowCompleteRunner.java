/*
 * Signals allow success to the running FirewallNotify app via sendBroadcast.
 * Used from the root watcher when shell "am broadcast" fails on some ROMs.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Looper;

public final class AllowCompleteRunner {

    private static final String PACKAGE = "app.firewall.notify";
    private static final int CONTEXT_INCLUDE_CODE = 0x00000001;
    private static final int CONTEXT_IGNORE_SECURITY = 0x00000002;

    private AllowCompleteRunner() {
    }

    public static void main(String[] args) {
        if (args.length < 1 || args[0].isEmpty()) {
            System.err.println("AllowCompleteRunner: missing package argument");
            System.exit(2);
        }
        String pkg = args[0];
        try {
            Looper.prepareMainLooper();
            Context ctx = getAppContext();
            Intent intent = new Intent(AllowCompleteReceiver.ACTION_ALLOW_COMPLETE);
            intent.setComponent(new ComponentName(PACKAGE, PACKAGE + ".AllowCompleteReceiver"));
            intent.setPackage(PACKAGE);
            intent.putExtra(NotifyHelper.EXTRA_PACKAGE, pkg);
            ctx.sendBroadcast(intent);
            System.out.println("AllowCompleteRunner: broadcast for " + pkg);
            System.exit(0);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("AllowCompleteRunner: " + c.getClass().getSimpleName()
                    + ": " + c.getMessage());
            System.exit(1);
        }
    }

    private static Context getAppContext() throws Exception {
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context system = (Context) at.getMethod("getSystemContext").invoke(thread);
        int flags = CONTEXT_INCLUDE_CODE | CONTEXT_IGNORE_SECURITY;
        return system.createPackageContext(PACKAGE, flags);
    }
}
