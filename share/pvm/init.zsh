if [[ -z "${PVM_PROJECT_ROOT:-}" ]]; then
  PVM_PROJECT_ROOT="${${(%):-%N}:A:h:h}"
  export PVM_PROJECT_ROOT
fi

export PVM_DIR="${PVM_DIR:-$HOME/.pvm}"
export PVM_SHIMS_DIR="$PVM_DIR/shims"
export PVM_SHELL_LOADED=zsh

case ":$PATH:" in
  *":$PVM_SHIMS_DIR:"*)
    ;;
  *)
    PATH="$PVM_SHIMS_DIR:$PATH"
    export PATH
    ;;
esac

function __pvm_bin() {
  if [[ -n "${PVM_PROJECT_ROOT:-}" && -x "$PVM_PROJECT_ROOT/bin/pvm" ]]; then
    print -r -- "$PVM_PROJECT_ROOT/bin/pvm"
    return 0
  fi

  if [[ -x "$HOME/.local/bin/pvm" ]]; then
    print -r -- "$HOME/.local/bin/pvm"
    return 0
  fi

  return 1
}

function __pvm_apply_env() {
  local pvm_bin
  local output

  pvm_bin="$(__pvm_bin)" || return 1
  output="$(PVM_EVAL=1 PVM_SHELL=zsh "$pvm_bin" env "$@")" || return $?
  [[ -n "$output" ]] && eval "$output"
}

function __pvm_install_wrapper() {
  local pvm_bin
  local arg
  local target=""
  local use_after=0
  local status
  local -a install_args

  pvm_bin="$(__pvm_bin)" || return 1
  for arg in "$@"; do
    if [[ "$arg" == "--use" ]]; then
      use_after=1
      continue
    fi

    install_args+=("$arg")
    if [[ "$arg" != -* && "$arg" != "install" && -z "$target" ]]; then
      target="$arg"
    fi
  done

  "$pvm_bin" "${install_args[@]}"
  status=$?
  [[ $status -eq 0 ]] || return $status

  if (( use_after )); then
    __pvm_apply_env use "$target"
  fi
}

function pvm() {
  local command_name="${1:-}"
  local pvm_bin

  case "$command_name" in
    use|shell)
      shift
      __pvm_apply_env use "$@"
      ;;
    deactivate)
      __pvm_apply_env deactivate
      ;;
    install)
      __pvm_install_wrapper "$@"
      ;;
    *)
      pvm_bin="$(__pvm_bin)" || return 1
      "$pvm_bin" "$@"
      ;;
  esac
}

rehash 2>/dev/null || true
