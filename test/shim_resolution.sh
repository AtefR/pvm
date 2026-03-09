#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PVM_DIR="$HOME/.pvm"
unset HOMEBREW_PREFIX
mkdir -p "$HOME"

MOCK_ROOT="$TEST_ROOT/mockbrew"
MOCK_BIN="$MOCK_ROOT/bin"
STATE_DIR="$MOCK_ROOT/state"
SYSTEM_BIN="$TEST_ROOT/system-bin"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$SYSTEM_BIN"

cat >"$MOCK_BIN/brew" <<EOF
#!/usr/bin/env bash
set -euo pipefail

MOCK_ROOT='$MOCK_ROOT'
STATE_DIR='$STATE_DIR'

latest_version() {
  printf '8.5.3\n'
}

formula_minor() {
  case "\$1" in
    php)
      printf '8.5\n'
      ;;
    php@*)
      printf '%s\n' "\${1#php@}"
      ;;
    *)
      exit 1
      ;;
  esac
}

create_tool() {
  local formula="\$1"
  local tool_path="\$2"
  mkdir -p "\$(dirname "\$tool_path")"
  cat >"\$tool_path" <<TOOL
#!/usr/bin/env bash
printf '%s\\n' 'mock-\$formula-\$(basename "\$tool_path")'
TOOL
  chmod +x "\$tool_path"
}

case "\${1:-}" in
  shellenv)
    printf "export HOMEBREW_PREFIX='%s'\\n" "\$MOCK_ROOT"
    printf 'export PATH="%s:$PATH"\\n' '$MOCK_BIN'
    ;;
  search)
    printf 'php\\nphp@8.4\\nphp@8.3\\n'
    ;;
  info)
    printf '==> php: stable %s (bottled), HEAD\\n' "\$(latest_version)"
    ;;
  list)
    shift
    if [[ "\${1:-}" == "--versions" ]]; then
      formula="\${2:?missing formula}"
      if [[ -f "\$STATE_DIR/\$formula.installed" ]]; then
        printf '%s %s\\n' "\$formula" "\$(cat "\$STATE_DIR/\$formula.installed")"
        exit 0
      fi
      exit 1
    fi
    if [[ "\${1:-}" == "--formula" ]]; then
      for marker in "\$STATE_DIR"/*.installed; do
        [[ -e "\$marker" ]] || exit 0
        basename "\$marker" .installed
      done | sort
      exit 0
    fi
    ;;
  --prefix)
    formula="\${2:?missing formula}"
    printf '%s/opt/%s\\n' "\$MOCK_ROOT" "\$formula"
    ;;
  install)
    formula="\${2:?missing formula}"
    minor="\$(formula_minor "\$formula")"
    prefix="\$MOCK_ROOT/opt/\$formula"
    mkdir -p "\$prefix/bin" "\$prefix/sbin"
    printf '%s\\n' "\$minor" >"\$STATE_DIR/\$formula.installed"
    create_tool "\$formula" "\$prefix/bin/php"
    create_tool "\$formula" "\$prefix/bin/phpize"
    create_tool "\$formula" "\$prefix/bin/php-config"
    create_tool "\$formula" "\$prefix/bin/phpdbg"
    create_tool "\$formula" "\$prefix/bin/php-cgi"
    create_tool "\$formula" "\$prefix/bin/pecl"
    create_tool "\$formula" "\$prefix/bin/phar"
    create_tool "\$formula" "\$prefix/bin/phar.phar"
    create_tool "\$formula" "\$prefix/sbin/php-fpm"
    if [[ "\$formula" != "php@8.3" ]]; then
      create_tool "\$formula" "\$prefix/bin/pear"
    fi
    ;;
  uninstall)
    formula="\${2:?missing formula}"
    rm -f "\$STATE_DIR/\$formula.installed"
    rm -rf "\$MOCK_ROOT/opt/\$formula"
    ;;
  --version)
    printf 'Homebrew mock\\n'
    ;;
  *)
    printf 'Unsupported brew invocation: %s\\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/brew"

cat >"$SYSTEM_BIN/php" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'system-php'
EOF
chmod +x "$SYSTEM_BIN/php"

export PATH="$MOCK_BIN:$SYSTEM_BIN:/usr/bin:/bin"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'assertion failed: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'assertion failed: %s\nmissing: %s\nactual: %s\n' "$message" "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_fails() {
  local expected_substring="$1"
  shift
  local output

  if output="$("$@" 2>&1)"; then
    printf 'assertion failed: command unexpectedly succeeded: %s\n' "$*" >&2
    exit 1
  fi

  assert_contains "$output" "$expected_substring" "failure output should mention expected text"
}

PVM_BIN="$PROJECT_ROOT/bin/pvm"

"$PVM_BIN" install 8.4 >/dev/null
"$PVM_BIN" install 8.3 >/dev/null
"$PVM_BIN" reshim >/dev/null 2>&1

test -L "$PVM_DIR/shims/php"

"$PVM_BIN" global 8.4 >/dev/null
global_php_path="$("$PVM_BIN" which php)"
assert_eq "$global_php_path" "$MOCK_ROOT/opt/php@8.4/bin/php" "global version should resolve through shim"

PROJECT_DIR="$TEST_ROOT/project"
mkdir -p "$PROJECT_DIR"
printf '8.3\n' >"$PROJECT_DIR/.php-version"
local_php_path="$(cd "$PROJECT_DIR" && "$PVM_BIN" which php)"
assert_eq "$local_php_path" "$MOCK_ROOT/opt/php@8.3/bin/php" "local version should override global"

shell_override_path="$(cd "$PROJECT_DIR" && PVM_VERSION=8.4 "$PVM_BIN" which php)"
assert_eq "$shell_override_path" "$MOCK_ROOT/opt/php@8.4/bin/php" "shell override should beat local version"

rm -f "$PROJECT_DIR/.php-version"
"$PVM_BIN" global --unset >/dev/null
system_php_path="$("$PVM_BIN" which php)"
assert_eq "$system_php_path" "$SYSTEM_BIN/php" "shim should fall back to system php when no pvm version is selected"

printf '8.3\n' >"$PROJECT_DIR/.php-version"
assert_fails "does not provide 'pear'" bash -lc "cd '$PROJECT_DIR' && PATH='$PVM_DIR/shims:$PATH' '$PVM_BIN' which pear"

printf 'shim resolution tests passed\n'
