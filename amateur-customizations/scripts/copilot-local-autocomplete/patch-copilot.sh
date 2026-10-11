#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${BUNDLE:-/usr/lib/code/extensions/copilot/dist/extension.js}"
STATE_DIR="${STATE_DIR:-$HOME/.local/share/copilot-local-autocomplete/state}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/copilot-local-autocomplete/backups}"
LOG_DIR="${LOG_DIR:-$HOME/.local/share/copilot-local-autocomplete/logs}"
PATCH_VERSION="local-autocomplete-v3"

mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR"

if [ ! -f "$BUNDLE" ]; then
  echo "Bundle not found: $BUNDLE"
  exit 1
fi

if [ ! -r "$BUNDLE" ] || [ ! -w "$BUNDLE" ]; then
  echo "Bundle is not writable by the current user: $BUNDLE"
  echo "Patch not applied; user-level patcher requires writable target or an explicit env override."
  exit 2
fi

CODE_OSS_VERSION="$(code --version 2>/dev/null | head -n 1 || echo unknown)"
COPILOT_VERSION="$(node -p "require('/usr/lib/code/extensions/copilot/package.json').version" 2>/dev/null || echo unknown)"
CORE_VERSION="$(node -p "require('/usr/lib/code/extensions/copilot/package.json').completionsCoreVersion" 2>/dev/null || echo unknown)"

CURRENT_HASH="$(sha256sum "$BUNDLE" | awk '{print $1}')"
PATCHED_HASH="$(cat "$STATE_DIR/patched-sha256" 2>/dev/null || echo)"
ORIGINAL_HASH="$(cat "$STATE_DIR/original-sha256" 2>/dev/null || echo)"

# --- MIGRATE_V1_TO_PRISTINE (one-time, hash-guarded, root only) ---
# If the live bundle is exactly the known V1-patched hash, restore it from the
# root-owned pristine backup so the pristine->v3 logic below can apply. This is
# a no-op unless BOTH hashes match exactly; the pristine backup is never altered.
if [ "$(id -u)" = "0" ] && [ "$CURRENT_HASH" = "7ba76b2622291d3f0cc23be63393c686150df5a7ae1e1d53f833adc8f9bbd43d" ]; then
  PRISTINE_SRC="$(ls -1t "$BACKUP_DIR"/copilot-*-pristine-extension.js 2>/dev/null | head -n 1 || true)"
  if [ -n "$PRISTINE_SRC" ]; then
    PRISTINE_SHA="$(sha256sum "$PRISTINE_SRC" | awk '{print $1}')"
    if [ "$PRISTINE_SHA" = "9405f019c19a55c17d1a7069175aa595b880f9b631d74f30a153c3068913a3cf" ]; then
      echo "migrating known V1-patched bundle -> pristine"
      cp -a "$PRISTINE_SRC" "$BUNDLE"
      CURRENT_HASH="$(sha256sum "$BUNDLE" | awk '{print $1}')"
      rm -f "$STATE_DIR/patched-sha256" "$STATE_DIR/current-sha256"
      printf '%s\n' "$CURRENT_HASH" > "$STATE_DIR/original-sha256"
    else
      echo "pristine backup hash mismatch; refusing migration" >&2
      exit 9
    fi
  fi
fi

if [ -n "$PATCHED_HASH" ] && [ "$CURRENT_HASH" = "$PATCHED_HASH" ]; then
  echo "already patched"
  exit 0
fi

if [ -n "$ORIGINAL_HASH" ] && [ "$CURRENT_HASH" = "$ORIGINAL_HASH" ]; then
  echo "pristine bundle; safe to patch"
else
  echo "UNKNOWN VERSION / UNKNOWN STATE"
  echo "Current bundle hash: $CURRENT_HASH"
  echo "Manual inspection required."
  exit 3
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
cp -a "$BUNDLE" "$BACKUP_DIR/copilot-${COPILOT_VERSION}-${TS}-pristine-extension.js"

TMP="${BUNDLE}.localpatch.tmp"
cp -a "$BUNDLE" "$TMP"

node - "$TMP" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
let js = fs.readFileSync(path, 'utf8');

