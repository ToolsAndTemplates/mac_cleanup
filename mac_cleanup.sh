#!/usr/bin/env bash
# mac_cleanup.sh
# Reusable macOS cleanup script: remove build caches and unused Xcode SDKs (dry-run by default).
# Usage: ./mac_cleanup.sh [--apply] [--targets xcode,node,python,java,flutter,homebrew,docker] [--project-root PATH] [--keep-sdk-count N]
# Author: ChatGPT (formal, careful, reusable)
set -euo pipefail
IFS=$'\n\t'

### ====== Configuration / defaults ======
DRY_RUN=true
TARGETS="all"                 # comma-separated: all,xcode,node,python,java,flutter,homebrew,docker,custom
PROJECT_ROOT="$(pwd)"         # where to clean project-specific caches (node_modules, __pycache__, etc.)
KEEP_SDK_COUNT=1              # keep the newest N SDKs per platform
REMOVE_UNAVAILABLE_SIMULATORS=false
REMOVE_ALL_SIMULATORS=false
LOGFILE="/tmp/mac_cleanup_$(date +%Y%m%d_%H%M%S).log"

### ====== Helpers ======
info()  { printf "\n[INFO] %s\n" "$*" | tee -a "$LOGFILE"; }
warn()  { printf "\n[WARN] %s\n" "$*" | tee -a "$LOGFILE" >&2; }
error() { printf "\n[ERROR] %s\n" "$*" | tee -a "$LOGFILE" >&2; exit 1; }

run_cmd() {
  # Executes or prints given command according to DRY_RUN
  if [ "$DRY_RUN" = true ]; then
    printf "DRY-RUN: %s\n" "$*" | tee -a "$LOGFILE"
  else
    printf "RUN: %s\n" "$*" | tee -a "$LOGFILE"
    eval "$@"
  fi
}

du_h() {
  # portable du human-readable for a path (works on mac)
  if [ -e "$1" ]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    echo "0B"
  fi
}

confirm_root_if_needed() {
  # Some operations require sudo (Xcode app area). We will attempt to sudo when needed.
  if [ "$DRY_RUN" = false ]; then
    if [ "$EUID" -ne 0 ]; then
      # we won't force full-run as root; sudo will be used when necessary for specific rm commands.
      true
    fi
  fi
}

### ====== Parse args ======
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) DRY_RUN=false; shift ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --keep-sdk-count) KEEP_SDK_COUNT="$2"; shift 2 ;;
    --remove-unavailable-simulators) REMOVE_UNAVAILABLE_SIMULATORS=true; shift ;;
    --remove-all-simulators) REMOVE_ALL_SIMULATORS=true; shift ;;
    --log) LOGFILE="$2"; shift 2 ;;
    --help|-h) 
      cat <<EOF
Usage: $0 [options]

Options:
  --apply                         Actually perform deletions (default is dry-run).
  --targets <comma-list>          What to clean. Default: all.
                                  Values: all,xcode,node,python,java,flutter,homebrew,docker,custom
  --project-root <path>           Target project root for node/python cleanup (default: current dir).
  --keep-sdk-count <N>            Keep newest N SDKs per Xcode platform (default: 1).
  --remove-unavailable-simulators Delete only unavailable simulators (xcrun simctl delete unavailable).
  --remove-all-simulators         Delete all simulators (xcrun simctl delete all).
  --log <path>                    Path to log file (default in /tmp).
  --help                          Show this help and exit.

Examples:
  # Dry-run for everything:
  $0

  # Real run: remove caches + delete old Xcode SDKs, keeping latest SDK per platform:
  $0 --apply --targets xcode,node,homebrew --keep-sdk-count 1

  # Only target node & python for a specific project:
  $0 --apply --targets node,python --project-root /path/to/project

EOF
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      shift
      ;;
  esac
done

info "Logfile: $LOGFILE"
info "DRY_RUN: $DRY_RUN"
info "Targets: $TARGETS"
info "Project root: $PROJECT_ROOT"
info "SDKs to keep per platform: $KEEP_SDK_COUNT"

confirm_root_if_needed

