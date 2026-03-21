# shellcheck shell=bash

tool_names() {
  cat <<'EOF'
php
phpize
php-config
phpdbg
php-cgi
php-fpm
pear
pecl
phar
phar.phar
EOF
}

cmd_reshim() {
  local shim_name
  local shim_target="$PVM_PROJECT_ROOT/libexec/pvm-shim"

  ensure_state_dirs
  mkdir -p "$PVM_PROJECT_ROOT/libexec"
  [[ -x "$shim_target" ]] || fail "Missing shim dispatcher at $shim_target"

  while IFS= read -r shim_name; do
    [[ -n "$shim_name" ]] || continue
    ln -sfn "$shim_target" "$PVM_SHIMS_DIR/$shim_name"
  done < <(tool_names)

  success "Refreshed pvm shims in $PVM_SHIMS_DIR."
}

print_help() {
  cat <<EOF
pvm $PVM_VERSION_STRING

Homebrew-backed PHP version manager with shim-based multi-shell support.

Usage:
  pvm install <version> [--use]
  pvm uninstall <version>
  pvm use [version]
  pvm deactivate
  pvm global <version>
  pvm global --unset
  pvm local <version>
  pvm local --unset
  pvm list
  pvm list-remote
  pvm current
  pvm which <tool>
  pvm ext <list|enable|disable> [extension] [--version <version>]
  pvm composer <install|update-self|which>
  pvm exec <version> <command...>
  pvm reshim
  pvm doctor
  pvm init <bash|zsh|fish>
  pvm help
EOF
}

cmd_install() {
  local target=""
  local use_after=0
  local formula
  local version

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --use)
        use_after=1
        ;;
      *)
        [[ -z "$target" ]] || fail "Unexpected argument for install: $1"
        target="$1"
        ;;
    esac
    shift
  done

  ensure_brew
  ensure_state_dirs
  formula="$(resolve_formula "$target")"
  version="$(formula_to_version "$formula")"

  if formula_installed "$formula"; then
    success "PHP $version is already installed."
  else
    info "Installing PHP $version with Homebrew. Brew will stream its own progress below."
    brew install "$formula"
    success "Installed PHP $version."
  fi

  cmd_reshim >/dev/null 2>&1

  if (( use_after )); then
    if [[ -n "${PVM_EVAL-}" ]]; then
      emit_env_activate "$version"
    else
      warn "PHP $version is installed. Load the pvm shell hook and run 'pvm use $version' to activate it in your shell."
    fi
  fi
}

cmd_uninstall() {
  local target="${1:-}"
  local formula
  local version

  ensure_brew
  ensure_state_dirs
  formula="$(resolve_formula "$target")"
  version="$(formula_to_version "$formula")"

  if ! formula_installed "$formula"; then
    warn "PHP $version is not installed."
    return 0
  fi

  if [[ "$(get_global_version 2>/dev/null || true)" == "$version" ]]; then
    rm -f "$PVM_DEFAULT_FILE"
    warn "Removed PHP $version as the global default because it is being uninstalled."
  fi

  info "Uninstalling PHP $version with Homebrew."
  brew uninstall "$formula"
  success "Uninstalled PHP $version."
  cmd_reshim >/dev/null 2>&1

  if [[ -n "${PVM_EVAL-}" && "${PVM_VERSION-}" == "$version" ]]; then
    emit_env_deactivate
  fi
}

cmd_use() {
  local target="${1:-}"
  local formula
  local version
  local prefix

  [[ -n "${PVM_EVAL-}" ]] || fail "pvm use must run through the shell hook. Add 'pvm init <shell>' to your shell config."

  if [[ -z "$target" ]]; then
    target="$(resolve_selected_version "$PWD" 2>/dev/null)" || fail "No version provided and no .php-version or global default was found."
  fi

  ensure_brew
  formula="$(resolve_formula "$target")"
  version="$(formula_to_version "$formula")"
  formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"
  prefix="$(formula_prefix "$formula")"
  emit_env_activate "$version" "$formula" "$prefix"
}

