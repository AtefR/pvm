# shellcheck shell=bash

php_etc_dir_for_version() {
  local version="$1"
  ensure_brew
  printf '%s/etc/php/%s\n' "$HOMEBREW_PREFIX" "$version"
}

stock_scan_dir_for_version() {
  local version="$1"
  printf '%s/conf.d\n' "$(php_etc_dir_for_version "$version")"
}

pvm_php_config_dir_for_version() {
  local version="$1"
  printf '%s/config/php/%s\n' "$PVM_DIR" "$version"
}

enabled_extensions_file_for_version() {
  local version="$1"
  printf '%s/enabled.list\n' "$(pvm_php_config_dir_for_version "$version")"
}

disabled_extensions_file_for_version() {
  local version="$1"
  printf '%s/disabled.list\n' "$(pvm_php_config_dir_for_version "$version")"
}

merged_scan_dir_for_version() {
  local version="$1"
  printf '%s/scan.d\n' "$(pvm_php_config_dir_for_version "$version")"
}

append_unique_line() {
  local file_path="$1"
  local value="$2"

  mkdir -p "$(dirname "$file_path")"
  touch "$file_path"
  grep -Fxq "$value" "$file_path" 2>/dev/null || printf '%s\n' "$value" >>"$file_path"
}

remove_line_from_file() {
  local file_path="$1"
  local value="$2"
  local tmp_file

  [[ -f "$file_path" ]] || return 0
  tmp_file="$(mktemp)"
  grep -Fvx "$value" "$file_path" >"$tmp_file" || true
  mv "$tmp_file" "$file_path"
}

extension_directive_type() {
  case "$(normalize_extension_name "$1")" in
    opcache|xdebug)
      printf 'zend_extension\n'
      ;;
    *)
      printf 'extension\n'
      ;;
  esac
}

extension_shared_path_for_version() {
  local version="$1"
  local extension_name
  local formula
  local prefix
  local php_config_bin
  local extension_dir
  local candidate_path

  extension_name="$(normalize_extension_name "$2")"
  formula="$(resolve_formula "$version")"
  formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"
  prefix="$(formula_prefix "$formula")"
  php_config_bin="$prefix/bin/php-config"
  [[ -x "$php_config_bin" ]] || fail "php-config is not available for PHP $version."
  extension_dir="$("$php_config_bin" --extension-dir)"
  candidate_path="$extension_dir/$extension_name.so"
  if [[ -e "$candidate_path" ]]; then
    printf '%s\n' "$candidate_path"
    return 0
  fi

  candidate_path="$(find "$prefix/lib/php" -maxdepth 2 -type f -name "$extension_name.so" | head -n 1)"
  if [[ -n "$candidate_path" ]]; then
    printf '%s\n' "$candidate_path"
    return 0
  fi

  printf '%s\n' "$extension_dir/$extension_name.so"
}

extension_is_builtin_for_version() {
  local version="$1"
  local extension_name
  local formula
  local prefix

  extension_name="$(normalize_extension_name "$2")"
  formula="$(resolve_formula "$version")"
  formula_installed "$formula" || return 1
  prefix="$(formula_prefix "$formula")"
  [[ -x "$prefix/bin/php" ]] || return 1
  "$prefix/bin/php" -n -m 2>/dev/null |
    tr '[:upper:]' '[:lower:]' |
    grep -Ev '^[[:space:]]*$|^\[' |
    grep -Fxq "$extension_name"
}

