# autolock — enforce screen lock after 1 minute, password required immediately

The headline control of the lazybox macOS fleet-hardening toolkit:

> Lock the screen after **60 seconds** of inactivity and require a password
> **immediately** (zero grace period) to get back in.

This component delivers that with two layers:

1. **A configuration profile (authoritative).** `com.lazybox.autolock.mobileconfig`
   carries a `com.apple.screensaver` payload. This is the supported,
   reliable way to enforce password-on-wake on modern macOS.
2. **A polling watchdog (defense-in-depth).** `idle-lock.sh`, run as a per-user
   LaunchAgent, independently locks the screen after the idle threshold. This
   is the backstop for **unmanaged** devices where a profile cannot be pushed.

---

## Why a profile is authoritative (the Sonoma caveat)

Historically you could set the lock policy with per-host preferences:

```sh
defaults -currentHost write com.apple.screensaver idleTime 60
defaults -currentHost write com.apple.screensaver askForPassword -int 1
defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0
```

As of **macOS Sonoma (14)** the `askForPassword` / `askForPasswordDelay`
preferences set this way **stopped being honored reliably** — the screensaver
subsystem no longer treats the written `defaults` values as the source of
truth for password-on-wake. The supported mechanism is now a **configuration
profile** with a `com.apple.screensaver` payload (typically delivered by MDM).
A managed profile sets the effective policy and prevents the user from
weakening it.

That is why the profile — not `defaults write` — is the primary control here.

## What the profile sets

`com.lazybox.autolock.mobileconfig` — top-level `PayloadType` `Configuration`,
`PayloadScope` `System`, `PayloadIdentifier` `com.lazybox.autolock`, fixed
UUIDs. One nested `com.apple.screensaver` payload with:

| Key                   | Value | Meaning                                            |
| --------------------- | ----- | -------------------------------------------------- |
| `idleTime`            | `60`  | Start the screen saver after 60s of inactivity.    |
| `askForPassword`      | `1`   | Require a password to wake from the screen saver.  |
| `askForPasswordDelay` | `0`   | Demand the password **immediately** (no grace).    |
| `loginWindowIdleTime` | `60`  | Also drop to the login window after 60s idle.      |

`idleTime=60` + `askForPasswordDelay=0` is what produces "lock after 1 minute,
password required immediately."

## Why a LaunchAgent, not a LaunchDaemon (for the watchdog)

Locking the screen means talking to the user's **WindowServer / GUI (Aqua)
session**. The mechanics:

- A **LaunchDaemon** runs as `root` at the system level with **no GUI session
  attached**. It can run code, but it **cannot lock the screen** — there is no
  session to suspend. `CGSession -suspend` from a daemon has nothing to act on.
- A **LaunchAgent** is loaded **into each user's GUI session** (`gui/<uid>`
  domain). It runs as the logged-in user, with a live WindowServer connection,
  so `CGSession -suspend` actually locks that user's screen.

Hence `com.lazybox.idlelock.plist` is a LaunchAgent, installed to
`/Library/LaunchAgents/` (applies to all users) and bootstrapped into the
console user's `gui/<uid>` domain.

### Why `CGSession -suspend` to lock

```
/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend
```

This is the "fast user switching → login window" path. It locks immediately,
is built into macOS, and — unlike scripting `System Events` or simulating the
Ctrl-Cmd-Q hotkey — needs **no Accessibility / Automation permission grant**,
so it works headlessly under launchd.

## Idle detection

`idle-lock.sh` reads HID idle time from IOKit:

```sh
ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'
```

`HIDIdleTime` is nanoseconds since the last keyboard/mouse input; dividing by
1e9 gives seconds. The watchdog polls every `POLL_INTERVAL` seconds (default 5)
and locks when idle ≥ threshold.

Threshold resolution (first wins): `$1` positional arg → `IDLE_THRESHOLD` env →
default `60`. Poll interval: `POLL_INTERVAL` env → default `5`.

The script is resilient: missing binaries are logged and it sleeps rather than
hot-looping under launchd `KeepAlive`; transient `ioreg` read failures are
retried.

---

## Files

| File                              | Purpose                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| `com.lazybox.autolock.mobileconfig` | Authoritative screensaver/lock policy profile.              |
| `idle-lock.sh`                    | Defense-in-depth idle watchdog (locks via CGSession).          |
| `com.lazybox.idlelock.plist`      | LaunchAgent that runs the watchdog in the user GUI session.    |
| `install.sh`                      | Installs profile + watchdog + agent; bootstraps the agent.     |
| `uninstall.sh`                    | Reverses the install.                                          |
| `verify.sh`                       | Audit-only: asserts profile, effective policy, agent loaded.   |

---

## Deployment

### Managed fleet (recommended) — deliver the profile via MDM

Upload `com.lazybox.autolock.mobileconfig` to your MDM (Jamf, Kandji, Intune,
Mosyle, …) as a custom configuration profile and scope it to your fleet. The
MDM owns the profile lifecycle.

Then, if you also want the watchdog as a backstop, run the installer with the
profile step skipped (so it does not fight the MDM-managed profile):

```sh
sudo LAZYBOX_SKIP_PROFILE=1 ./install.sh
```

> Do **not** manually `profiles install` a profile that your MDM also manages —
> the two can conflict.

### Standalone / unmanaged device

Installs the profile locally **and** the watchdog:

```sh
sudo ./install.sh
```

`install.sh` will:

1. `profiles install -type configuration -path com.lazybox.autolock.mobileconfig`
2. Copy `idle-lock.sh` → `/usr/local/lib/lazybox/idle-lock.sh`
3. Copy `com.lazybox.idlelock.plist` → `/Library/LaunchAgents/`
4. `launchctl bootstrap gui/<uid> …` for the console user

> The watchdog sources the shared `lib/common.sh`. The installer also copies it
> to `/usr/local/lib/lib/common.sh` so the installed script can find it
> (`idle-lock.sh` resolves `../lib/common.sh` relative to its own location).

### Uninstall

```sh
sudo ./uninstall.sh            # also removes the local profile
sudo LAZYBOX_SKIP_PROFILE=1 ./uninstall.sh   # leave the MDM-managed profile alone
```

---

## Verify

```sh
sudo ./verify.sh
```

This asserts (audit-only, mutates nothing):

- the `com.lazybox.autolock` profile is installed;
- effective `idleTime=60`, `askForPassword=1`, `askForPasswordDelay=0`;
- the profile carries the `loginWindowIdleTime` payload;
- the LaunchAgent plist exists and is loaded in the console user's GUI session.

Run as root and with a user logged in at the GUI for the per-user and
session-loaded checks to be meaningful. `verify.sh` exits non-zero if any
assertion fails (CI-friendly).

You can also eyeball the effective policy manually:

```sh
profiles show -output stdout-xml | grep -A1 askForPasswordDelay
defaults -currentHost read com.apple.screensaver
```
