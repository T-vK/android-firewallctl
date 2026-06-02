/*
 * Posts a notification via app_process (no am/cmd IPC). Used when am start/broadcast
 * fails with Binder transaction errors on some ROMs.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.Context;
import android.os.Looper;

public final class NotifyRunner {

    private NotifyRunner() {
    }

    public static void main(String[] args) {
        if (args.length < 1 || args[0].isEmpty()) {
            System.err.println("NotifyRunner: missing package argument");
            System.exit(2);
        }
        try {
            Looper.prepareMainLooper();
            Context ctx = getSystemContext();
            NotifyHelper.showBlocked(ctx, args[0]);
            System.exit(0);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("NotifyRunner: " + c.getClass().getSimpleName() + ": " + c.getMessage());
            System.exit(1);
        }
    }

    private static Context getSystemContext() throws Exception {
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        return (Context) at.getMethod("getSystemContext").invoke(thread);
    }
}
