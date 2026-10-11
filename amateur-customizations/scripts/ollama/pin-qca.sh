#!/usr/bin/env bash
# pin-qca.sh - keep the CPU-only Qwen2.5-Coder 1.5B ("qca") resident on Ollama.
#
# WHY THIS EXISTS
#   Ollama's scheduler (sched.go) evicts *every* loaded runner whenever it predicts
#   that a newly requested model will not fit in GPU memory.  That prediction is
#   deliberately conservative and it ignores the fact that a CPU-only runner holds
#   0 MiB of VRAM, so requesting a big GPU model (gex2 / on / gesql) kills qca's
#   runner even though freeing qca frees no VRAM at all.  This script restores qca
#   within a few seconds and keeps its keep-alive at "forever".
#
#   A normal inference request sent to qca by the editor resets its keep-alive to
#   that request's value (typically 5m), so the periodic refresh below is required
#   in order to keep "UNTIL = Forever".
#
# MODES
#   load      load/refresh qca: num_ctx=32768, num_gpu=0, keep_alive=-1
#   pin       same but with an empty prompt (cheapest keep-alive refresh)
#   unpin     unload qca
#   present   exit 0 only if qca is loaded AND using 0 MiB VRAM (silent)
#   watchdog  run forever: restore qca when evicted, refresh keep-alive,
#             and force a CPU-only reload if it ever appears on the GPU
set -uo pipefail

API="${QCA_API:-http://127.0.0.1:11435}"
MODEL="${QCA_MODEL:-qca}"
CTX="${QCA_CTX:-32768}"
INTERVAL="${QCA_INTERVAL:-5}"   # how often to verify that qca is still loaded
REFRESH="${QCA_REFRESH:-60}"    # how often to re-arm keep_alive=-1
CURL=/usr/bin/curl

post() { # post <prompt> <keep_alive>
  "$CURL" -fsS -m 300 -H 'Content-Type: application/json' \
    "$API/api/generate" \
    --data-raw "{\"model\":\"$MODEL\",\"prompt\":\"$1\",\"stream\":false,\"keep_alive\":$2,\"options\":{\"num_ctx\":$CTX,\"num_gpu\":0,\"num_predict\":1}}" \
    >/dev/null 2>&1
}

vram_bytes() { # echoes size_vram of the loaded model; fails if it is not loaded
  local json frag
  json=$("$CURL" -fsS -m 10 "$API/api/ps" 2>/dev/null) || return 1
  # models are separated by "},{" - split there so nested objects don't break parsing
  frag=$(printf '%s' "$json" | sed 's/},{/}\n{/g' | grep -F "\"name\":\"$MODEL:latest\"" | head -n1)
  [ -n "$frag" ] || return 1
  printf '%s' "$frag" | grep -o '"size_vram":[0-9]*' | head -n1 | cut -d: -f2
}

case "${1:-load}" in
  load)
    post "Return exactly OK." -1
    ;;
  pin)
    post "" -1
    ;;
  unpin)
    post "" 0
    ;;
  present)
    v=$(vram_bytes) || exit 1
    [ "$v" = "0" ] || exit 1
    exit 0
    ;;
  watchdog)
    declare -i last now
    post "Return exactly OK." -1
    last=$(date +%s)
    while :; do
      sleep "$INTERVAL"
      now=$(date +%s)
      if ! v=$(vram_bytes); then
        # qca is gone - most likely evicted by a big GPU model load
        if post "Return exactly OK." -1; then
          last=$(date +%s)
          echo "qca restored (num_gpu=0, num_ctx=$CTX, keep_alive=-1)"
        fi
      elif [ "$v" != "0" ]; then
        echo "qca found with $v bytes on GPU - forcing CPU-only reload" >&2
        post "" 0
        if post "Return exactly OK." -1; then last=$(date +%s); fi
      elif [ $((now - last)) -ge "$REFRESH" ]; then
        if post "" -1; then last=$(date +%s); fi
      fi
    done
    ;;
  *)
    echo "Usage: $0 {load|pin|unpin|present|watchdog}" >&2
    exit 2
    ;;
esac
