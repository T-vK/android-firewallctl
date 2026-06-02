/*
 * Actionable notification when a new app is default-denied.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewallctl;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;

public final class BlockedAppNotifier implements NotifyReceiver.Callback {

    public static final String EXTRA_PACKAGE = "package";

    private static final String CHANNEL_ID = "firewall_default_deny";
    private static final String CHANNEL_NAME = "Firewall default deny";
    private static final int NOTIFICATION_ID = 0x464444;

    private static final String ACTION_ALLOW = "app.firewallctl.action.ALLOW_NETWORK";
    private static final String ACTION_SETTINGS = "app.firewallctl.action.OPEN_NETWORK_SETTINGS";

    private static final String ALLOWLIST_PATH = "/data/adb/firewall_default_deny/allowlist.txt";
    private static final long TIMEOUT_MS = 30L * 60L * 1000L;
    private static final int FLAG_IMMUTABLE = 0x04000000;
    private static final int RECEIVER_EXPORTED = 0x2;

    private final Object lock = new Object();
    private boolean finished;

    private Context context;
    private NotificationManager notificationManager;
    private NotifyReceiver allowReceiver;
    private String notificationTag;
    private String blockedPackage;

    public static void main(String[] args) {
        try {
            Main.relaxHiddenApi();
            new BlockedAppNotifier().run(args);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("firewallctl-notify: "
                    + c.getClass().getSimpleName() + ": " + c.getMessage());
            System.exit(1);
        }
    }

    private void run(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("Usage: BlockedAppNotifier <package>");
            System.exit(2);
        }
        blockedPackage = args[0];
        notificationTag = "firewall_default_deny_" + blockedPackage;

        context = getSystemContext();
        notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);

        registerReceivers();
        try {
            createChannel();
            postNotification(blockedPackage);
            waitForCompletion();
        } finally {
            unregisterReceivers();
        }
    }

    private void waitForCompletion() throws InterruptedException {
        synchronized (lock) {
            if (!finished) {
                lock.wait(TIMEOUT_MS);
            }
        }
    }

    private void finish() {
        synchronized (lock) {
            if (finished) {
                return;
            }
            finished = true;
            cancelNotification();
            lock.notifyAll();
        }
    }

    @Override
    public void onAction(String action, String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            pkg = blockedPackage;
        }
        if (ACTION_ALLOW.equals(action)) {
            onAllowNetwork(pkg);
            finish();
        } else if (ACTION_SETTINGS.equals(action)) {
            onOpenNetworkSettings(pkg);
            finish();
        }
    }

    private static Context getSystemContext() throws Exception {
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        return (Context) at.getMethod("getSystemContext").invoke(thread);
    }

    private void createChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT);
        notificationManager.createNotificationChannel(channel);
    }

    private void postNotification(String pkg) throws Exception {
        String label = resolveAppLabel(pkg);
        String title = "Internet blocked for new app";
        String text = label + " — network access was disabled by default.";

        int iconId = context.getResources().getIdentifier(
                "stat_sys_warning", "drawable", "android");
        if (iconId == 0) {
            iconId = context.getResources().getIdentifier(
                    "ic_dialog_alert", "drawable", "android");
        }

        int flags = PendingIntent.FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE;
        PendingIntent settingsPi = activityPendingIntent(pkg, 1);

        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(iconId)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(
                        text + "\n\nPackage: " + pkg + "\n\nTap to open network settings."))
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setContentIntent(settingsPi)
                .addAction(new Notification.Action.Builder(
                        0, "Allow network",
                        PendingIntent.getBroadcast(context, pkg.hashCode() + 2,
                                buildBroadcastIntent(ACTION_ALLOW, pkg), flags))
                        .build())
                .addAction(new Notification.Action.Builder(
                        0, "Network settings", settingsPi)
                        .build());

        Object user = Class.forName("android.os.UserHandle").getField("CURRENT").get(null);
        notificationManager.getClass().getMethod(
                "notifyAsUser", String.class, int.class, Notification.class,
                Class.forName("android.os.UserHandle"))
                .invoke(notificationManager, notificationTag, NOTIFICATION_ID,
                        builder.build(), user);
    }

    private PendingIntent activityPendingIntent(String pkg, int requestCode) {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE;
        return PendingIntent.getActivity(context, pkg.hashCode() + requestCode,
                buildDataSettingsIntent(pkg), flags);
    }

    private Intent buildBroadcastIntent(String action, String pkg) {
        Intent intent = new Intent(action);
        intent.setPackage(context.getPackageName());
        intent.putExtra(EXTRA_PACKAGE, pkg);
        return intent;
    }

    private void registerReceivers() {
        allowReceiver = new NotifyReceiver(ACTION_ALLOW, this);
        IntentFilter allowFilter = new IntentFilter(ACTION_ALLOW);
        registerReceiverExported(allowReceiver, allowFilter);
    }

    private void registerReceiverExported(NotifyReceiver receiver, IntentFilter filter) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, RECEIVER_EXPORTED);
                return;
            }
        } catch (Throwable ignored) { /* fall through */ }
        context.registerReceiver(receiver, filter);
    }

    private void unregisterReceivers() {
        try {
            if (allowReceiver != null) {
                context.unregisterReceiver(allowReceiver);
            }
        } catch (Throwable ignored) { /* fine */ }
    }

    private void onAllowNetwork(String pkg) {
        try {
            appendAllowlist(pkg);
            Main main = new Main();
            main.run(new String[]{"clear", pkg});
        } catch (Throwable t) {
            System.err.println("firewallctl-notify: allow failed for " + pkg + ": " + t.getMessage());
        }
    }

    private void onOpenNetworkSettings(String pkg) {
        try {
            Intent intent = buildDataSettingsIntent(pkg);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        } catch (Throwable t) {
            System.err.println("firewallctl-notify: settings intent failed for " + pkg
                    + ": " + t.getMessage());
        }
    }

    private static Intent buildDataSettingsIntent(String pkg) {
        Intent[] candidates = new Intent[] {
                new Intent("android.settings.APP_DATA_USAGE")
                        .putExtra("android.intent.extra.PACKAGE_NAME", pkg),
                new Intent("android.intent.action.MANAGE_NETWORK_USAGE")
                        .setData(Uri.parse("package:" + pkg)),
                new Intent("android.settings.APPLICATION_DETAILS_SETTINGS")
                        .setData(Uri.parse("package:" + pkg)),
        };
        PackageManager pm = null;
        try {
            pm = getSystemContext().getPackageManager();
        } catch (Exception ignored) { /* use first resolvable */ }
        for (Intent intent : candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (pm == null || intent.resolveActivity(pm) != null) {
                return intent;
            }
        }
        return candidates[candidates.length - 1];
    }

    private static void appendAllowlist(String pkg) throws Exception {
        File file = new File(ALLOWLIST_PATH);
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) {
            //noinspection ResultOfMethodCallIgnored
            parent.mkdirs();
        }
        try (BufferedReader br = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = br.readLine()) != null) {
                String trimmed = line.trim();
                if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                    continue;
                }
                if (trimmed.equals(pkg)) {
                    return;
                }
            }
        } catch (Exception ignored) {
            /* new file */
        }
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(file, true))) {
            bw.write(pkg);
            bw.newLine();
        }
    }

    private String resolveAppLabel(String pkg) {
        try {
            PackageManager pm = context.getPackageManager();
            ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
            return String.valueOf(info.loadLabel(pm));
        } catch (Throwable t) {
            return pkg;
        }
    }

    private void cancelNotification() {
        try {
            Object user = Class.forName("android.os.UserHandle").getField("CURRENT").get(null);
            notificationManager.getClass().getMethod(
                    "cancelAsUser", String.class, int.class,
                    Class.forName("android.os.UserHandle"))
                    .invoke(notificationManager, notificationTag, NOTIFICATION_ID, user);
        } catch (Throwable ignored) { /* fine */ }
    }
}