### ====== Utility: confirm deletion strategy for Xcode SDKs ======
get_xcode_devroot() {
  # Try xcode-select, fallback to /Applications/Xcode.app
  if command -v xcode-select >/dev/null 2>&1; then
    local xroot
    xroot="$(xcode-select -p 2>/dev/null || true)"
    if [ -n "$xroot" ]; then
      # xcode-select path points to .../Contents/Developer
      echo "$xroot"
      return
    fi
  fi
  # fallback
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    echo "/Applications/Xcode.app/Contents/Developer"
    return
  fi
  echo ""   # not found
}

list_installed_xcode_sdks() {
  # prints "platform|sdkdir"
  local XDEV
  XDEV="$(get_xcode_devroot)"
  if [ -z "$XDEV" ]; then
    return 0
  fi
  for platform in "$XDEV"/Platforms/*; do
    [ -d "$platform" ] || continue
    local platform_name
    platform_name="$(basename "$platform")"
    local sdks_dir="$platform/Developer/SDKs"
    if [ -d "$sdks_dir" ]; then
      for sdk in "$sdks_dir"/*.sdk; do
        [ -d "$sdk" ] || continue
        printf "%s|%s\n" "$platform_name" "$sdk"
      done
    fi
  done
}

sdk_version_from_name() {
  # input: iPhoneOS16.2.sdk or MacOSX13.4.sdk -> output: 16.2 or 13.4 (string)
  local name
  name="$(basename "$1")"
  # remove extension
  name="${name%.sdk}"
  # extract trailing digits and dots
  if [[ $name =~ ([0-9]+\.[0-9]+|[0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "0"
  fi
}

### ====== Xcode Cleanup ======
do_xcode_cleanup() {
  info "=== Xcode cleanup ==="

  local XDEV
  XDEV="$(get_xcode_devroot || true)"
  if [ -z "$XDEV" ]; then
    warn "Xcode developer path not found (xcode-select -p failed). Skipping Xcode cleanup."
    return
  fi
  info "Xcode dev root: $XDEV"

  # 1) DerivedData
  local derived="$HOME/Library/Developer/Xcode/DerivedData"
  if [ -d "$derived" ]; then
    info "DerivedData exists: $(du_h "$derived")"
    run_cmd "ls -lah \"$derived\" | sed -n '1,5p'"
    run_cmd "du -sh \"$derived\" || true"
    run_cmd "rm -rf \"$derived\"/*"
  else
    info "DerivedData not present."
  fi

  # 2) Archives
  local archives="$HOME/Library/Developer/Xcode/Archives"
  if [ -d "$archives" ]; then
    info "Archives: $(du_h "$archives")"
    run_cmd "ls -lah \"$archives\" | sed -n '1,5p'"
    run_cmd "rm -rf \"$archives\"/*"
  fi

  # 3) DeviceSupport (old iOS DeviceSupport)
  local ds="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  if [ -d "$ds" ]; then
    info "iOS DeviceSupport: $(du_h "$ds")"
    run_cmd "ls -lah \"$ds\" | sed -n '1,50p'"
    run_cmd "rm -rf \"$ds\"/*"
  fi

  # 4) CoreSimulator Caches
  local cs="$HOME/Library/Developer/CoreSimulator/Caches"
  if [ -d "$cs" ]; then
    info "CoreSimulator Caches: $(du_h "$cs")"
    run_cmd "rm -rf \"$cs\"/*"
  fi

  # 5) Delete simulators (optional flags)
  if [ "$REMOVE_ALL_SIMULATORS" = true ]; then
    info "Deleting all simulators via xcrun simctl delete all"
    run_cmd "xcrun simctl delete all || true"
  elif [ "$REMOVE_UNAVAILABLE_SIMULATORS" = true ]; then
    info "Deleting unavailable simulators via xcrun simctl delete unavailable"
    run_cmd "xcrun simctl delete unavailable || true"
  fi

  # 6) Xcode SDKs - list candidates and delete old ones
  if [ -n "$KEEP_SDK_COUNT" ] && [ "$KEEP_SDK_COUNT" -ge 0 ]; then
    # Build a list by platform
    declare -A seen  # not persistent across functions but used here
    local platform sdk version_line
    # Collect sdks into an array as "platform|sdk|version"
    local sdks=()
    while IFS='|' read -r platform sdk; do
      [ -n "$sdk" ] || continue
      version_line="$(sdk_version_from_name "$sdk")"
      sdks+=("$platform|$sdk|$version_line")
    done < <(list_installed_xcode_sdks)

    if [ ${#sdks[@]} -eq 0 ]; then
      info "No SDK directories found under Xcode. Skipping SDK deletion."
    else
      info "Found ${#sdks[@]} SDK(s). Will keep newest $KEEP_SDK_COUNT per platform."
      # Group by platform and decide which to delete
      declare -A group_map
      for item in "${sdks[@]}"; do
        IFS='|' read -r p s v <<<"$item"
        # Use array-like key: platform||version|sdkpath
        group_map["$p"]+="$v|$s\n"
      done

      for p in "${!group_map[@]}"; do
        info "Platform: $p"
        # read entries into a sortable list (version numeric sort)
        IFS=$'\n' read -r -d '' -a entries < <(printf "%b" "${group_map[$p]}" && printf '\0')
        # create an array of "version<TAB>sdk"
        local arr=()
        for e in "${entries[@]}"; do
          [ -z "$e" ] && continue
          # e is like "16.2|/path/to/iPhoneOS16.2.sdk"
          IFS='|' read -r ver sdkpath <<<"$e"
          arr+=("$ver"$'\t'"$sdkpath")
        done
        # sort by numeric version descending
        IFS=$'\n' sorted=($(printf "%s\n" "${arr[@]}" | sort -r -t $'\t' -k1V || true))
        # keep top KEEP_SDK_COUNT, delete others
        local idx=0
        for sline in "${sorted[@]}"; do
          idx=$((idx+1))
          ver="${sline%%$'\t'*}"
          sdkpath="${sline#*$'\t'}"
          if [ $idx -le "$KEEP_SDK_COUNT" ]; then
            info "Keeping SDK: $sdkpath (version $ver)"
          else
            info "Candidate for removal: $sdkpath (version $ver) size=$(du_h "$sdkpath")"
            # Delete it if not dry-run
            run_cmd "sudo rm -rf \"$sdkpath\""
          fi
        done
      done
    fi
  fi

  # 7) Optional: Xcode ModuleCache directories (safe)
  local mc1="$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"
  local mc2="$HOME/Library/Developer/Xcode/ModuleCache.noindex"
  if [ -d "$mc1" ]; then
    info "ModuleCache1: $(du_h "$mc1")"
    run_cmd "rm -rf \"$mc1\"/*"
  fi
  if [ -d "$mc2" ]; then
    info "ModuleCache2: $(du_h \"$mc2\")"
    run_cmd "rm -rf \"$mc2\"/*"
  fi

  info "Xcode cleanup done."
}

### ====== Project-specific cleanup (node, python, gradle, maven, flutter) ======
do_project_cleanup() {
  info "=== Project cleanup for path: $PROJECT_ROOT ==="
  # Node: remove node_modules and optionally run npm/yarn cache clean
  if [[ "$TARGETS" == *"node"* ]] || [[ "$TARGETS" == "all" ]]; then
    local nm="$PROJECT_ROOT/node_modules"
    if [ -d "$nm" ]; then
      info "node_modules size: $(du_h "$nm")"
      run_cmd "rm -rf \"$nm\""
      if command -v npm >/dev/null 2>&1; then
        info "Running npm cache verify (dry-run/actual depending on mode)"
        run_cmd "npm cache verify || true"
      fi
      if command -v yarn >/dev/null 2>&1; then
        info "Running yarn cache list (no deletion unless apply)"
        if [ "$DRY_RUN" = false ]; then
          run_cmd "yarn cache clean || true"
        else
          run_cmd "yarn cache list || true"
        fi
      fi
    else
      info "No node_modules found at $nm"
    fi
  fi

  # Python: remove __pycache__ directories and pip cache
  if [[ "$TARGETS" == *"python"* ]] || [[ "$TARGETS" == "all" ]]; then
    info "Searching for __pycache__ under $PROJECT_ROOT (this may take a moment)..."
    # find and show sizes
    mapfile -t pyc_dirs < <(find "$PROJECT_ROOT" -type d -name "__pycache__" 2>/dev/null || true)
    if [ ${#pyc_dirs[@]} -gt 0 ]; then
      for d in "${pyc_dirs[@]}"; do
        info "pycache: $d size: $(du_h "$d")"
        run_cmd "rm -rf \"$d\""
      done
    else
      info "No __pycache__ directories found under $PROJECT_ROOT"
    fi
    if command -v pip >/dev/null 2>&1; then
      info "pip cache info: $(du_h "$HOME/Library/Caches/pip")"
      if [ "$DRY_RUN" = false ]; then
        run_cmd "pip cache purge || true"
      fi
    fi
  fi

  # Java/Gradle
  if [[ "$TARGETS" == *"java"* ]] || [[ "$TARGETS" == "all" ]]; then
    if [ -d "$HOME/.gradle/caches" ]; then
      info "Gradle caches size: $(du_h "$HOME/.gradle/caches")"
      run_cmd "rm -rf \"$HOME/.gradle/caches\""
    fi
    if [ -d "$HOME/.m2/repository" ]; then
      info "Maven repo size: $(du_h "$HOME/.m2/repository")"
      run_cmd "rm -rf \"$HOME/.m2/repository\""
    fi
  fi

  # Flutter
  if [[ "$TARGETS" == *"flutter"* ]] || [[ "$TARGETS" == "all" ]]; then
    if command -v flutter >/dev/null 2>&1; then
      info "Running 'flutter clean' in project root (if flutter project)"
      run_cmd "cd \"$PROJECT_ROOT\" && flutter clean || true"
      if [ "$DRY_RUN" = false ]; then
        run_cmd "flutter pub cache repair || true"
      else
        run_cmd "flutter pub cache list || true"
      fi
    else
      info "flutter not installed / not on PATH"
    fi
  fi
}

### ====== Homebrew, Docker cleanup ======
do_homebrew_cleanup() {
  if [[ "$TARGETS" == *"homebrew"* ]] || [[ "$TARGETS" == "all" ]]; then
    if command -v brew >/dev/null 2>&1; then
      info "Homebrew cleanup: brew cleanup --prune=all"
      run_cmd "brew cleanup --prune=all || true"
      info "Homebrew caches: $(du_h "$HOME/Library/Caches/Homebrew")"
      run_cmd "rm -rf \"$HOME/Library/Caches/Homebrew\"/* || true"
    else
      info "brew not found: skipping Homebrew cleanup"
    fi
  fi
}

do_docker_cleanup() {
  if [[ "$TARGETS" == *"docker"* ]] || [[ "$TARGETS" == "all" ]]; then
    if command -v docker >/dev/null 2>&1; then
      info "Docker system prune (images/containers/volumes)"
      # Be very careful: this deletes all unused images/containers/volumes
      if [ "$DRY_RUN" = true ]; then
        run_cmd "docker system df || true"
        run_cmd "echo 'DRY-RUN: docker system prune -a --volumes (would be executed with --apply)'"
      else
        run_cmd "docker system prune -a --volumes -f || true"
      fi
    else
      info "docker not found: skipping Docker cleanup"
    fi
  fi
}

### ====== Main flow ======
main() {
  info "Starting mac cleanup script"

  # Expand targets
  if [ "$TARGETS" = "all" ] || [[ "$TARGETS" == *"all"* ]]; then
    TARGETS="xcode,node,python,java,flutter,homebrew,docker"
  fi

  # Xcode cleanup if requested
  if [[ "$TARGETS" == *"xcode"* ]]; then
    do_xcode_cleanup
  fi

  # Project cleanup (node, python, etc.)
  if [[ "$TARGETS" == *"node"* ]] || [[ "$TARGETS" == *"python"* ]] || [[ "$TARGETS" == *"java"* ]] || [[ "$TARGETS" == *"flutter"* ]]; then
    do_project_cleanup
  fi

  # Homebrew
  if [[ "$TARGETS" == *"homebrew"* ]]; then
    do_homebrew_cleanup
  fi

  # Docker
  if [[ "$TARGETS" == *"docker"* ]]; then
    do_docker_cleanup
  fi

  info "Completed selected cleanup tasks."
  info "If you ran in dry-run mode, re-run with --apply to actually remove files."
  info "Log saved to: $LOGFILE"
}

main "$@"