cmd_deactivate() {
  [[ -n "${PVM_EVAL-}" ]] || fail "pvm deactivate must run through the shell hook."
  emit_env_deactivate
}

cmd_global() {
  local target="${1:-}"
  local formula
  local version

  ensure_state_dirs

  if [[ "$target" == "--unset" ]]; then
    rm -f "$PVM_DEFAULT_FILE"
    ensure_brew
    clear_homebrew_php_links
    success "Cleared the global PHP default and removed Homebrew PHP links."
    return 0
  fi

  ensure_brew
  formula="$(resolve_formula "$target")"
  version="$(formula_to_version "$formula")"
  formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"
  printf '%s\n' "$version" >"$PVM_DEFAULT_FILE"
  sync_homebrew_php_links "$formula"
  success "Set PHP $version as the global default and linked it for external tools."
}

cmd_local() {
  local target="${1:-}"
  local formula
  local version

  if [[ "$target" == "--unset" ]]; then
    rm -f "$PWD/.php-version"
    success "Removed $PWD/.php-version."
    return 0
  fi

  ensure_brew
  formula="$(resolve_formula "$target")"
  version="$(formula_to_version "$formula")"
  printf '%s\n' "$version" >"$PWD/.php-version"
  success "Wrote PHP $version to $PWD/.php-version."
}

