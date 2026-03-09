#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PVM_DIR="$HOME/.pvm"
mkdir -p "$HOME"

PVM_BIN="$PROJECT_ROOT/bin/pvm"
TARGET_VERSION=""
UNINSTALLED_VERSION=""
BUILTIN_EXTENSION=""

for candidate in 8.4 8.3 8.2; do
  if "$PVM_BIN" exec "$candidate" php -v >/dev/null 2>&1; then
    TARGET_VERSION="$candidate"
    break
  fi
done

[[ -n "$TARGET_VERSION" ]] || {
  printf 'no installed php version found for extension test\n' >&2
  exit 1
}

while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  if ! "$PVM_BIN" exec "$candidate" php -v >/dev/null 2>&1; then
    UNINSTALLED_VERSION="$candidate"
    break
  fi
done < <("$PVM_BIN" list-remote | awk '{print $1}')

BUILTIN_EXTENSION="$(
  "$PVM_BIN" exec "$TARGET_VERSION" php -n -m |
    tr '[:upper:]' '[:lower:]' |
    grep -Ev '^[[:space:]]*$|^\[' |
    grep -E '^(date|filter|hash|json|libxml|openssl|pcre|random|reflection|session|spl|standard|tokenizer|zlib)$' |
    head -n 1
)"

[[ -n "$BUILTIN_EXTENSION" ]] || {
  printf 'no built-in extension candidate found for PHP %s\n' "$TARGET_VERSION" >&2
  exit 1
}

"$PVM_BIN" ext disable opcache --version "$TARGET_VERSION" >/dev/null
list_output="$("$PVM_BIN" ext list --version "$TARGET_VERSION")"
[[ "$list_output" == *"disabled: opcache"* ]] || {
  printf 'expected disabled opcache in ext list\n%s\n' "$list_output" >&2
  exit 1
}

if "$PVM_BIN" exec "$TARGET_VERSION" php -m | grep -Fxq 'Zend OPcache'; then
  printf 'expected Zend OPcache to be disabled for PHP %s\n' "$TARGET_VERSION" >&2
  exit 1
fi

"$PVM_BIN" ext enable opcache --version "$TARGET_VERSION" >/dev/null
if ! "$PVM_BIN" exec "$TARGET_VERSION" php -m | grep -Fxq 'Zend OPcache'; then
  printf 'expected Zend OPcache to be enabled for PHP %s\n' "$TARGET_VERSION" >&2
  exit 1
fi

if "$PVM_BIN" ext disable "$BUILTIN_EXTENSION" --version "$TARGET_VERSION" >/dev/null 2>&1; then
  printf 'expected built-in %s extension disable to fail for PHP %s\n' "$BUILTIN_EXTENSION" "$TARGET_VERSION" >&2
  exit 1
fi

if ! "$PVM_BIN" exec "$TARGET_VERSION" php -n -m | tr '[:upper:]' '[:lower:]' | grep -Fxq "$BUILTIN_EXTENSION"; then
  printf 'expected built-in %s extension to remain available for PHP %s\n' "$BUILTIN_EXTENSION" "$TARGET_VERSION" >&2
  exit 1
fi

if [[ -n "$UNINSTALLED_VERSION" ]]; then
  if "$PVM_BIN" ext list --version "$UNINSTALLED_VERSION" >/dev/null 2>&1; then
    printf 'expected ext list to fail for uninstalled PHP %s\n' "$UNINSTALLED_VERSION" >&2
    exit 1
  fi

  if "$PVM_BIN" ext disable opcache --version "$UNINSTALLED_VERSION" >/dev/null 2>&1; then
    printf 'expected ext disable to fail for uninstalled PHP %s\n' "$UNINSTALLED_VERSION" >&2
    exit 1
  fi
fi

doctor_output="$("$PVM_BIN" doctor "$TARGET_VERSION")"
[[ "$doctor_output" == *"doctor version: $TARGET_VERSION"* ]] || {
  printf 'doctor output missing target version\n%s\n' "$doctor_output" >&2
  exit 1
}

printf 'extension tests passed\n'
