#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done

BOOTSTRAP_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
PVM_INSTALL_ROOT="${PVM_INSTALL_ROOT:-$HOME/.local/share/pvm}"
PVM_REF="${PVM_REF:-main}"
PVM_REPO_URL="${PVM_REPO_URL:-https://github.com/AtefR/pvm.git}"
LOCAL_SOURCE_DIR=""

if [[ -x "$BOOTSTRAP_DIR/install.sh" && -x "$BOOTSTRAP_DIR/bin/pvm" ]]; then
  LOCAL_SOURCE_DIR="$BOOTSTRAP_DIR"
fi

copy_local_checkout() {
  local source_dir="$1"
  local target_dir="$2"
  local tmp_dir

  tmp_dir="$(mktemp -d)"
  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  tar -C "$source_dir" --exclude=.git -cf - . | tar -C "$target_dir" -xf -
  rm -rf "$tmp_dir"
}

clone_or_update_repo() {
  local repo_url="$1"
  local ref="$2"
  local target_dir="$3"

  if [[ -d "$target_dir/.git" ]]; then
    git -C "$target_dir" fetch --tags origin
    git -C "$target_dir" checkout "$ref"
    git -C "$target_dir" pull --ff-only origin "$ref"
  else
    rm -rf "$target_dir"
    git clone "$repo_url" "$target_dir"
    git -C "$target_dir" checkout "$ref"
  fi
}

if [[ -n "$LOCAL_SOURCE_DIR" && "${PVM_BOOTSTRAP_MODE:-local}" != "git" ]]; then
  mkdir -p "$(dirname "$PVM_INSTALL_ROOT")"
  copy_local_checkout "$LOCAL_SOURCE_DIR" "$PVM_INSTALL_ROOT"
else
  command -v git >/dev/null 2>&1 || {
    printf 'error: git is required for bootstrap installs.\n' >&2
    exit 1
  }

  if [[ -z "$PVM_REPO_URL" && -d "$PVM_INSTALL_ROOT/.git" ]]; then
    PVM_REPO_URL="$(git -C "$PVM_INSTALL_ROOT" remote get-url origin)"
  fi

  if [[ -z "$PVM_REPO_URL" ]]; then
    printf 'error: set PVM_REPO_URL or run bootstrap.sh from a pvm checkout.\n' >&2
    exit 1
  fi

  mkdir -p "$(dirname "$PVM_INSTALL_ROOT")"
  clone_or_update_repo "$PVM_REPO_URL" "$PVM_REF" "$PVM_INSTALL_ROOT"
fi

cd "$PVM_INSTALL_ROOT"
exec "$PVM_INSTALL_ROOT/install.sh"
