#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$(SUDO_USER=tester "$PROJECT_ROOT/bin/pvm" list 2>&1 || true)"

if [[ "$output" != *"Do not run pvm with sudo or as root"* ]]; then
  printf 'expected sudo guard message, got:\n%s\n' "$output" >&2
  exit 1
fi

printf 'sudo guard tests passed\n'
