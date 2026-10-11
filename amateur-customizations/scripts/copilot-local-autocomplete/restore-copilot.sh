#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${BUNDLE:-/usr/lib/code/extensions/copilot/dist/extension.js}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/copilot-local-autocomplete/backups}"
STATE_DIR="${STATE_DIR:-$HOME/.local/share/copilot-local-autocomplete/state}"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "No backups directory found."
  exit 1
fi

PATCHED_HASH="$(cat "$STATE_DIR/patched-sha256" 2>/dev/null || echo)"
CURRENT_HASH="$(sha256sum "$BUNDLE" 2>/dev/null | awk '{print $1}' || echo)"

if [ -z "$PATCHED_HASH" ]; then
  echo "No known patched state recorded."
  exit 1
fi

if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" != "$PATCHED_HASH" ]; then
  echo "Current bundle does not match the recorded patched state. Refusing to restore."
  exit 2
fi

LATEST_BACKUP="$(ls -1t "$BACKUP_DIR"/copilot-*-pristine-extension.js 2>/dev/null | head -n 1 || true)"
if [ -z "$LATEST_BACKUP" ]; then
  echo "No pristine backup found."
  exit 3
fi

COPILOT_VERSION="$(node -p "require('/usr/lib/code/extensions/copilot/package.json').version" 2>/dev/null || echo unknown)"
case "$LATEST_BACKUP" in
  *"$COPILOT_VERSION"*) ;;
  *)
    echo "Backup does not match the installed Copilot version; refusing to restore."
    exit 4
    ;;
esac

cp -a "$LATEST_BACKUP" "$BUNDLE"
sha256sum "$BUNDLE" | awk '{print $1}' > "$STATE_DIR/original-sha256"
rm -f "$STATE_DIR/patched-sha256"

printf 'restore patch\n'
printf 'This removes the local branch from the current compatible bundle without downgrading Copilot.\n'