cmd_list() {
  local installed_formulae
  local formula
  local version
  local resolved=""
  local global_version=""
  local local_version=""
  local tags=()

  ensure_brew
  installed_formulae="$(installed_php_formulae)"
  resolved="$(resolve_selected_version "$PWD" 2>/dev/null || true)"
  global_version="$(get_global_version 2>/dev/null || true)"
  local_version="$(get_local_version "$PWD" 2>/dev/null || true)"

  [[ -n "$installed_formulae" ]] || {
    printf 'No Homebrew PHP versions are installed.\n'
    return 0
  }

  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    version="$(formula_to_version "$formula")"
    tags=()
    [[ "$version" == "$resolved" ]] && tags+=("selected")
    [[ "$version" == "$global_version" ]] && tags+=("global")
    [[ "$version" == "$local_version" ]] && tags+=("local")
    [[ "$formula" == "php" ]] && tags+=("latest")

    if [[ ${#tags[@]} -gt 0 ]]; then
      printf '%-6s %s\n' "$version" "(${tags[*]})"
    else
      printf '%s\n' "$version"
    fi
  done <<<"$installed_formulae"
}

cmd_list_remote() {
  local latest_minor
  local formula
  local seen_latest=0

  ensure_brew
  latest_minor="$(get_latest_minor)"

  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    if [[ "$formula" == "php" ]]; then
      printf '%-6s %s\n' "$latest_minor" "(latest)"
      seen_latest=1
    else
      printf '%s\n' "${formula#php@}"
    fi
  done < <(brew search '/^php(@[0-9]+\.[0-9]+)?$/' 2>/dev/null)

  if (( ! seen_latest )); then
    printf '%-6s %s\n' "$latest_minor" "(latest)"
  fi
}

cmd_current() {
  local version=""
  local system_php=""

  if [[ -n "${PVM_VERSION-}" ]]; then
    printf '%s (shell)\n' "$PVM_VERSION"
    return 0
  fi

  if version="$(get_local_version "$PWD" 2>/dev/null)"; then
    printf '%s (local)\n' "$version"
    return 0
  fi

  if version="$(get_global_version 2>/dev/null)"; then
    printf '%s (global)\n' "$version"
    return 0
  fi

  system_php="$(find_system_tool php)"
  if [[ -n "$system_php" ]]; then
    printf 'system (%s)\n' "$system_php"
    return 0
  fi

  printf 'none\n'
}

cmd_which() {
  local tool_name="${1:-php}"
  local tool_path

  tool_path="$(get_resolved_tool_path "$tool_name" "$PWD")"
  [[ -n "$tool_path" ]] || fail "No active PHP version and no system '$tool_name' found."
  printf '%s\n' "$tool_path"
}

cmd_ext() {
  local subcommand="${1:-}"
  local extension_name=""
  local version_arg=""
  local version=""
  local formula
  local list_file
  local shared_path
  local -a managed_values=()
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        shift
        [[ $# -gt 0 ]] || fail "Missing value for --version."
        version_arg="$1"
        ;;
      *)
        [[ -z "$extension_name" ]] || fail "Unexpected argument for pvm ext: $1"
        extension_name="$1"
        ;;
    esac
    shift
  done

  version="$(resolve_target_version "$version_arg")"
  ensure_brew
  ensure_state_dirs
  formula="$(resolve_formula "$version")"
  version="$(formula_to_version "$formula")"
  formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"

  case "$subcommand" in
    list)
      rebuild_scan_dir_for_version "$version"
      printf 'PHP %s\n' "$version"
      printf 'managed scan dir: %s\n' "$(merged_scan_dir_for_version "$version")"

      for list_file in "$(enabled_extensions_file_for_version "$version")" "$(disabled_extensions_file_for_version "$version")"; do
        managed_values=()
        if [[ -f "$list_file" ]]; then
          while IFS= read -r extension_name; do
            [[ -n "$extension_name" ]] || continue
            managed_values+=("$extension_name")
          done <"$list_file"
        fi

        if [[ "$list_file" == "$(enabled_extensions_file_for_version "$version")" ]]; then
          printf 'enabled: '
        else
          printf 'disabled: '
        fi

        if [[ ${#managed_values[@]} -eq 0 ]]; then
          printf 'none\n'
        else
          printf '%s\n' "${managed_values[*]}"
        fi
      done
      ;;
    enable)
      [[ -n "$extension_name" ]] || fail "Missing extension name. Try: pvm ext enable xdebug --version 8.4"
      extension_name="$(normalize_extension_name "$extension_name")"
      shared_path="$(extension_shared_path_for_version "$version" "$extension_name" 2>/dev/null || true)"
      if [[ -z "$shared_path" || ! -e "$shared_path" ]]; then
        if extension_is_builtin_for_version "$version" "$extension_name"; then
          fail "Extension '$extension_name' is built into PHP $version and does not need to be enabled."
        fi
        fail "The shared extension '$extension_name' is not available for PHP $version."
      fi
      remove_line_from_file "$(disabled_extensions_file_for_version "$version")" "$extension_name"
      if stock_ini_has_extension "$version" "$extension_name"; then
        remove_line_from_file "$(enabled_extensions_file_for_version "$version")" "$extension_name"
      else
        append_unique_line "$(enabled_extensions_file_for_version "$version")" "$extension_name"
      fi
      rebuild_scan_dir_for_version "$version"
      success "Enabled extension '$extension_name' for PHP $version."
      ;;
    disable)
      [[ -n "$extension_name" ]] || fail "Missing extension name. Try: pvm ext disable opcache --version 8.4"
      extension_name="$(normalize_extension_name "$extension_name")"
      if extension_is_builtin_for_version "$version" "$extension_name"; then
        fail "Extension '$extension_name' is built into PHP $version and cannot be disabled through ini files."
      fi
      remove_line_from_file "$(enabled_extensions_file_for_version "$version")" "$extension_name"
      append_unique_line "$(disabled_extensions_file_for_version "$version")" "$extension_name"
      rebuild_scan_dir_for_version "$version"
      success "Disabled extension '$extension_name' for PHP $version."
      ;;
    *)
      fail "Unsupported ext subcommand: ${subcommand:-missing}"
      ;;
  esac
}

cmd_composer() {
  local subcommand="${1:-}"
  local php_bin
  local installer_path
  local sig_path

  shift || true

  case "$subcommand" in
    install)
      ensure_state_dirs
      php_bin="$(resolve_php_runtime)"
      info "Installing Composer with the official installer."
      (
        local tmp_dir

        tmp_dir="$(mktemp -d)"
        trap 'rm -rf "$tmp_dir"' EXIT
        installer_path="$tmp_dir/composer-setup.php"
        sig_path="$tmp_dir/installer.sig"
        download_composer_installer "$installer_path" "$sig_path"
        verify_composer_installer "$php_bin" "$installer_path" "$sig_path"
        mkdir -p "$PVM_COMPOSER_DIR"
        "$php_bin" "$installer_path" --install-dir="$PVM_COMPOSER_DIR" --filename=composer
      )
      chmod +x "$PVM_COMPOSER_BIN"
      link_composer_binary
      success "Composer is installed at $PVM_COMPOSER_BIN."
      ;;
    update-self)
      php_bin="$(resolve_php_runtime)"
      ensure_composer_installed
      "$php_bin" "$PVM_COMPOSER_BIN" self-update "$@"
      ;;
    which)
      ensure_composer_installed
      printf '%s\n' "$PVM_COMPOSER_BIN"
      ;;
    "")
      fail "Missing composer subcommand. Use: pvm composer install"
      ;;
    *)
      fail "Unsupported composer subcommand: $subcommand"
      ;;
  esac
}

