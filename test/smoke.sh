#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$PROJECT_ROOT/bin/pvm" version
"$PROJECT_ROOT/bin/pvm" init bash >/dev/null
"$PROJECT_ROOT/bin/pvm" init zsh >/dev/null
"$PROJECT_ROOT/bin/pvm" init fish >/dev/null
"$PROJECT_ROOT/bin/pvm" reshim >/dev/null
"$PROJECT_ROOT/bin/pvm" list-remote >/dev/null
"$PROJECT_ROOT/bin/pvm" list >/dev/null
"$PROJECT_ROOT/bin/pvm" doctor >/dev/null
"$PROJECT_ROOT/test/shim_resolution.sh" >/dev/null
"$PROJECT_ROOT/test/composer.sh" >/dev/null
"$PROJECT_ROOT/test/sudo_guard.sh" >/dev/null
"$PROJECT_ROOT/test/extensions.sh" >/dev/null
"$PROJECT_ROOT/test/shell_hooks.sh" >/dev/null
"$PROJECT_ROOT/test/bootstrap.sh" >/dev/null
