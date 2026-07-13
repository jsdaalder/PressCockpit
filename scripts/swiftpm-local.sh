#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCRATCH_PATH="/private/tmp/jwh-swiftpm"
FRESH_BUILD=0
LOG_DIR=""

quote_args() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done
  printf '%s' "${quoted[*]}"
}

usage() {
  cat <<'EOF'
Usage: scripts/swiftpm-local.sh [--scratch-path PATH] [--fresh] <swift-subcommand> [args...]

Examples:
  scripts/swiftpm-local.sh run JournalismWorkflowHub
  scripts/swiftpm-local.sh --fresh run JournalismWorkflowHub
  scripts/swiftpm-local.sh test --filter AppStoreNavigationTests
  scripts/swiftpm-local.sh build

This wrapper keeps SwiftPM scratch data outside the synced workspace so
SQLite build database access stays reliable on Google Drive and similar paths.
It also saves a timestamped transcript of each invocation under the scratch
directory so transient build progress can be inspected afterward.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scratch-path)
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --fresh)
      FRESH_BUILD=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

if [[ "$FRESH_BUILD" -eq 1 ]]; then
  rm -rf "$SCRATCH_PATH"
fi

mkdir -p "$SCRATCH_PATH"
LOG_DIR="$SCRATCH_PATH/logs"
mkdir -p "$LOG_DIR"

export CLANG_MODULE_CACHE_PATH="$SCRATCH_PATH/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_PATH/swiftpm-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

SWIFT_SUBCOMMAND="$1"
shift

SWIFT_ARGS=("$SWIFT_SUBCOMMAND" "--scratch-path" "$SCRATCH_PATH" "$@")
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/swiftpm-${SWIFT_SUBCOMMAND}-${TIMESTAMP}.log"

RTK_BIN="${HOME}/.local/bin/rtk"
LAUNCHER=()
if [[ -x "$RTK_BIN" ]]; then
  LAUNCHER=("$RTK_BIN" swift)
elif command -v rtk >/dev/null 2>&1; then
  LAUNCHER=("$(command -v rtk)" swift)
else
  LAUNCHER=(swift)
fi

{
  echo "[swiftpm-local] root: $ROOT_DIR"
  echo "[swiftpm-local] subcommand: $SWIFT_SUBCOMMAND"
  echo "[swiftpm-local] scratch: $SCRATCH_PATH"
  echo "[swiftpm-local] fresh: $FRESH_BUILD"
  echo "[swiftpm-local] clang cache: $CLANG_MODULE_CACHE_PATH"
  echo "[swiftpm-local] swiftpm cache: $SWIFTPM_MODULECACHE_OVERRIDE"
  echo "[swiftpm-local] log: $LOG_FILE"
  echo "[swiftpm-local] command: $(quote_args "${LAUNCHER[@]}" "${SWIFT_ARGS[@]}")"
  "${LAUNCHER[@]}" "${SWIFT_ARGS[@]}"
} 2>&1 | tee "$LOG_FILE"
exit "${PIPESTATUS[0]}"
