/*
 * firewallctl - LineageOS per-app firewall policy CLI
 *
 * Talks to NetworkPolicyManagerService via Binder using only reflection.
 * No compile-time dependency on android.jar; no APK; no Google libraries.
 * Run via app_process as root. See scripts/firewallctl on-device wrapper.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewallctl;

import java.io.BufferedReader;
import java.io.FileReader;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.LinkedHashMap;
import java.util.Map;

public final class Main {

    private static final String SERVICE_NAME = "netpolicy";
    private static final String NPM_CLASS = "android.net.NetworkPolicyManager";
    private static final String INPM_STUB_CLASS = "android.net.INetworkPolicyManager$Stub";
    private static final String SERVICE_MANAGER_CLASS = "android.os.ServiceManager";
    private static final String IBINDER_CLASS = "android.os.IBinder";

    private Object npm;
    private Map<String, Integer> policies;

    public static void main(String[] args) {
        try {
            relaxHiddenApi();
            new Main().run(args);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("firewallctl: " + c.getClass().getSimpleName() + ": " + c.getMessage());
            System.exit(1);
        }
    }

    private void run(String[] args) throws Exception {
        if (args.length == 0) { usage(); return; }
        connect();
        String cmd = args[0];
        switch (cmd) {
            case "get":            doGet(args); break;
            case "set":            doSet(args); break;
            case "clear":          doClear(args); break;
            case "list-policies":  doListPolicies(); break;
            case "list-uids":      doListUids(); break;
            case "-h": case "--help": case "help": usage(); break;
            default:
                System.err.println("Unknown command: " + cmd);
                usage();
                System.exit(2);
        }
    }

    private void connect() throws Exception {
        Class<?> sm = Class.forName(SERVICE_MANAGER_CLASS);
        Object binder = sm.getMethod("getService", String.class).invoke(null, SERVICE_NAME);
        if (binder == null) throw new RuntimeException("netpolicy service not available (run as root?)");
        Class<?> ibinder = Class.forName(IBINDER_CLASS);
        Class<?> stub = Class.forName(INPM_STUB_CLASS);
        npm = stub.getMethod("asInterface", ibinder).invoke(null, binder);
        policies = new LinkedHashMap<>();
        Class<?> npmCls = Class.forName(NPM_CLASS);
        for (Field f : npmCls.getFields()) {
            if (f.getType() == int.class && Modifier.isStatic(f.getModifiers())
                    && f.getName().startsWith("POLICY_")) {
                policies.put(f.getName(), f.getInt(null));
            }
        }
    }

    private int resolveUid(String s) throws Exception {
        try { return Integer.parseInt(s); } catch (NumberFormatException ignored) {}
        try (BufferedReader br = new BufferedReader(new FileReader("/data/system/packages.list"))) {
            String line;
            while ((line = br.readLine()) != null) {
                int sp1 = line.indexOf(' ');
                if (sp1 < 0) continue;
                if (!s.equals(line.substring(0, sp1))) continue;
                int sp2 = line.indexOf(' ', sp1 + 1);
                String uidStr = sp2 < 0 ? line.substring(sp1 + 1) : line.substring(sp1 + 1, sp2);
                return Integer.parseInt(uidStr);
            }
        }
        throw new RuntimeException("package not found in /data/system/packages.list: " + s);
    }

    private int getUidPolicy(int uid) throws Exception {
        return (int) npm.getClass().getMethod("getUidPolicy", int.class).invoke(npm, uid);
    }

    private void setUidPolicy(int uid, int policy) throws Exception {
        npm.getClass().getMethod("setUidPolicy", int.class, int.class).invoke(npm, uid, policy);
    }

    private String describePolicy(int policy) {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, Integer> e : policies.entrySet()) {
            int v = e.getValue();
            if (v != 0 && (policy & v) == v) {
                if (sb.length() > 0) sb.append(", ");
                sb.append(e.getKey());
            }
        }
        return sb.length() == 0 ? "POLICY_NONE" : sb.toString();
    }

    private int resolveFlag(String name) {
        if (!name.startsWith("POLICY_")) name = "POLICY_" + name;
        Integer v = policies.get(name);
        if (v == null) throw new RuntimeException(
                "unknown policy flag on this ROM: " + name + " (run list-policies)");
        return v;
    }

    private void doGet(String[] args) throws Exception {
        if (args.length < 2) { System.err.println("Usage: get <uid|package>"); System.exit(2); }
        int uid = resolveUid(args[1]);
        int p = getUidPolicy(uid);
        System.out.printf("uid=%d  policy=0x%x  flags=[%s]%n", uid, p, describePolicy(p));
    }

    private void doSet(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("Usage: set <uid|package> {+|-}FLAG [...]"); System.exit(2);
        }
        int uid = resolveUid(args[1]);
        int before = getUidPolicy(uid);
        int target = before;
        for (int i = 2; i < args.length; i++) {
            String spec = args[i];
            if (spec.length() < 2 || (spec.charAt(0) != '+' && spec.charAt(0) != '-')) {
                throw new RuntimeException("flag must start with + or -: " + spec);
            }
            int v = resolveFlag(spec.substring(1));
            target = spec.charAt(0) == '+' ? (target | v) : (target & ~v);
        }
        setUidPolicy(uid, target);
        int after = getUidPolicy(uid);
        System.out.printf("uid=%d  before=0x%x  requested=0x%x  after=0x%x%n",
                uid, before, target, after);
        System.out.printf("flags=[%s]%n", describePolicy(after));
    }

    private void doClear(String[] args) throws Exception {
        if (args.length < 2) { System.err.println("Usage: clear <uid|package>"); System.exit(2); }
        int uid = resolveUid(args[1]);
        setUidPolicy(uid, 0);
        System.out.printf("uid=%d  policy cleared%n", uid);
    }

    private void doListPolicies() {
        System.out.println("POLICY_* constants exposed by this ROM:");
        for (Map.Entry<String, Integer> e : policies.entrySet()) {
            System.out.printf("  %-40s 0x%x%n", e.getKey(), e.getValue());
        }
    }

    private void doListUids() throws Exception {
        try (BufferedReader br = new BufferedReader(new FileReader("/data/system/packages.list"))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split(" ", 3);
                if (parts.length < 2) continue;
                int uid;
                try { uid = Integer.parseInt(parts[1]); } catch (NumberFormatException e) { continue; }
                int p = getUidPolicy(uid);
                if (p != 0) {
                    System.out.printf("uid=%-6d  policy=0x%-8x  pkg=%s%n    flags=[%s]%n",
                            uid, p, parts[0], describePolicy(p));
                }
            }
        }
    }

    private void usage() {
        String s = ""
                + "firewallctl - LineageOS per-app firewall policy CLI\n"
                + "\n"
                + "Commands:\n"
                + "  get <uid|package>                    show current policy\n"
                + "  set <uid|package> {+|-}FLAG [...]    add/remove policy flags\n"
                + "  clear <uid|package>                  reset policy to 0\n"
                + "  list-policies                        list POLICY_* this ROM supports\n"
                + "  list-uids                            list all UIDs with non-zero policy\n"
                + "\n"
                + "Flag names accept the POLICY_ prefix or omit it. Typical Lineage names:\n"
                + "  POLICY_REJECT_ALL                  ('Allow network access' OFF)\n"
                + "  POLICY_REJECT_WIFI                 ('Wi-Fi data' OFF)\n"
                + "  POLICY_REJECT_CELLULAR             ('Mobile data' OFF)\n"
                + "  POLICY_REJECT_VPN                  ('VPN data' OFF)\n"
                + "  POLICY_REJECT_METERED_BACKGROUND   ('Background data' OFF, denylist)\n"
                + "  POLICY_ALLOW_METERED_BACKGROUND    ('Unrestricted mobile data' ON, allowlist)\n"
                + "\n"
                + "Examples:\n"
                + "  firewallctl set com.example.app +REJECT_ALL\n"
                + "  firewallctl set 10123 +REJECT_WIFI +REJECT_CELLULAR\n"
                + "  firewallctl set com.example.app -REJECT_ALL\n"
                + "  firewallctl get com.example.app\n"
                + "  firewallctl list-policies\n"
                + "\n"
                + "Requires root. Changes are reflected in Settings > Apps > <App> immediately.\n";
        System.out.print(s);
    }

    /** Best-effort hidden-API exemption (no-op on Android < 9 / outside zygote). */
    private static void relaxHiddenApi() {
        try {
            Method forName = Class.class.getDeclaredMethod("forName", String.class);
            Method getDecl = Class.class.getDeclaredMethod(
                    "getDeclaredMethod", String.class, Class[].class);
            Class<?> vmrt = (Class<?>) forName.invoke(null, "dalvik.system.VMRuntime");
            Method getRuntime = (Method) getDecl.invoke(vmrt, "getRuntime", new Class[0]);
            Method setEx = (Method) getDecl.invoke(
                    vmrt, "setHiddenApiExemptions", new Class[]{String[].class});
            setEx.invoke(getRuntime.invoke(null), new Object[]{new String[]{"L"}});
        } catch (Throwable ignored) { /* fine */ }
    }
}