const required = [
  /fetchAndStreamCompletions/,
  /this\.#e/,
  /copilotTokenManager/,
  /getToken\(/
];

for (const re of required) {
  if (!re.test(js)) {
    console.error('Copilot version changed and the known patch pattern no longer matches.');
    process.exit(1);
  }
}

const topInsert = Buffer.from("CmZ1bmN0aW9uIGxvY2FsQXV0b2NvbXBsZXRlRW5hYmxlZCgpe3RyeXtjb25zdCB2c2NvZGU9cmVxdWlyZSgidnNjb2RlIik7Y29uc3QgY29uZj12c2NvZGUud29ya3NwYWNlLmdldENvbmZpZ3VyYXRpb24oImdpdGh1Yi5jb3BpbG90LmxvY2FsQXV0b2NvbXBsZXRlIik7cmV0dXJuICEhY29uZi5nZXQoImVuYWJsZWQiLGZhbHNlKTt9Y2F0Y2h7cmV0dXJuIGZhbHNlO319CmFzeW5jIGZ1bmN0aW9uIG9sbGFtYUZldGNoQW5kU3RyZWFtKG4scixvLGEpe3RyeXtjb25zdCB2c2NvZGU9cmVxdWlyZSgidnNjb2RlIik7Y29uc3QgY2ZnPXZzY29kZS53b3Jrc3BhY2UuZ2V0Q29uZmlndXJhdGlvbigiZ2l0aHViLmNvcGlsb3QubG9jYWxBdXRvY29tcGxldGUiKTtjb25zdCBiYXNlPShjZmcuZ2V0KCJlbmRwb2ludCIsImh0dHA6Ly8xMjcuMC4wLjE6MTE0MzUiKXx8Imh0dHA6Ly8xMjcuMC4wLjE6MTE0MzUiKS5yZXBsYWNlKC9cLyQvLCIiKTtjb25zdCBtb2RlbD1jZmcuZ2V0KCJtb2RlbCIsImdyYW5pdGU0LjE6M2ItcTZfSyIpO2NvbnN0IG51bVByZWRpY3Q9TnVtYmVyKGNmZy5nZXQoIm51bVByZWRpY3QiLDEyOCl8fDEyOCk7Y29uc3Qga2VlcEFsaXZlUmF3PWNmZy5nZXQoImtlZXBBbGl2ZSIsIjYwMCIpO2NvbnN0IGtlZXBBbGl2ZT0odHlwZW9mIGtlZXBBbGl2ZVJhdz09PSJudW1iZXIiKT9rZWVwQWxpdmVSYXc6KC9eXGQrJC8udGVzdChTdHJpbmcoa2VlcEFsaXZlUmF3fHwiIikudHJpbSgpKT9OdW1iZXIoU3RyaW5nKGtlZXBBbGl2ZVJhdykudHJpbSgpKTpTdHJpbmcoa2VlcEFsaXZlUmF3fHwiNjAwIikpO2NvbnN0IHByZWZpeD1TdHJpbmcobiYmbi5wcm9tcHQmJm4ucHJvbXB0LnByZWZpeCE9bnVsbD9uLnByb21wdC5wcmVmaXg6IiIpO2NvbnN0IHN1ZmZpeD1TdHJpbmcobiYmbi5wcm9tcHQmJm4ucHJvbXB0LnN1ZmZpeCE9bnVsbD9uLnByb21wdC5zdWZmaXg6IiIpO2NvbnN0IGNvbnRyb2xsZXI9bmV3IEFib3J0Q29udHJvbGxlcigpO2NvbnN0IGFib3J0TGlzdGVuZXI9YSYmYS5vbkNhbmNlbGxhdGlvblJlcXVlc3RlZD9hLm9uQ2FuY2VsbGF0aW9uUmVxdWVzdGVkKGZ1bmN0aW9uKCl7Y29udHJvbGxlci5hYm9ydCgpO30pOm51bGw7Y29uc3QgdXJsPWJhc2UrIi9hcGkvZ2VuZXJhdGUiO2NvbnN0IGJvZHk9e21vZGVsOm1vZGVsLHByb21wdDpwcmVmaXgsc3VmZml4OnN1ZmZpeCxzdHJlYW06dHJ1ZSxvcHRpb25zOntudW1fcHJlZGljdDpudW1QcmVkaWN0LHRlbXBlcmF0dXJlOjAuMn0sa2VlcF9hbGl2ZTprZWVwQWxpdmUscmF3OmZhbHNlfTtsZXQgcmVzO3RyeXtyZXM9YXdhaXQgZmV0Y2godXJsLHttZXRob2Q6IlBPU1QiLGhlYWRlcnM6eyJDb250ZW50LVR5cGUiOiJhcHBsaWNhdGlvbi9qc29uIn0sYm9keTpKU09OLnN0cmluZ2lmeShib2R5KSxzaWduYWw6Y29udHJvbGxlci5zaWduYWx9KTt9Y2F0Y2goZSl7aWYoZSYmZS5uYW1lPT09IkFib3J0RXJyb3IiKXJldHVybnt0eXBlOiJjYW5jZWxlZCIscmVhc29uOiJhYm9ydGVkIGJlZm9yZSByZXNwb25zZSJ9O3Rocm93IGU7fWlmKCFyZXMub2spe3Rocm93IG5ldyBFcnJvcigiT2xsYW1hIHJlcXVlc3QgZmFpbGVkOiAiK3Jlcy5zdGF0dXMrIiAiK3Jlcy5zdGF0dXNUZXh0KTt9aWYoIXJlcy5ib2R5fHx0eXBlb2YgcmVzLmJvZHkuZ2V0UmVhZGVyIT09ImZ1bmN0aW9uIil7dGhyb3cgbmV3IEVycm9yKCJPbGxhbWEgc3RyZWFtaW5nIGJvZHkgdW5hdmFpbGFibGUiKTt9Y29uc3QgcmVhZGVyPXJlcy5ib2R5LmdldFJlYWRlcigpO2NvbnN0IGRlY29kZXI9bmV3IFRleHREZWNvZGVyKCk7bGV0IGJ1Zj0iIjtsZXQgdGV4dD0iIjtsZXQgZG9uZVNlZW49ZmFsc2U7dHJ5e2Zvcig7Oyl7bGV0IHJkO3RyeXtyZD1hd2FpdCByZWFkZXIucmVhZCgpO31jYXRjaChlKXtpZihlJiZlLm5hbWU9PT0iQWJvcnRFcnJvciIpcmV0dXJue3R5cGU6ImNhbmNlbGVkIixyZWFzb246ImFib3J0ZWQgZHVyaW5nIHN0cmVhbSJ9O3Rocm93IGU7fWlmKHJkLmRvbmUpYnJlYWs7YnVmKz1kZWNvZGVyLmRlY29kZShyZC52YWx1ZSx7c3RyZWFtOnRydWV9KTtsZXQgbmw7d2hpbGUoKG5sPWJ1Zi5pbmRleE9mKCJcbiIpKT49MCl7Y29uc3QgbGluZT1idWYuc2xpY2UoMCxubCkudHJpbSgpO2J1Zj1idWYuc2xpY2UobmwrMSk7aWYoIWxpbmUpY29udGludWU7bGV0IGNodW5rO3RyeXtjaHVuaz1KU09OLnBhcnNlKGxpbmUpO31jYXRjaChpZ24pe2NvbnRpbnVlO31pZihjaHVuayYmdHlwZW9mIGNodW5rLnJlc3BvbnNlPT09InN0cmluZyImJmNodW5rLnJlc3BvbnNlKXRleHQrPWNodW5rLnJlc3BvbnNlO2lmKGNodW5rJiZjaHVuay5kb25lKXtkb25lU2Vlbj10cnVlO3RyeXthd2FpdCByZWFkZXIuY2FuY2VsKCk7fWNhdGNoKGlnbjIpe31icmVhazt9fWlmKGRvbmVTZWVuKWJyZWFrO2lmKGEmJmEuaXNDYW5jZWxsYXRpb25SZXF1ZXN0ZWQpe3RyeXthd2FpdCByZWFkZXIuY2FuY2VsKCk7fWNhdGNoKGlnbjMpe31yZXR1cm57dHlwZToiY2FuY2VsZWQiLHJlYXNvbjoiY2FuY2VsbGVkIGR1cmluZyBzdHJlYW0ifTt9fWNvbnN0IHRhaWw9KGJ1ZitkZWNvZGVyLmRlY29kZSgpKS50cmltKCk7aWYodGFpbCYmIWRvbmVTZWVuKXt0cnl7Y29uc3QgbGFzdENodW5rPUpTT04ucGFyc2UodGFpbCk7aWYobGFzdENodW5rJiZ0eXBlb2YgbGFzdENodW5rLnJlc3BvbnNlPT09InN0cmluZyIpdGV4dCs9bGFzdENodW5rLnJlc3BvbnNlO31jYXRjaChpZ240KXt9fX1maW5hbGx5e3RyeXtyZWFkZXIucmVsZWFzZUxvY2soKTt9Y2F0Y2goaWduNSl7fWlmKGFib3J0TGlzdGVuZXImJmFib3J0TGlzdGVuZXIuZGlzcG9zZSlhYm9ydExpc3RlbmVyLmRpc3Bvc2UoKTt9Y29uc3QgcmVxdWVzdElkPShnbG9iYWxUaGlzLmNyeXB0byYmZ2xvYmFsVGhpcy5jcnlwdG8ucmFuZG9tVVVJRCk/Z2xvYmFsVGhpcy5jcnlwdG8ucmFuZG9tVVVJRCgpOiJvbGxhbWEtIitEYXRlLm5vdygpKyItIitNYXRoLnJhbmRvbSgpLnRvU3RyaW5nKDE2KS5zbGljZSgyKTtyZXR1cm57dHlwZToic3VjY2VzcyIsY2hvaWNlczpbe2Nob2ljZUluZGV4OjAsY29tcGxldGlvblRleHQ6dGV4dCxyZXF1ZXN0SWQ6cmVxdWVzdElkLGZpbmlzaFJlYXNvbjoic3RvcCIsdG9rZW5zOlt0ZXh0XSxudW1Ub2tlbnM6MSxibG9ja0ZpbmlzaGVkOnRydWUsdGVsZW1ldHJ5RGF0YTp7fSxjbGllbnRDb21wbGV0aW9uSWQ6cmVxdWVzdElkLG1lYW5Mb2dQcm9iOnZvaWQgMCxtZWFuQWx0ZXJuYXRpdmVMb2dQcm9iOnZvaWQgMCxjb3BpbG90QW5ub3RhdGlvbnM6W119XSxnZXRQcm9jZXNzaW5nVGltZTpmdW5jdGlvbigpe3JldHVybiAwO319O31jYXRjaChlcnIpe2lmKGVyciYmZXJyLm5hbWU9PT0iQWJvcnRFcnJvciIpcmV0dXJue3R5cGU6ImNhbmNlbGVkIixyZWFzb246ImFib3J0ZWQifTtjb25zdCByZXF1ZXN0SWQ9KGdsb2JhbFRoaXMuY3J5cHRvJiZnbG9iYWxUaGlzLmNyeXB0by5yYW5kb21VVUlEKT9nbG9iYWxUaGlzLmNyeXB0by5yYW5kb21VVUlEKCk6Im9sbGFtYS1mYWlsZWQtIitEYXRlLm5vdygpKyItIitNYXRoLnJhbmRvbSgpLnRvU3RyaW5nKDE2KS5zbGljZSgyKTtyZXR1cm57dHlwZToiZmFpbGVkIixyZWFzb246ZXJyJiZlcnIubWVzc2FnZT9lcnIubWVzc2FnZTpTdHJpbmcoZXJyKSxyZXF1ZXN0SWQ6cmVxdWVzdElkfTt9fQo=", "base64").toString("utf8");

if (js.includes('function localAutocompleteEnabled()') || js.includes('async function ollamaFetchAndStream')) {
  console.log('already patched');
  process.exit(0);
}

const marker = /if\(this\.#e\)return\{type:"canceled",reason:this\.#e\};/;
if (!marker.test(js)) {
  console.error('Target block not found; refusing to patch.');
  process.exit(1);
}

const replacement = `if(this.#e)return{type:"canceled",reason:this.#e};if(localAutocompleteEnabled()){return await ollamaFetchAndStream(n,r,o,a);}`;
js = js.replace(marker, replacement);
const useStrictIndex = js.indexOf('"use strict";');
if (useStrictIndex >= 0) {
  let insertAt = js.indexOf(';', useStrictIndex) + 1;
  js = js.slice(0, insertAt) + topInsert + js.slice(insertAt);
}

fs.writeFileSync(path, js);
NODE

if [ ! -f "$TMP" ]; then
  echo "Patch temp file not created; aborting."
  exit 4
fi

node - "$TMP" <<'NODE'
const fs = require('fs');
const js = fs.readFileSync(process.argv[2], 'utf8');
if (!/function localAutocompleteEnabled\(\)/.test(js)) throw new Error('localAutocompleteEnabled missing');
if (!/ollamaFetchAndStream\(/.test(js)) throw new Error('ollamaFetchAndStream missing');
if (!/getReader\(\)/.test(js)) throw new Error('v2 streaming reader missing');
if (/await res\.text\(\)/.test(js)) throw new Error('v1 buffering still present');
if (/options:\{num_predict:numPredict, keep_alive/.test(js)) throw new Error('keep_alive still inside options');
if (!/keep_alive:keepAlive,raw:false/.test(js)) throw new Error('top-level keep_alive missing');
if (!/if\(localAutocompleteEnabled\(\)\)/.test(js)) throw new Error('local branch missing');
if ((js.match(/if\(localAutocompleteEnabled\(\)\)/g) || []).length !== 1) throw new Error('duplicate local branch');
console.log('patch structure validated');
NODE

mv -f "$TMP" "$BUNDLE"
sha256sum "$BUNDLE" | awk '{print $1}' > "$STATE_DIR/patched-sha256"
sha256sum "$BUNDLE" | awk '{print $1}' > "$STATE_DIR/current-sha256"
if [ ! -f "$STATE_DIR/original-sha256" ]; then
  printf '%s\n' "$CURRENT_HASH" > "$STATE_DIR/original-sha256"
fi
cat > "$STATE_DIR/installed-version" <<EOF
Code OSS: $CODE_OSS_VERSION
Copilot: $COPILOT_VERSION
Completions Core: $CORE_VERSION
Bundle SHA256: $(sha256sum "$BUNDLE" | awk '{print $1}')
Patch version: $PATCH_VERSION
Patch status: INSTALLED
EOF

echo "Patch applied successfully."