cmd_exec() {
  local target="${1:-}"
  local formula
  local version
  local prefix
  shift || true

  [[ $# -gt 0 ]] || fail "Missing command for pvm exec."
  ensure_brew
  formula="$(resolve_formula "$target")"
  version="$(formula_to_version "$formula")"
  formula_installed "$formula" || fail "PHP $version is not installed. Run: pvm install $version"
  prefix="$(formula_prefix "$formula")"
  configure_php_environment_for_version "$version"
  PATH="$prefix/bin:$prefix/sbin:$(system_path_without_shims)" exec "$@"
}

cmd_exec_tool() {
  local tool_name="${1:-}"
  local tool_path
  local version=""
  shift || true

  [[ -n "$tool_name" ]] || fail "Missing tool name for internal exec-tool."
  version="$(resolve_selected_version "$PWD" 2>/dev/null || true)"
  tool_path="$(get_resolved_tool_path "$tool_name" "$PWD")"
  [[ -n "$tool_path" ]] || fail "No active PHP version and no system '$tool_name' found."
  if [[ -n "$version" ]]; then
    configure_php_environment_for_version "$version"
  fi
  exec "$tool_path" "$@"
}

cmd_doctor() {
  local version_arg="${1:-}"
  local version=""
  local formula=""
  local prefix=""
  local php_config_bin=""
  local extension_dir=""
  local stock_dir=""
  local managed_dir=""
  local ini_file=""
  local issues=0
  local issue_line=""
  local php_shim_target=""

  printf 'pvm version: %s\n' "$PVM_VERSION_STRING"
  printf 'project root: %s\n' "$PVM_PROJECT_ROOT"
  printf 'state dir: %s\n' "$PVM_DIR"
  printf 'shims dir: %s\n' "$PVM_SHIMS_DIR"
  printf 'brew: %s\n' "$(find_brew_binary || printf 'missing')"
  printf 'shell hook: %s\n' "${PVM_SHELL_LOADED:-not detected}"
  printf 'selected version: %s\n' "$(resolve_selected_version "$PWD" 2>/dev/null || printf 'none')"
  if ! php_shim_target="$(get_resolved_tool_path php "$PWD" 2>/dev/null)"; then
    php_shim_target=""
  fi
  printf 'php shim target: %s\n' "${php_shim_target:-none}"

  if ! version="$(resolve_target_version "$version_arg" 2>/dev/null)"; then
    version=""
  fi
  if [[ -z "$version" ]]; then
    return 0
  fi

  ensure_brew
  formula="$(resolve_formula "$version")"
  formula_installed "$formula" || {
    printf 'doctor version: %s (not installed)\n' "$version"
    return 0
  }

  prefix="$(formula_prefix "$formula")"
  php_config_bin="$prefix/bin/php-config"
  if [[ -x "$php_config_bin" ]]; then
    extension_dir="$("$php_config_bin" --extension-dir)"
  fi
  stock_dir="$(stock_scan_dir_for_version "$version")"
  managed_dir="$(merged_scan_dir_for_version "$version")"
  rebuild_scan_dir_for_version "$version"

  printf 'doctor version: %s\n' "$version"
  printf 'php prefix: %s\n' "$prefix"
  printf 'php etc dir: %s\n' "$(php_etc_dir_for_version "$version")"
  printf 'stock scan dir: %s\n' "$stock_dir"
  printf 'managed scan dir: %s\n' "$managed_dir"
  printf 'extension dir: %s\n' "${extension_dir:-unknown}"

  if [[ -n "$extension_dir" ]]; then
    while IFS= read -r ini_file; do
      [[ -n "$ini_file" ]] || continue
      while IFS= read -r issue_line; do
        [[ -n "$issue_line" ]] || continue
        printf 'warning: broken ini entry: %s\n' "$issue_line"
        issues=1
      done < <(inspect_ini_file_for_missing_extensions "$ini_file" "$extension_dir" "$prefix")
    done < <(active_ini_files_for_version "$version" "$prefix")
  fi

  if (( ! issues )); then
    printf 'doctor result: no broken extension directives detected\n'
  fi
}

cmd_init() {
  case "${1:-}" in
    bash)
      printf "export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
      printf 'export PVM_PROJECT_ROOT=%q\n' "$PVM_PROJECT_ROOT"
      printf 'source %q\n' "$PVM_PROJECT_ROOT/share/pvm/init.bash"
      ;;
    zsh)
      printf "export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
      printf 'export PVM_PROJECT_ROOT=%q\n' "$PVM_PROJECT_ROOT"
      printf 'source %q\n' "$PVM_PROJECT_ROOT/share/pvm/init.zsh"
      ;;
    fish)
      printf 'fish_add_path -m ~/.local/bin\n'
      printf "set -gx PVM_PROJECT_ROOT '%s'\n" "$(escape_single_quotes "$PVM_PROJECT_ROOT")"
      printf "source '%s'\n" "$(escape_single_quotes "$PVM_PROJECT_ROOT/share/pvm/init.fish")"
      ;;
    *)
      fail "Unsupported shell. Use one of: bash, zsh, fish"
      ;;
  esac
}

