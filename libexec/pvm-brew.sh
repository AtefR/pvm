# shellcheck shell=bash

find_brew_binary() {
  local candidate

  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

hydrate_brew_environment() {
  local brew_bin
  local brew_dir
  local brew_root

  brew_bin="$(find_brew_binary)" || return 1
  brew_dir="$(dirname "$brew_bin")"
  brew_root="$(cd -P "$brew_dir/.." && pwd)"

  case ":$PATH:" in
    *":$brew_dir:"*)
      ;;
    *)
      PATH="$brew_dir:$PATH"
      export PATH
      ;;
  esac

  export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$brew_root}"
}

prompt_install_brew() {
  local reply

  printf 'Homebrew is required for pvm. Install it now? [Y/n] ' >&2
  if [[ -t 0 ]]; then
    read -r reply || return 1
  elif [[ -r /dev/tty ]]; then
    read -r reply </dev/tty || return 1
  else
    return 1
  fi

  case "${reply:-Y}" in
    y|Y|yes|YES|"")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_homebrew() {
  info "Installing Homebrew using the official installer..."
  command -v curl >/dev/null 2>&1 || fail "curl is required to install Homebrew automatically."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  hydrate_brew_environment || fail "Homebrew was installed, but pvm could not find brew afterwards."
  success "Homebrew is ready."
}

ensure_brew() {
  if hydrate_brew_environment; then
    return 0
  fi

  warn "Homebrew is not installed."
  if ! prompt_install_brew; then
    fail "Install Homebrew from https://brew.sh and rerun pvm."
  fi

  install_homebrew
}

get_latest_minor() {
  local latest

  latest="$(brew info php 2>/dev/null | sed -n '1s/.*stable \([0-9][0-9]*\.[0-9][0-9]*\)\..*/\1/p' | head -n 1)"
  [[ -n "$latest" ]] || fail "Unable to determine the latest Homebrew PHP version."
  printf '%s\n' "$latest"
}

formula_exists() {
  local formula="$1"
  local candidate

  [[ "$formula" == "php" ]] && return 0

  while IFS= read -r candidate; do
    [[ "$candidate" == "$formula" ]] && return 0
  done < <(brew search '/^php(@[0-9]+\.[0-9]+)?$/' 2>/dev/null)

  return 1
}

resolve_formula() {
  local raw_input="${1:-}"
  local normalized
  local latest_minor
  local candidate

  normalized="$(normalize_requested_version "$raw_input")"
  [[ -n "$normalized" ]] || fail "Missing PHP version. Try: pvm install 8.4"

  case "$normalized" in
    latest|stable|php)
      printf 'php\n'
      return 0
      ;;
  esac

  if [[ "$normalized" =~ ^php@[0-9]+\.[0-9]+$ ]]; then
    candidate="$normalized"
    if formula_installed "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  elif [[ "$normalized" =~ ^[0-9]+\.[0-9]+$ ]]; then
    if candidate="$(installed_formula_for_minor "$normalized" 2>/dev/null)"; then
      printf '%s\n' "$candidate"
      return 0
    fi

    latest_minor="$(get_latest_minor)"
    if [[ "$normalized" == "$latest_minor" ]]; then
      printf 'php\n'
      return 0
    fi
    candidate="php@$normalized"
  else
    fail "Unsupported PHP version format: $raw_input"
  fi

  formula_exists "$candidate" || fail "Homebrew does not expose $candidate on this machine."
  printf '%s\n' "$candidate"
}

formula_to_version() {
  local formula="$1"

  if [[ "$formula" == "php" ]]; then
    get_latest_minor
  else
    printf '%s\n' "${formula#php@}"
  fi
}

installed_php_formulae() {
  brew list --formula 2>/dev/null | grep -E '^php(@|$)' || true
}

formula_installed() {
  local prefix
  prefix="$(formula_prefix "$1")" || return 1
  [[ -e "$prefix" ]]
}

formula_prefix() {
  local formula="$1"
  local brew_bin
  local brew_root

  if [[ -n "${HOMEBREW_PREFIX-}" ]]; then
    printf '%s/opt/%s\n' "$HOMEBREW_PREFIX" "$formula"
    return 0
  fi

  brew_bin="$(find_brew_binary)" || return 1
  brew_root="$(cd -P "$(dirname "$brew_bin")/.." && pwd)"
  printf '%s/opt/%s\n' "$brew_root" "$formula"
}

installed_formula_for_minor() {
  local minor="$1"
  local prefix
  local installed_minor

  if formula_installed "php@$minor"; then
    printf 'php@%s\n' "$minor"
    return 0
  fi

  if ! formula_installed "php"; then
    return 1
  fi

  prefix="$(formula_prefix "php")"
  [[ -x "$prefix/bin/php" ]] || return 1
  installed_minor="$("$prefix/bin/php" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"
  [[ "$installed_minor" == "$minor" ]] || return 1
  printf 'php\n'
}

