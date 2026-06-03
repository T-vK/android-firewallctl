/*
 * Posts a notification via app_process (no am/cmd IPC). Used when am start/broadcast
 * fails with Binder transaction errors on some ROMs.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.Context;
import android.os.Looper;

public final class NotifyRunner {

    private static final String PACKAGE = "app.firewall.notify";
    private static final int CONTEXT_INCLUDE_CODE = 0x00000001;
    private static final int CONTEXT_IGNORE_SECURITY = 0x00000002;

    private NotifyRunner() {
    }

    public static void main(String[] args) {
        if (args.length < 1 || args[0].isEmpty()) {
            System.err.println("NotifyRunner: missing package argument");
            System.exit(2);
        }
        try {
            Looper.prepareMainLooper();
            grantNotificationPermission();
            Context ctx = getAppContext();
            android.app.NotificationManager nm =
                    (android.app.NotificationManager) ctx.getSystemService(
                            android.content.Context.NOTIFICATION_SERVICE);
            if (nm != null && !nm.areNotificationsEnabled()) {
                grantNotificationPermission();
                if (!nm.areNotificationsEnabled()) {
                    System.err.println("NotifyRunner: POST_NOTIFICATIONS not granted");
                    System.exit(1);
                }
            }
            if (args.length >= 2 && NotifyHelper.KIND_INSTALL_DETECT.equals(args[1])) {
                NotifyHelper.showInstallDetected(ctx, args[0], null);
                System.out.println("NotifyRunner: install_detect posted for " + args[0]);
            } else {
                NotifyHelper.showBlocked(ctx, args[0]);
                System.out.println("NotifyRunner: posted for " + args[0]);
            }
            System.exit(0);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("NotifyRunner: " + c.getClass().getSimpleName() + ": " + c.getMessage());
            System.exit(1);
        }
    }

    private static void grantNotificationPermission() {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{
                    "/system/bin/pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS"});
            p.waitFor();
        } catch (Throwable ignored) {
            /* best-effort */
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
