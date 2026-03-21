#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done

PROJECT_ROOT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
TARGET_BIN_DIR="$HOME/.local/bin"
TARGET_BIN="$TARGET_BIN_DIR/pvm"
PVM_DIR="$HOME/.pvm"
SHELL_NAME="${SHELL##*/}"
RC_FILE="$HOME/.bashrc"

mkdir -p "$TARGET_BIN_DIR"
ln -sfn "$PROJECT_ROOT/bin/pvm" "$TARGET_BIN"
chmod +x "$PROJECT_ROOT/bin/pvm" "$PROJECT_ROOT/libexec/pvm-shim"
PVM_DIR="$PVM_DIR" "$PROJECT_ROOT/bin/pvm" reshim >/dev/null 2>&1

case "$SHELL_NAME" in
  bash)
    RC_FILE="$HOME/.bashrc"
    ;;
  zsh)
    RC_FILE="$HOME/.zshrc"
    ;;
  fish)
    RC_FILE="$HOME/.config/fish/config.fish"
    ;;
  *)
    RC_FILE="$HOME/.bashrc"
    ;;
esac

mkdir -p "$(dirname "$RC_FILE")"
touch "$RC_FILE"

while IFS= read -r init_line; do
  [[ -n "$init_line" ]] || continue
  if ! grep -Fqx "$init_line" "$RC_FILE"; then
    printf '\n%s\n' "$init_line" >>"$RC_FILE"
  fi
done < <("$PROJECT_ROOT/bin/pvm" init "$SHELL_NAME")

cat <<EOF
pvm has been installed.

Binary:
  $TARGET_BIN

Shell config:
  $RC_FILE

Shims:
  \$HOME/.pvm/shims

Next step:
  source "$RC_FILE"
EOF
