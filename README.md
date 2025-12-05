# mac_cleanup — README

**Purpose.**

`mac_cleanup.sh` is a reusable, safe, and auditable bash script designed to free disk space on macOS developer machines by removing common build caches and by deleting unused Xcode SDK directories and simulator data. The script is conservative by default (dry-run mode), reports what it *would* remove and the space reclaimed, and requires an explicit `--apply` flag to perform destructive actions.

This README describes installation, configuration, command-line options, behavior, safety considerations, examples, troubleshooting, and recommended workflows.

---

# Table of contents

1. [Prerequisites](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#prerequisites)
2. [Files &amp; locations](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#files--locations)
3. [Installation](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#installation)
4. [Design &amp; behavior summary](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#design--behavior-summary)
5. [Command-line options (full)](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#command-line-options-full)
6. [Usage examples](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#usage-examples)
7. [What the script cleans (detailed)](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#what-the-script-cleans-detailed)
8. [Xcode SDK deletion policy explained](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#xcode-sdk-deletion-policy-explained)
9. [Safety &amp; recovery](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#safety--recovery)
10. [Logging &amp; output](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#logging--output)
11. [Customizing the script](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#customizing-the-script)
12. [Automation suggestions (optional)](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#automation-suggestions-optional)
13. [Troubleshooting / FAQ](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#troubleshooting--faq)
14. [License](https://chatgpt.com/c/693260a7-a464-8329-ba83-3a3ea2fdfd11#license)

---

# Prerequisites

* macOS with Terminal access (bash-compatible shell).
* `xcode-select` / Xcode installed if you want the Xcode cleanup features.
* `sudo` privileges for removing files inside `/Applications/Xcode.app` or other system locations.
* Optional: `brew`, `docker`, `npm`, `yarn`, `flutter`, `pip` in PATH if you want their respective cleanup tasks to run. The script *will* detect presence and skip steps for missing tools.

---

# Files & locations

* `mac_cleanup.sh` — the cleanup script (single file).
* Default runtime log: `/tmp/mac_cleanup_<timestamp>.log` (script prints the exact logfile path at start). You may override with `--log <path>`.

---

# Installation

1. Save the script as `mac_cleanup.sh` in a directory you control, for example `~/bin/`.
2. Make the script executable:

```bash
chmod +x mac_cleanup.sh
```

3. (Optional) Move it into a global bin directory:

```bash
sudo mv mac_cleanup.sh /usr/local/bin/mac_cleanup.sh
```

4. Confirm it runs (dry-run default):

```bash
./mac_cleanup.sh --help
```

---

# Design & behavior summary

* **Dry-run by default.** The script will *print* the commands it would execute and show sizes for candidate directories, but it will not delete anything unless run with `--apply`.
* **Targets.** You can restrict cleanup to named categories (xcode, node, python, java, flutter, homebrew, docker, custom). `--targets all` (default) expands to all supported categories.
* **Xcode SDK safe policy.** The script keeps the newest `N` SDKs per platform (default `N=1`) and only deletes older SDK directories inside Xcode. You control `N` with `--keep-sdk-count`.
* **Auditability.** The script writes a log and prints every command in dry-run mode. When `--apply` is used, executed commands are also logged.
* **Sudo only when required.** SDK deletion inside `/Applications/Xcode.app` uses `sudo rm -rf` and will prompt for password when necessary.
* **Non-destructive options.** For simulators the script only deletes them when you pass explicit flags that indicate you accept removal: `--remove-unavailable-simulators` or `--remove-all-simulators`.

---

# Command-line options (full)

```
Usage: mac_cleanup.sh [options]

Options:
  --apply                         Actually perform deletions (default is dry-run).
  --targets <comma-list>          What to clean. Default: all.
                                  Values: all,xcode,node,python,java,flutter,homebrew,docker
  --project-root <path>           Target project root for project-specific cleanup (default: current dir).
  --keep-sdk-count <N>            Keep newest N SDKs per Xcode platform (default: 1).
  --remove-unavailable-simulators Delete only unavailable simulators (xcrun simctl delete unavailable).
  --remove-all-simulators         Delete all simulators (xcrun simctl delete all).
  --log <path>                    Path to logfile (default: /tmp/mac_cleanup_<timestamp>.log).
  --help, -h                      Show this help and exit.
```

Notes:

* Multiple targets should be comma-separated, for example: `--targets xcode,node`.
* If you specify `--targets all` or omit `--targets`, the script expands to `xcode,node,python,java,flutter,homebrew,docker`.

---

# Usage examples

1. **Show what would be removed (dry-run, safe):**

```bash
./mac_cleanup.sh
```

2. **Perform a real cleanup for Xcode and Homebrew only, keeping the newest SDK per platform:**

```bash
sudo ./mac_cleanup.sh --apply --targets xcode,homebrew --keep-sdk-count 1
```

3. **Clean node and python caches for a specific project, actually apply deletions:**

```bash
./mac_cleanup.sh --apply --targets node,python --project-root /Users/you/Projects/my-app
```

4. **Inspect Docker disk usage (dry-run) or remove all unused Docker resources (apply):**

```bash
# Dry-run
./mac_cleanup.sh --targets docker

# Apply (destructive)
./mac_cleanup.sh --apply --targets docker
```

5. **Delete only unavailable simulators (safe option):**

```bash
./mac_cleanup.sh --apply --targets xcode --remove-unavailable-simulators
```

---

# What the script cleans (detailed)

The script performs these actions for the selected targets:

## Xcode

* `~/Library/Developer/Xcode/DerivedData/*` — remove build intermediates and caches. (Safe; frees large space)
* `~/Library/Developer/Xcode/Archives/*` — remove archived builds (`.xcarchive`). (Destructive to archives)
* `~/Library/Developer/Xcode/iOS DeviceSupport/*` — remove old DeviceSupport folders installed when devices were connected.
* `~/Library/Developer/CoreSimulator/Caches/*` — remove simulator caches.
* `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/*` and `~/Library/Developer/Xcode/ModuleCache.noindex/*` — clear module caches.
* **Xcode SDKs** under `/Applications/Xcode.app/Contents/Developer/Platforms/*/Developer/SDKs/*.sdk` — deletes older SDK directories according to `--keep-sdk-count`.
* Optional simulator deletion via `xcrun simctl delete unavailable` or `xcrun simctl delete all` (only if you pass corresponding flags).

## Node (project-level)

* `node_modules` in the specified `--project-root`.
* Optionally runs `npm cache verify` (or other `npm`/`yarn` commands) depending on `--apply`.

## Python (project-level)

* All `__pycache__` directories under `--project-root`.
* `pip cache purge` when `--apply` and `pip` present.

## Java

* `~/.gradle/caches/` — delete Gradle caches.
* `~/.m2/repository` — delete Maven repository (destructive; re-download required to rebuild).

## Flutter

* `flutter clean` invoked in `--project-root` (only if `flutter` in PATH).
* `flutter pub cache repair` or `flutter pub cache list` depending on dry-run vs apply.

## Homebrew

* `brew cleanup --prune=all`.
* `~/Library/Caches/Homebrew/*` — clear cached downloads.

## Docker

* `docker system df` (dry-run) or `docker system prune -a --volumes` (apply). **This will remove** unused images, stopped containers, networks, and volumes.

---

# Xcode SDK deletion policy explained

* The script enumerates SDK directories per Xcode platform (for example, `iPhoneOS.platform/Developer/SDKs/` and `MacOSX.platform/Developer/SDKs/`).
* It extracts version numbers from SDK names (e.g., `iPhoneOS16.2.sdk` → `16.2`) and sorts them numerically by version.
* It keeps the newest `N` SDKs per platform (default `N=1`) and  **deletes older SDK directories** .
* **Why this is useful:** Xcode bundles multiple SDKs and older SDKs are rarely needed; removing them reclaims tens of gigabytes in some setups.
* **Risk:** Removing SDKs makes building for those OS versions impossible. To restore them you must reinstall Xcode or recover from backup.

---

# Safety & recovery

**Dry-run is the default.** Always run the script once without `--apply` to inspect candidates and sizes.

**Backups.** Before running with `--apply`:

* Use Time Machine or another backup solution if you keep important archives or custom SDKs.
* If you remove `.xcarchive` bundles which you might later need for distribution or symbolication, back them up.

**Reinstalling Xcode.** If you accidentally remove SDKs or other Xcode internals, reinstall Xcode from the App Store or Apple Developer site to restore them.

**Re-downloadable caches.** Most caches removed by this script (npm, pip, Homebrew packages, Gradle, etc.) are re-downloadable. Be prepared for rebuilds and re-downloads after cleanup.

---

# Logging & output

* The script prints an explicit logfile path at startup. Default path: `/tmp/mac_cleanup_<timestamp>.log`.
* Dry-run mode prints commands it would run and the sizes of candidate directories.
* When `--apply` is used, executed commands are both printed and executed; actions and outcomes are logged.

---

# Customizing the script

* **Change default `KEEP_SDK_COUNT`.** Edit the `KEEP_SDK_COUNT` default in the script or pass `--keep-sdk-count N`.
* **Add/remove targets.** If you want to also clean other caches (e.g., CocoaPods cache, Android SDK), add handlers to `do_project_cleanup` or new functions using the script style.
* **Exclude particular paths.** Modify the script to filter out specific directories from removal by adding path checks before `run_cmd "rm -rf ..."` lines.
* **Non-interactive / CI use.** Use `--apply` in controlled CI systems but ensure you have backups and that deleting caches is acceptable for the environment.

---

# Automation suggestions (optional)

If you want periodic reports (dry-run) emailed to you before manual cleanup:

* Run dry-run via a scheduled `launchd` job or cron job and redirect log to a known path.
* Review logs and only run `--apply` manually (recommended).

**Example launchd idea (NOT included):** run the script weekly in dry-run mode and store logs under `~/Library/Logs/mac_cleanup/`.

---

# Troubleshooting / FAQ

**Q: The script reports “Xcode developer path not found”.**

A: Ensure Xcode or the Command Line Tools is installed and that `xcode-select -p` returns a valid developer directory. Install Xcode from the App Store or run `xcode-select --install`.

**Q: I got `sudo: a password is required` when removing SDKs.**

A: That is expected for destructive deletions inside `/Applications/Xcode.app`. Re-run with `sudo` or run the script from an account that can provide sudo. Example:

```bash
sudo ./mac_cleanup.sh --apply --targets xcode --keep-sdk-count 1
```

**Q: I removed archives and need one back.**

A: Recover from a Time Machine backup or from any offsite archive. If you pushed builds to App Store Connect, you can re-download dSYMs and related artifacts there in some cases.

**Q: Docker deletion removed a volume with data.**

A: If you used `--apply` with the docker target, volumes may be removed. Check `docker volume ls` and `docker ps -a` for remaining artifacts. Recovery is only possible from backups.

**Q: I want to keep more SDKs for a platform.**

A: Use `--keep-sdk-count 2` (or a higher number) to keep the newest 2 SDKs per platform.

**Q: I run this across many projects and need to remove `node_modules` from many places.**

A: Change `--project-root` to a parent directory and run with `--targets node`. The script removes the `node_modules` only in the top-level `--project-root` path. If you need recursive multi-project cleanup, extend the script to find and remove `node_modules` recursively (note: that is riskier and may be slow).

---

# Example workflow (recommended)

1. **Inspect (dry-run):**

```bash
./mac_cleanup.sh
```

2. **Review the logfile printed to stdout** and confirm the candidates and sizes.
3. **Run targeted apply** (restrict targets to what you know you want to remove):

```bash
sudo ./mac_cleanup.sh --apply --targets xcode,homebrew --keep-sdk-count 1
```

4. **Verify free space** :

```bash
df -h /
```

---

# License

This script is provided "as-is" for convenience. Use at your own risk. You are responsible for verifying the cleanup candidates before pressing `--apply`. Consider backing up important data and archives before running destructive options.
