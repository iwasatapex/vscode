# Apply

Idempotent order: extension → copilot patch → marketplace → watchdog.
All patch scripts refuse unknown bundle hashes (exit 3) instead of
guessing.

1. Extension: copy `extensions/local-ollama-autocomplete` to
   `~/.vscode-oss/extensions/local-ollama-autocomplete-0.1.0/` or build
   a VSIX and `code-oss --install-extension`.
2. Copilot patch (root): run `patch-copilot.sh` with `BUNDLE=` pointing
   at the live `/usr/lib/code/extensions/copilot/dist/extension.js`.
   It backs up pristine bundles hash-guarded and inserts the
   `localAutocompleteEnabled → ollamaFetchAndStream` branch once.
3. Marketplace (root): `code-oss-ms-marketplace.sh` backs up
   `/usr/lib/code/product.json`, rewrites only `extensionsGallery` +
   `linkProtectionTrustedDomains`, installs
   `/etc/pacman.d/hooks/95-code-oss-ms-marketplace.hook`.
4. Watchdog (user): install `systemd/ollama-qwen-autocomplete.service`,
   `daemon-reload`, `enable --now`. Configure `QCA_MODEL` (default
   `qca` alias does NOT exist — set to `qwen2.5-coder:1.5b` etc.).
