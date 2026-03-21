#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PVM_DIR="$HOME/.pvm"
export PVM_USER_BIN_DIR="$HOME/.local/bin"
mkdir -p "$HOME"

PHP_RUNTIME="${PHP_RUNTIME:-}"
for candidate in \
  "${PHP_RUNTIME:-}" \
  "$(command -v php 2>/dev/null || true)" \
  /home/linuxbrew/.linuxbrew/opt/php/bin/php \
  /home/linuxbrew/.linuxbrew/opt/php@8.4/bin/php \
  /home/linuxbrew/.linuxbrew/opt/php@8.3/bin/php \
  /home/linuxbrew/.linuxbrew/opt/php@8.2/bin/php
do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  case "$candidate" in
    */.pvm/shims/*)
      continue
      ;;
  esac
  if "$candidate" -v >/dev/null 2>&1; then
    PHP_RUNTIME="$candidate"
    break
  fi
done
[[ -n "$PHP_RUNTIME" ]] || {
  printf 'no php runtime available for composer test\n' >&2
  exit 1
}

php_runtime_dir="$(dirname "$PHP_RUNTIME")"
export PATH="$php_runtime_dir:$PATH"

INSTALLER_SOURCE="$TEST_ROOT/composer-setup.php"
SIG_SOURCE="$TEST_ROOT/installer.sig"

cat >"$INSTALLER_SOURCE" <<'EOF'
<?php
$installDir = null;
$filename = 'composer';
foreach ($argv as $arg) {
    if (str_starts_with($arg, '--install-dir=')) {
        $installDir = substr($arg, 14);
    }
    if (str_starts_with($arg, '--filename=')) {
        $filename = substr($arg, 11);
    }
}

if ($installDir === null) {
    fwrite(STDERR, "missing install dir\n");
    exit(1);
}

if (!is_dir($installDir)) {
    mkdir($installDir, 0777, true);
}

$target = rtrim($installDir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $filename;
$script = <<<'PHP'
#!/usr/bin/env php
<?php
if (($argv[1] ?? '') === 'self-update') {
    echo "composer-self-update-ok\n";
    exit(0);
}
echo "composer-installed-ok\n";
PHP;
file_put_contents($target, $script);
chmod($target, 0755);
echo "Composer mock installed\n";
EOF

# shellcheck disable=SC2016
"$PHP_RUNTIME" -r 'echo hash_file("sha384", $argv[1]);' "$INSTALLER_SOURCE" >"$SIG_SOURCE"

export PVM_COMPOSER_INSTALLER_URL="file://$INSTALLER_SOURCE"
export PVM_COMPOSER_INSTALLER_SIG_URL="file://$SIG_SOURCE"

PVM_BIN="$PROJECT_ROOT/bin/pvm"

"$PVM_BIN" composer install >/dev/null

test -x "$PVM_DIR/tools/composer/composer"
test -L "$HOME/.local/bin/composer"

composer_path="$("$PVM_BIN" composer which)"
if [[ "$composer_path" != "$PVM_DIR/tools/composer/composer" ]]; then
  printf 'unexpected composer path: %s\n' "$composer_path" >&2
  exit 1
fi

install_output="$("$HOME/.local/bin/composer")"
if [[ "$install_output" != "composer-installed-ok" ]]; then
  printf 'unexpected composer output: %s\n' "$install_output" >&2
  exit 1
fi

update_output="$("$PVM_BIN" composer update-self)"
if [[ "$update_output" != "composer-self-update-ok" ]]; then
  printf 'unexpected composer update output: %s\n' "$update_output" >&2
  exit 1
fi

printf 'composer tests passed\n'
