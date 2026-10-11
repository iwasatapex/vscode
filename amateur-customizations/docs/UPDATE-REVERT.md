# Update

1. `sudo pacman -Syu` (code upgrades trigger the marketplace hook).
2. Re-run copilot `patch-copilot.sh`; on `UNKNOWN VERSION` stop and
   diff the new bundle — patterns (`fetchAndStreamCompletions`,
   `this.#e`, `copilotTokenManager`) may have moved.
3. Re-check `ollama list` models; update picker enum only for exact
   installed ids.
4. Rebase this branch onto the new upstream tag, re-verify, commit.

# Revert

```bash
bash amateur-customizations/scripts/copilot-local-autocomplete/restore-copilot.sh
sudo cp /usr/lib/code/product.json.bak-<stamp> /usr/lib/code/product.json
sudo rm -f /usr/local/bin/code-oss-ms-marketplace \
  /etc/pacman.d/hooks/95-code-oss-ms-marketplace.hook
systemctl --user disable --now ollama-qwen-autocomplete.service
code-oss --uninstall-extension local.local-ollama-autocomplete
git checkout 1.138.0  # leave the branch checked out nowhere destructive
```

# Troubleshooting / known issues (do not auto-repair)

- FOLLOW-UP 1: `copilot-local-autocomplete.service/.timer` present in
  2026-10-09 snapshot but absent live (`~/.config/systemd/user/`).
  Record-only; re-enable only after review.
- FOLLOW-UP 2: `pin-qca.sh` defaults to `QCA_MODEL=qca`, but
  `ollama show qca` → `model 'qca:latest' not found`. Set
  `QCA_MODEL=qwen2.5-coder:1.5b` (or 3b-base) explicitly.
- FOLLOW-UP 3: `ollama ps` shows GPU model resident, Qwen evicted;
  watchdog service is `disabled/inactive`. Decide residency policy.
- Marketplace/Copilot redistribution: scripts only, respect vendor
  licenses; `extensions.verifySignature:false` weakens signature checks
  (Microsoft blocklist via `controlUrl` still applies).
