# shellcheck shell=bash

print_stderr() {
  local color_code="$1"
  shift

  if (( PVM_COLOR )); then
    printf '\033[%sm%s\033[0m\n' "$color_code" "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

info() {
  print_stderr "1;34" "==> $*"
}

success() {
  print_stderr "1;32" "==> $*"
}

warn() {
  print_stderr "1;33" "warning: $*"
}

fail() {
  print_stderr "1;31" "error: $*"
  exit 1
}

lowercase() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'
}

ensure_state_dirs() {
  mkdir -p "$PVM_DIR" "$PVM_SHIMS_DIR" "$PVM_TOOLS_DIR"
}

trim_file_value() {
  awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit }' "$1"
}

normalize_requested_version() {
  lowercase "$1"
}

normalize_extension_name() {
  lowercase "$1"
}

escape_single_quotes() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

assert_safe_user_context() {
  local command_name="${1:-help}"

  case "$command_name" in
    help|--help|-h|version|--version|-v)
      return 0
      ;;
  esac

  if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER-}" ]]; then
    fail "Do not run pvm with sudo or as root. Use your normal user account so pvm state in \$HOME stays writable."
  fi
}
