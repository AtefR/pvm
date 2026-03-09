#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PVM_INSTALL_ROOT="$TEST_ROOT/install-root"
export SHELL=/usr/bin/bash

mkdir -p "$HOME"

"$PROJECT_ROOT/bootstrap.sh" >/dev/null

test -x "$PVM_INSTALL_ROOT/bin/pvm"
test -L "$HOME/.local/bin/pvm"
test -L "$HOME/.pvm/shims/php"
grep -Fq 'source ' "$HOME/.bashrc"

printf 'bootstrap tests passed\n'