file_matches_disabled_extension() {
  local file_path="$1"
  local extension_name
  local basename_no_ext

  extension_name="$(normalize_extension_name "$2")"
  basename_no_ext="$(basename "$file_path" .ini)"
  basename_no_ext="${basename_no_ext#ext-}"
  basename_no_ext="${basename_no_ext#zend-}"
  basename_no_ext="${basename_no_ext#zz-pvm-ext-}"
  basename_no_ext="${basename_no_ext#zz-pvm-zend-}"

  if [[ "$(normalize_extension_name "$basename_no_ext")" == "$extension_name" ]]; then
    return 0
  fi

  awk -v target="$extension_name" '
    /^[[:space:]]*[;#]/ { next }
    /^[[:space:]]*(zend_extension|extension)[[:space:]]*=/ {
      value = $0
      sub(/^[[:space:]]*(zend_extension|extension)[[:space:]]*=[[:space:]]*/, "", value)
      gsub(/"/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      sub(/\.so$/, "", value)
      sub(/^.*\//, "", value)
      if (tolower(value) == target) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file_path"
}

stock_ini_has_extension() {
  local version="$1"
  local extension_name
  local ini_file

  extension_name="$(normalize_extension_name "$2")"
  while IFS= read -r ini_file; do
    [[ -n "$ini_file" ]] || continue
    if file_matches_disabled_extension "$ini_file" "$extension_name"; then
      return 0
    fi
  done < <(find "$(stock_scan_dir_for_version "$version")" -maxdepth 1 -type f -name '*.ini' | sort 2>/dev/null)

  return 1
}

rebuild_scan_dir_for_version() {
  local version="$1"
  local config_dir
  local enabled_file
  local disabled_file
  local stock_dir
  local target_dir
  local tmp_dir
  local ini_file
  local extension_name
  local shared_path
  local directive

  ensure_state_dirs
  config_dir="$(pvm_php_config_dir_for_version "$version")"
  enabled_file="$(enabled_extensions_file_for_version "$version")"
  disabled_file="$(disabled_extensions_file_for_version "$version")"
  stock_dir="$(stock_scan_dir_for_version "$version")"
  target_dir="$(merged_scan_dir_for_version "$version")"

  mkdir -p "$config_dir"
  touch "$enabled_file" "$disabled_file"
  tmp_dir="$(mktemp -d)"

  if [[ -d "$stock_dir" ]]; then
    while IFS= read -r ini_file; do
      [[ -n "$ini_file" ]] || continue
      local skip_ini=0
      while IFS= read -r extension_name; do
        [[ -n "$extension_name" ]] || continue
        if file_matches_disabled_extension "$ini_file" "$extension_name"; then
          skip_ini=1
          break
        fi
      done <"$disabled_file"

      if (( skip_ini )); then
        continue
      fi

      ln -sfn "$ini_file" "$tmp_dir/$(basename "$ini_file")"
    done < <(find "$stock_dir" -maxdepth 1 -type f -name '*.ini' | sort)
  fi

  while IFS= read -r extension_name; do
    [[ -n "$extension_name" ]] || continue
    shared_path="$(extension_shared_path_for_version "$version" "$extension_name")"
    [[ -e "$shared_path" ]] || fail "The shared extension '$extension_name' is not available for PHP $version."
    directive="$(extension_directive_type "$extension_name")"
    cat >"$tmp_dir/zz-pvm-ext-$(normalize_extension_name "$extension_name").ini" <<EOF
[${extension_name}]
${directive}="${shared_path}"
EOF
  done <"$enabled_file"

  rm -rf "$target_dir"
  mkdir -p "$(dirname "$target_dir")"
  mv "$tmp_dir" "$target_dir"
}

configure_php_environment_for_version() {
  local version="$1"
  local etc_dir
  local scan_dir

  etc_dir="$(php_etc_dir_for_version "$version")"
  scan_dir="$(merged_scan_dir_for_version "$version")"
  rebuild_scan_dir_for_version "$version"

  export PHPRC="$etc_dir"
  export PHP_INI_SCAN_DIR="$scan_dir"
}

emit_php_environment_for_version() {
  local version="$1"
  local etc_dir
  local scan_dir

  etc_dir="$(php_etc_dir_for_version "$version")"
  scan_dir="$(merged_scan_dir_for_version "$version")"
  rebuild_scan_dir_for_version "$version"

  case "${PVM_SHELL:-bash}" in
    fish)
      printf "set -gx PHPRC '%s'\n" "$(escape_single_quotes "$etc_dir")"
      printf "set -gx PHP_INI_SCAN_DIR '%s'\n" "$(escape_single_quotes "$scan_dir")"
      ;;
    *)
      printf "export PHPRC='%s'\n" "$(escape_single_quotes "$etc_dir")"
      printf "export PHP_INI_SCAN_DIR='%s'\n" "$(escape_single_quotes "$scan_dir")"
      ;;
  esac
}

inspect_ini_file_for_missing_extensions() {
  local file_path="$1"
  local extension_dir="$2"
  local prefix="$3"
  local line=""
  local value=""
  local target=""
  local candidate=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*[\;\#] ]] && continue
    [[ "$line" =~ ^[[:space:]]*(zend_extension|extension)[[:space:]]*= ]] || continue

    value="${line#*=}"
    value="${value%%[;#]*}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value%\'}"
    value="${value#\'}"
    value="${value%\"}"
    value="${value#\"}"
    [[ -n "$value" ]] || continue

    if [[ "$value" == /* ]]; then
      target="$value"
    else
      target="$value"
      [[ "$target" == *.so ]] || target="$target.so"
      target="$extension_dir/$target"
      if [[ ! -e "$target" ]]; then
        candidate="$(find "$prefix/lib/php" -maxdepth 2 -type f -name "$(basename "$target")" | head -n 1)"
        if [[ -n "$candidate" ]]; then
          target="$candidate"
        fi
      fi
    fi

    [[ -e "$target" ]] || printf '%s -> missing %s\n' "$file_path" "$target"
  done <"$file_path"
}

active_ini_files_for_version() {
  local version="$1"
  local prefix="$2"
  local php_bin="$prefix/bin/php"
  local etc_dir
  local scan_dir

  etc_dir="$(php_etc_dir_for_version "$version")"
  scan_dir="$(merged_scan_dir_for_version "$version")"

  PHPRC="$etc_dir" PHP_INI_SCAN_DIR="$scan_dir" "$php_bin" --ini 2>/dev/null | awk '
    function emit_entry(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == "" || value == "(none)") {
        return
      }
      gsub(/,/, "\n", value)
      print value
    }

    /^Loaded Configuration File:/ {
      value = $0
      sub(/^Loaded Configuration File:[[:space:]]*/, "", value)
      emit_entry(value)
      next
    }

    /^Additional .ini files parsed:/ {
      value = $0
      sub(/^Additional .ini files parsed:[[:space:]]*/, "", value)
      emit_entry(value)
      extra = 1
      next
    }

    /^[[:space:]]+\// && extra {
      emit_entry($0)
      next
    }

    {
      extra = 0
    }
  ' | while IFS= read -r ini_file; do
    [[ -f "$ini_file" ]] || continue
    printf '%s\n' "$ini_file"
  done | sort -u
}

emit_env_activate() {
  local version="$1"
  local formula="${2:-}"
  local prefix="${3:-}"

  if [[ -z "$formula" ]]; then
    formula="$(resolve_formula "$version")"
  fi

  if [[ -z "$prefix" ]]; then
    formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"
    prefix="$(formula_prefix "$formula")"
  fi

  case "${PVM_SHELL:-bash}" in
    fish)
      printf "set -gx PVM_VERSION '%s'\n" "$(escape_single_quotes "$version")"
      printf "set -gx PVM_PHP_ROOT '%s'\n" "$(escape_single_quotes "$prefix")"
      emit_php_environment_for_version "$version"
      ;;
    *)
      printf "export PVM_VERSION='%s'\n" "$(escape_single_quotes "$version")"
      printf "export PVM_PHP_ROOT='%s'\n" "$(escape_single_quotes "$prefix")"
      emit_php_environment_for_version "$version"
      printf 'hash -r 2>/dev/null || true\n'
      ;;
  esac
}

emit_env_deactivate() {
  case "${PVM_SHELL:-bash}" in
    fish)
      printf 'set -e PVM_VERSION\n'
      printf 'set -e PVM_PHP_ROOT\n'
      printf 'set -e PHPRC\n'
      printf 'set -e PHP_INI_SCAN_DIR\n'
      ;;
    *)
      printf 'unset PVM_VERSION\n'
      printf 'unset PVM_PHP_ROOT\n'
      printf 'unset PHPRC\n'
      printf 'unset PHP_INI_SCAN_DIR\n'
      printf 'hash -r 2>/dev/null || true\n'
      ;;
  esac
}
