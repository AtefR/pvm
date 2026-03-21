# shellcheck shell=bash

ensure_curl() {
  command -v curl >/dev/null 2>&1 || fail "curl is required for this command."
}

resolve_php_runtime() {
  local php_path
  php_path="$(get_resolved_tool_path php "$PWD")"
  [[ -n "$php_path" ]] || fail "No PHP runtime is available. Install PHP with pvm first."
  printf '%s\n' "$php_path"
}

ensure_composer_installed() {
  [[ -x "$PVM_COMPOSER_BIN" ]] || fail "Composer is not installed yet. Run: pvm composer install"
}

download_composer_installer() {
  local installer_path="$1"
  local sig_path="$2"

  ensure_curl
  curl -fsSL "$PVM_COMPOSER_INSTALLER_URL" -o "$installer_path"
  curl -fsSL "$PVM_COMPOSER_INSTALLER_SIG_URL" -o "$sig_path"
}

verify_composer_installer() {
  local php_bin="$1"
  local installer_path="$2"
  local sig_path="$3"
  local expected
  local actual

  expected="$(tr -d '\n\r' <"$sig_path")"
  # shellcheck disable=SC2016
  actual="$("$php_bin" -r 'echo hash_file("sha384", $argv[1]);' "$installer_path")"
  [[ -n "$expected" ]] || fail "Composer installer signature is empty."
  [[ "$expected" == "$actual" ]] || fail "Composer installer checksum verification failed."
}

link_composer_binary() {
  mkdir -p "$PVM_USER_BIN_DIR"
  ln -sfn "$PVM_COMPOSER_BIN" "$PVM_USER_COMPOSER_LINK"
}
