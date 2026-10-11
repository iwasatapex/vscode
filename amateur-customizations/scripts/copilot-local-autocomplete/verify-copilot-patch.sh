#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${BUNDLE:-/usr/lib/code/extensions/copilot/dist/extension.js}"
STATE_DIR="${STATE_DIR:-$HOME/.local/share/copilot-local-autocomplete/state}"

if [ ! -f "$BUNDLE" ]; then
  echo "Bundle not found: $BUNDLE"
  exit 1
fi

CODE_OSS_VERSION="$(code --version 2>/dev/null | head -n 1 || echo unknown)"
COPILOT_VERSION="$(node -p "require('/usr/lib/code/extensions/copilot/package.json').version" 2>/dev/null || echo unknown)"
CORE_VERSION="$(node -p "require('/usr/lib/code/extensions/copilot/package.json').completionsCoreVersion" 2>/dev/null || echo unknown)"
CURRENT_HASH="$(sha256sum "$BUNDLE" | awk '{print $1}')"
PATCHED_HASH="$(cat "$STATE_DIR/patched-sha256" 2>/dev/null || echo)"
ORIGINAL_HASH="$(cat "$STATE_DIR/original-sha256" 2>/dev/null || echo)"

if [ "$CURRENT_HASH" = "$PATCHED_HASH" ]; then
  STATUS="INSTALLED"
elif [ "$CURRENT_HASH" = "$ORIGINAL_HASH" ]; then
  STATUS="PRISTINE"
else
  STATUS="UNKNOWN"
fi

echo "Copilot Local Autocomplete"
echo "--------------------------"
echo "Code - OSS:             ${CODE_OSS_VERSION}"
echo "Copilot:                ${COPILOT_VERSION}"
echo "Completions Core:       ${CORE_VERSION}"
echo "Bundle:                 ${BUNDLE}"
echo "Patch status:           ${STATUS}"

if grep -q "localAutocompleteEnabled" "$BUNDLE"; then
  echo "Local branch:           FOUND"
else
  echo "Local branch:           MISSING"
fi

if grep -q "this.#e" "$BUNDLE" && grep -q "copilotTokenManager" "$BUNDLE"; then
  echo "Remote branch:          PRESERVED"
else
  echo "Remote branch:          UNKNOWN"
fi

if grep -q "ollamaFetchAndStream" "$BUNDLE"; then
  echo "Token bypass:           VERIFIED"
else
  echo "Token bypass:           MISSING"
fi

echo "Patched SHA256:         ${PATCHED_HASH:-n/a}"
echo "Original SHA256:        ${ORIGINAL_HASH:-n/a}"
