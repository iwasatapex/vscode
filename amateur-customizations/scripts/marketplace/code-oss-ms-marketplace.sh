#!/bin/bash
#
# code-oss-ms-marketplace.sh
#
# Points the CachyOS/Arch "code" package (Code - OSS, /usr/lib/code) at the
# official Microsoft Visual Studio Code Marketplace instead of Open VSX.
#
# Values changed in /usr/lib/code/product.json (nothing else is modified):
#   extensionsGallery.serviceUrl          -> Microsoft gallery query API
#   extensionsGallery.itemUrl             -> Microsoft marketplace item pages
#   extensionsGallery.publisherUrl        -> Microsoft marketplace publisher pages
#   extensionsGallery.resourceUrlTemplate -> Microsoft unpkg CDN (icons/assets)
#   extensionsGallery.controlUrl          -> Microsoft malicious-extension blocklist
#   extensionsGallery.latestUrlTemplate   -> removed (Open VSX-only endpoint)
#   linkProtectionTrustedDomains          -> marketplace.visualstudio.com appended
#
# Safety:
#   * backs up product.json to product.json.bak-<timestamp> before the first change
#   * idempotent: exits early if the Microsoft gallery is already configured
#   * atomic write (temp file + rename), JSON validated before and after
#   * can install a pacman hook so the setting survives "pacman -Syu"
#
# Usage:
#   ./code-oss-ms-marketplace.sh              # patch + install pacman hook (root)
#   ./code-oss-ms-marketplace.sh --patch-only # patch only (used by the pacman hook)
#
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

PRODUCT="/usr/lib/code/product.json"
SELF_INSTALL="/usr/local/bin/code-oss-ms-marketplace"
HOOK="/etc/pacman.d/hooks/95-code-oss-ms-marketplace.hook"
PYTHON="/usr/bin/python3"

PATCH_ONLY=0
[ "${1:-}" = "--patch-only" ] && PATCH_ONLY=1

log() { printf '==> %s\n' "$*"; }

# --------------------------------------------------------------------------
# 0. escalate if not root
# --------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log "Root privileges are needed to patch ${PRODUCT}."
    if command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        log "Asking for authorisation via pkexec (a password dialog will appear)..."
        exec pkexec "$0" "$@"
    fi
    echo "Please re-run: sudo $0" >&2
    exit 1
fi

[ -f "$PRODUCT" ] || { echo "ERROR: ${PRODUCT} not found - is the 'code' package installed?" >&2; exit 1; }
[ -x "$PYTHON" ] || { echo "ERROR: ${PYTHON} not found." >&2; exit 1; }

# --------------------------------------------------------------------------
# 1. is it already pointing at the Microsoft Marketplace?
# --------------------------------------------------------------------------
already=0
if "$PYTHON" - "$PRODUCT" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    product = json.load(fh)
gallery = product.get("extensionsGallery") or {}
sys.exit(0 if "marketplace.visualstudio.com" in str(gallery.get("serviceUrl", "")) else 1)
PY
then
    already=1
fi

# --------------------------------------------------------------------------
# 2. backup + patch
# --------------------------------------------------------------------------
if [ "$already" -eq 1 ]; then
    log "Microsoft Marketplace already configured in ${PRODUCT} - not touching it."
else
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="${PRODUCT}.bak-${stamp}"
    log "Backup: ${backup}"
    cp -a -- "$PRODUCT" "$backup"
    chmod 0644 -- "$backup"

    log "Patching extension gallery configuration"
    "$PYTHON" - "$PRODUCT" <<'PY'
import json, os, sys, tempfile

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    product = json.load(fh)

