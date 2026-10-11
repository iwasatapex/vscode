# Verify (read-only)

```bash
code --version  # expect 1.138.0 7debcd0e2a
sha256sum /usr/lib/code/extensions/copilot/dist/extension.js
cat /var/lib/copilot-local-autocomplete/state/patched-sha256
bash amateur-customizations/scripts/copilot-local-autocomplete/verify-copilot-patch.sh
grep -c localAutocompleteEnabled /usr/lib/code/extensions/copilot/dist/extension.js
ollama list | grep -i qwen
systemctl --user status ollama-qwen-autocomplete.service --no-pager -l
git rev-parse 1.138.0^{commit}
```

Expected patched SHA (2026-10-09): 
`c2d360e5a06402f1ee84f3bef253caff26da6aabf288fbda4fc3fa87ef372e4a`,
Copilot `0.66.0`, core `1.378.1799`.
