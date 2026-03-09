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

for candidate in 8.4 8.3 8.2; do
  if "$PVM_BIN" exec "$candidate" php -v >/dev/null 2>&1; then
    TARGET_VERSION="$candidate"
    break
  fi
done

[[ -n "$TARGET_VERSION" ]] || {
  printf 'no installed php version found for shell hook test\n' >&2
  exit 1
}

# shellcheck disable=SC2016
env \
  HOME="$HOME" \
  PVM_DIR="$PVM_DIR" \
  PVM_PROJECT_ROOT="$PROJECT_ROOT" \
  TARGET_VERSION="$TARGET_VERSION" \
  bash -lc '
    source "$PVM_PROJECT_ROOT/share/pvm/init.bash"
    pvm reshim >/dev/null
    pvm use "$TARGET_VERSION" >/dev/null
    [[ "$(command -v php)" == "$PVM_DIR/shims/php" ]]
    [[ "${PVM_VERSION-}" == "$TARGET_VERSION" ]]
    [[ "$(php -r '"'"'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;'"'"')" == "$TARGET_VERSION" ]]
    pvm deactivate >/dev/null
    [[ -z "${PVM_VERSION-}" ]]
  '

if command -v fish >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  env \
    HOME="$HOME" \
    PVM_DIR="$PVM_DIR" \
    PVM_PROJECT_ROOT="$PROJECT_ROOT" \
    TARGET_VERSION="$TARGET_VERSION" \
    fish -c '
      source "$PVM_PROJECT_ROOT/share/pvm/init.fish"
      pvm reshim >/dev/null
      pvm use $TARGET_VERSION >/dev/null
      test (command -v php) = "$PVM_DIR/shims/php"
      test "$PVM_VERSION" = "$TARGET_VERSION"
      test (php -r "echo PHP_MAJOR_VERSION . \".\" . PHP_MINOR_VERSION;") = "$TARGET_VERSION"
      pvm deactivate >/dev/null
      not set -q PVM_VERSION
    '
fi

if command -v zsh >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  env \
    HOME="$HOME" \
    PVM_DIR="$PVM_DIR" \
    PVM_PROJECT_ROOT="$PROJECT_ROOT" \
    TARGET_VERSION="$TARGET_VERSION" \
    zsh -lc '
      source "$PVM_PROJECT_ROOT/share/pvm/init.zsh"
      pvm reshim >/dev/null
      pvm use "$TARGET_VERSION" >/dev/null
      [[ "$(command -v php)" == "$PVM_DIR/shims/php" ]]
      [[ "${PVM_VERSION:-}" == "$TARGET_VERSION" ]]
      [[ "$(php -r '"'"'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;'"'"')" == "$TARGET_VERSION" ]]
      pvm deactivate >/dev/null
      [[ -z "${PVM_VERSION:-}" ]]
    '
fi

printf 'shell hook tests passed\n'