# Only endpoints that were individually verified over HTTPS are written here.
gallery = product.get("extensionsGallery") or {}
gallery.update({
    "serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",
    "itemUrl": "https://marketplace.visualstudio.com/items",
    "publisherUrl": "https://marketplace.visualstudio.com/publishers",
    "resourceUrlTemplate": "https://{publisher}.vscode-unpkg.net/{publisher}/{name}/{version}/{path}",
    "controlUrl": "https://main.vscode-cdn.net/extensions/marketplace.json",
})
# Open VSX-only endpoint; the Microsoft gallery has no equivalent route. The client
# then uses ${serviceUrl}/vscode/{publisher}/{name}/latest (which Microsoft serves)
# or falls back to the classic extensionquery API.
gallery.pop("latestUrlTemplate", None)
product["extensionsGallery"] = gallery

domains = product.get("linkProtectionTrustedDomains") or []
for domain in ("https://marketplace.visualstudio.com",):
    if domain not in domains:
        domains.append(domain)
product["linkProtectionTrustedDomains"] = domains

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".product.json.")
with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
    json.dump(product, fh, indent="\t", ensure_ascii=False)
    fh.write("\n")
os.chmod(tmp_path, 0o644)
os.replace(tmp_path, path)
PY
fi

# --------------------------------------------------------------------------
# 3. prune old backups (keep the 3 most recent) and verify the result
# --------------------------------------------------------------------------
for old in $(ls -1t "${PRODUCT}".bak-* 2>/dev/null | tail -n +4); do
    log "Removing old backup ${old}"
    rm -f -- "$old"
done

log "Verifying ${PRODUCT}"
"$PYTHON" - "$PRODUCT" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    product = json.load(fh)
gallery = product["extensionsGallery"]
expected = {
    "serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",
    "itemUrl": "https://marketplace.visualstudio.com/items",
    "publisherUrl": "https://marketplace.visualstudio.com/publishers",
    "resourceUrlTemplate": "https://{publisher}.vscode-unpkg.net/{publisher}/{name}/{version}/{path}",
    "controlUrl": "https://main.vscode-cdn.net/extensions/marketplace.json",
}
print("product.json nameLong       :", product.get("nameLong"))
print("product.json version        :", product.get("version"))
print("product.json commit         :", product.get("commit"))
print("extensionsGallery           :")
for key in sorted(gallery):
    print(f"    {key} = {gallery[key]}")
print("linkProtectionTrustedDomains:", product.get("linkProtectionTrustedDomains"))
for key, value in expected.items():
    if gallery.get(key) != value:
        sys.exit(f"ERROR: {key} is {gallery.get(key)!r}, expected {value!r}")
if "latestUrlTemplate" in gallery:
    sys.exit("ERROR: latestUrlTemplate still present")
print("OK: Microsoft Marketplace endpoints configured")
PY

# --------------------------------------------------------------------------
# 4. install hook + a stable copy of this script (skipped with --patch-only)
# --------------------------------------------------------------------------
if [ "$PATCH_ONLY" -eq 0 ]; then
    if [ "$0" != "$SELF_INSTALL" ]; then
        log "Installing ${SELF_INSTALL}"
        install -Dm0755 "$0" "$SELF_INSTALL"
    fi

    log "Installing pacman hook ${HOOK}"
    install -d -m0755 /etc/pacman.d/hooks
    cat > "$HOOK" <<'HOOKEOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = code

[Action]
Description = Re-applying the Microsoft Marketplace gallery configuration to /usr/lib/code/product.json
When = PostTransaction
Exec = /usr/local/bin/code-oss-ms-marketplace --patch-only
HOOKEOF
    chmod 0644 -- "$HOOK"

    log "Done."
    echo
    echo "Next steps:"
    echo "  1. Fully quit and restart Code - OSS (a running instance keeps the old config)."
    echo "  2. Open the Extensions view and search for 'pylance' or 'ms-toolsai':"
    echo "     results must come from the Microsoft Marketplace (verified-publisher badges)."
    echo "  3. Rollback at any time:"
    echo "       sudo cp ${PRODUCT}.bak-<newest timestamp> ${PRODUCT}"
    echo "       sudo rm -f ${SELF_INSTALL} ${HOOK}"
fi
