# Amateur local customizations (Code-OSS 1.138.0)

Personal, reproducible layer on top of upstream `microsoft/vscode` tag
`1.138.0` (commit `7debcd0e2acdea1c52de81bf9ee1620444407dda`).
Branch: `amateur/local-customizations`.

## Layout

- `extensions/local-ollama-autocomplete/` — standalone model-picker
  extension (first-party, MIT). Install via VSIX or copy.
- `scripts/copilot-local-autocomplete/` — **patch scripts only** for the
  proprietary built-in Copilot bundle
  (`/usr/lib/code/extensions/copilot/dist/extension.js`).
  The patched/proprietary bundle itself is NEVER committed.
- `scripts/marketplace/code-oss-ms-marketplace.sh` — idempotent
  `product.json` gallery switch (Open VSX → Microsoft) + pacman hook
  installer. Requires root for system paths.
- `scripts/ollama/pin-qca.sh` — keep a CPU-only Ollama model resident.
- `systemd/ollama-qwen-autocomplete.service` — user unit running
  `pin-qca.sh watchdog`.
- `examples/settings.template.jsonc` — sanitized settings template.
  Real `settings.json`, tokens, DB creds, chat histories are excluded.
- `docs/` — apply / verify / update / revert notes.

## Upstream

- Upstream: `https://github.com/microsoft/vscode` (`upstream` remote).
- Fork: `https://github.com/iwasatapex/vscode` (`origin` remote).
- Base: tag `1.138.0`. Verify with
  `git rev-parse 1.138.0^{commit}` → `7debcd0e2...`.

## Apply

```bash
# 1. model picker (user extension dir)
cp -r amateur-customizations/extensions/local-ollama-autocomplete \
  ~/.vscode-oss/extensions/local-ollama-autocomplete-0.1.0
# or: code-oss --install-extension <built .vsix>

# 2. copilot patch (needs root for /usr/lib/code)
sudo BUNDLE=/usr/lib/code/extensions/copilot/dist/extension.js \
  bash amateur-customizations/scripts/copilot-local-autocomplete/patch-copilot.sh
bash amateur-customizations/scripts/copilot-local-autocomplete/verify-copilot-patch.sh

# 3. marketplace shim (needs root)
sudo bash amateur-customizations/scripts/marketplace/code-oss-ms-marketplace.sh

# 4. ollama watchdog (user)
cp amateur-customizations/systemd/ollama-qwen-autocomplete.service \
  ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now ollama-qwen-autocomplete.service
```

See `docs/APPLY.md`, `docs/VERIFY.md`, `docs/UPDATE.md`, `docs/REVERT.md`.

## Safety / licensing

- Copilot bundle is proprietary: only scripts + docs are tracked.
- No secrets, `settings.json`, model blobs, `.vsix` binaries, or the
  2.9 GB snapshot are committed.
- Never force-push. Re-apply scripts are idempotent.
