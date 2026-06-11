# Android Tools Inventory from PRoot Ubuntu on Termux

Discovered: 2026-05-31 — Samsung Galaxy A33, Android OS (OneUI), Termux + PRoot Ubuntu

## Environment
- Device: Samsung Galaxy A33 (8GB RAM)
- Host: Termux + PRoot (proot-distro) running Ubuntu 26.04 arm64
- App UID on Android: 11265 (maps to `aid_u0_a1265` user)
- `/` is `/dev/block/dm-55` (f2fs) — the Android userdata partition
- Rootfs: `/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs/`

## `/proc/mounts` reveals Android storage mounts

Even though PRoot isolates the filesystem, `/proc/mounts` shows real Android kernel mounts:

```
/dev/fuse /mnt/installer/0/emulated fuse ...
/dev/fuse /mnt/androidwritable/0/emulated fuse ...
/dev/fuse /mnt/user/0/emulated fuse ...
/dev/block/dm-55 /mnt/pass_through/0/emulated f2fs ...
```

These directories are NOT accessible from PRoot (ls fails with ENOENT), but confirm the FUSE/emulated storage layer exists.

## Android system paths visible from PRoot

| Path | Accessible? | Notes |
|------|-------------|-------|
| `/system/` | ✅ Readable | Android framework files |
| `/system/bin/` | ❌ Permission denied on ls | But individual binaries executable |
| `/system/app/` | ✅ | Pre-installed apps |
| `/system/priv-app/` | ✅ | Privileged apps |
| `/apex/` | ✅ | Android modules |
| `/dev/binder` | ✅ | Symlink to /dev/binderfs/binder |
| `/dev/socket/` | ⚠️ Partial | Some entries show ??? permissions |
| `/data/app/` | ❌ | Empty/blocked by SELinux |
| `/data/data/` | ❌ | Not visible (SELinux) |
| `/sdcard/` | ❌ | Not bind-mounted by default |

## Working Android commands

### `service list` — FULLY WORKS
Returns 389 services including: activity, activity_task, alarm, connectivity, cpu, diskstats, display, input_method, window, network_management, notification, package (but not callable), power, procstats, sensor_privacy, telephony, user, vibrator, wifi.

### `service call` — WORKS with permission limits
```
# Example: calling activity_task (returns Permission Denial as Parcel)
/system/bin/service call activity_task 1
Result: Parcel(
  0x00000000: ffffffff 0000003c 00650050 006d0072 '....<...P.e.r.m.'
  0x00000010: 00730069 00690073 006e006f 00440020 'i.s.s.i.o.n. .D.'
  0x00000020: 006e0065 00610069 003a006c 00700020 'e.n.i.a.l.:. .p.'
  ...
  'Permission Denial: ... uid=11265 ...'
```

### `dumpsys` — WORKS partially
```
/system/bin/dumpsys battery     # Works: shows battery level, temp, etc.
/system/bin/dumpsys meminfo     # Works
/system/bin/dumpsys wifi        # Works
/system/bin/dumpsys package     # FAILS: "Permission Denial: can't dump PackageManager from pid=XXX, uid=11265 due to missing android.permission.DUMP permission"
```

### `service check` — WORKS

### `pm` (Package Manager) — WORKS (updated)
```
pm list packages                  # ✅ Returns ALL installed packages (641 on Samsung A33)
pm path com.termux                # ✅ Returns APK path: /data/app/.../base.apk
pm list features                  # ✅ Returns hardware features
pm get-install-location           # ✅ Works
pm list packages | grep whatsapp  # ✅ Search for specific apps
pm grant <pkg> <perm>             # ❌ FAILS: "Neither user 11265 nor current process has android.permission.GRANT_RUNTIME_PERMISSIONS"
pm dump <pkg>                     # ❌ FAILS: "Permission Denial: can't dump PackageManager"
pm resolve-activity               # ❌ FAILS: SecurityException: INTERACT_ACROSS_USERS_FULL
```

Note: `pm` used to fail with a linker error on older Android versions, but on Samsung A33 (OneUI / Android 14+) it now works for query operations. The calling UID (11265 = Termux app) still lacks GRANT and DUMP permissions.

## Broken Android commands

### `am` (Activity Manager) — FAILS with new error
On this device, `am` no longer fails with the linker error. Instead it reaches the Android framework but is blocked by permission checks:
```
# am start -n com.termux/.app.TermuxActivity
Starting: Intent { cmp=com.termux/.app.TermuxActivity }
java.lang.reflect.InvocationTargetException
Caused by: java.lang.SecurityException: Permission Denial:
startActivityAsUser asks to run as user -2 but is calling from uid u0a1265;
this requires android.permission.INTERACT_ACROSS_USERS_FULL
or android.permission.INTERACT_ACROSS_USERS
```
Root cause: `am` launches with user `-2` (CURRENT_OR_SELF) but the Termux UID (u0a1265) can't act across users. Non-rooted Android 14+ blocks this.

### Old linker failures (may still apply on older Android)
```
WARNING: linker: Warning: failed to find generated linker configuration from "/linkerconfig/ld.config.txt"
```
- `content` — `app_process: inaccessible or not found`
- `cmd` — Can't find the binary or app_process missing

### `pm grant` / `pm dump`
These work differently than the linker failures above — `pm` itself runs, but specific subcommands are permission-denied at the framework level. This is a separate class of failure from the linker issue.

## ADB

- ADB daemon IS listed as a running Android service (`service list` shows `adb`)
- But NO TCP port 5555 is listening — ADB runs on USB transport only
- Installing `adb` client in Ubuntu won't help for device-local ADB (can't connect to itself)
- USB-ADB from the phone to another host is the normal use case

## Termux integration

PATH includes `/data/data/com.termux/files/usr/bin`, but:
- `termux-open` binary NOT found at that path
- `termux-setup-storage` NOT found
- Termux API tools need the separate API app installed

To use Termux features from PRoot, bind-mount:
```
proot-distro login ubuntu --bind /data/data/com.termux/files/usr/bin:/termux-bin
```
Then call `/termux-bin/termux-open`, `/termux-bin/termux-notification`, etc.

## Key takeaway

PRoot provides Linux syscall translation on Android, but the Android Java framework (ART/Dalvik/app_process) is NOT fully available. Native Android tools (`dumpsys`, `service`, `pm` for queries) work as they're C++ system services accessible via Binder, but subject to the calling Termux app UID's permission level. Tools that need to launch activities or cross users (`am`) or need elevated permissions (`pm grant`, `pm dump`) fail on non-rooted devices. Behavior varies significantly across Android versions — always test on the target device.