get_global_version() {
  [[ -f "$PVM_DEFAULT_FILE" ]] || return 1
  trim_file_value "$PVM_DEFAULT_FILE"
}

find_local_version_file() {
  local search_dir="${1:-$PWD}"

  while [[ -n "$search_dir" ]]; do
    if [[ -f "$search_dir/.php-version" ]]; then
      printf '%s\n' "$search_dir/.php-version"
      return 0
    fi

    [[ "$search_dir" == "/" ]] && break
    search_dir="$(dirname "$search_dir")"
  done

  return 1
}

get_local_version() {
  local file_path
  file_path="$(find_local_version_file "${1:-$PWD}")" || return 1
  trim_file_value "$file_path"
}

resolve_selected_version() {
  local search_dir="${1:-$PWD}"

  if [[ -n "${PVM_VERSION-}" ]]; then
    printf '%s\n' "$PVM_VERSION"
    return 0
  fi

  if get_local_version "$search_dir" 2>/dev/null; then
    return 0
  fi

  if get_global_version 2>/dev/null; then
    return 0
  fi

  return 1
}

resolve_target_version() {
  local target="${1:-}"
  local formula

  if [[ -z "$target" ]]; then
    target="$(resolve_selected_version "$PWD" 2>/dev/null)" || fail "No PHP version provided and no active/local/global selection was found."
  fi

  formula="$(resolve_formula "$target")"
  formula_to_version "$formula"
}

system_path_without_shims() {
  local old_path="${PATH:-}"
  local segment
  local -a segments=()
  local -a filtered=()
  local joined=""

  IFS=':' read -r -a segments <<<"$old_path"
  for segment in "${segments[@]}"; do
    [[ -n "$segment" ]] || continue
    [[ "$segment" == "$PVM_SHIMS_DIR" ]] && continue
    filtered+=("$segment")
  done

  for segment in "${filtered[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$segment"
    else
      joined="$joined:$segment"
    fi
  done

  printf '%s\n' "$joined"
}

currently_linked_php_formula() {
  local formula
  local candidate
  local selected_path=""
  local linked_php="${HOMEBREW_PREFIX:-}/bin/php"

  [[ -n "${HOMEBREW_PREFIX-}" ]] || return 1
  [[ -x "$linked_php" ]] || return 1

  selected_path="$(readlink -f "$linked_php" 2>/dev/null || true)"
  [[ -n "$selected_path" ]] || return 1

  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    candidate="$(readlink -f "$(formula_prefix "$formula")/bin/php" 2>/dev/null || true)"
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == "$selected_path" ]]; then
      printf '%s\n' "$formula"
      return 0
    fi
  done < <(installed_php_formulae)

  return 1
}

sync_homebrew_php_links() {
  local selected_formula="$1"
  local formula
  local linked_formula=""

  linked_formula="$(currently_linked_php_formula 2>/dev/null || true)"
  if [[ "$linked_formula" == "$selected_formula" ]]; then
    return 0
  fi

  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    [[ "$formula" == "$selected_formula" ]] && continue
    brew unlink "$formula" >/dev/null 2>&1 || true
  done < <(installed_php_formulae)

  brew link --overwrite --force "$selected_formula" >/dev/null 2>&1 ||
    fail "Unable to link $selected_formula through Homebrew."
}

clear_homebrew_php_links() {
  local formula

  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    brew unlink "$formula" >/dev/null 2>&1 || true
  done < <(installed_php_formulae)
}

find_system_tool() {
  local tool_name="$1"
  local cleaned_path

  cleaned_path="$(system_path_without_shims)"
  PATH="$cleaned_path" command -v "$tool_name" 2>/dev/null || true
}

get_resolved_tool_path() {
  local tool_name="$1"
  local search_dir="${2:-$PWD}"
  local version
  local formula
  local prefix

  if ! version="$(resolve_selected_version "$search_dir" 2>/dev/null)"; then
    find_system_tool "$tool_name"
    return 0
  fi

  ensure_brew
  formula="$(resolve_formula "$version")"
  formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"
  prefix="$(formula_prefix "$formula")"

  if [[ -x "$prefix/bin/$tool_name" ]]; then
    printf '%s\n' "$prefix/bin/$tool_name"
    return 0
  fi

  if [[ -x "$prefix/sbin/$tool_name" ]]; then
    printf '%s\n' "$prefix/sbin/$tool_name"
    return 0
  fi

  fail "The active PHP version does not provide '$tool_name'."
}