cmd_env() {
  local action="${1:-}"
  shift || true

  case "$action" in
    use|shell)
      cmd_use "$@"
      ;;
    deactivate)
      cmd_deactivate
      ;;
    *)
      fail "Unsupported env action: $action"
      ;;
  esac
}

cmd_version() {
  printf '%s\n' "$PVM_VERSION_STRING"
}

main() {
  local command_name="${1:-help}"
  shift || true

  case "$command_name" in
    install)
      cmd_install "$@"
      ;;
    uninstall|remove)
      cmd_uninstall "$@"
      ;;
    use|shell)
      cmd_use "$@"
      ;;
    deactivate)
      cmd_deactivate
      ;;
    global)
      cmd_global "$@"
      ;;
    local)
      cmd_local "$@"
      ;;
    list|ls)
      cmd_list
      ;;
    list-remote|ls-remote)
      cmd_list_remote
      ;;
    current)
      cmd_current
      ;;
    which)
      cmd_which "$@"
      ;;
    ext)
      cmd_ext "$@"
      ;;
    composer)
      cmd_composer "$@"
      ;;
    exec)
      cmd_exec "$@"
      ;;
    exec-tool)
      cmd_exec_tool "$@"
      ;;
    reshim)
      cmd_reshim
      ;;
    doctor)
      cmd_doctor "$@"
      ;;
    init)
      cmd_init "$@"
      ;;
    env)
      cmd_env "$@"
      ;;
    version|--version|-v)
      cmd_version
      ;;
    help|--help|-h)
      print_help
      ;;
    *)
      fail "Unknown command: $command_name"
      ;;
  esac
}
