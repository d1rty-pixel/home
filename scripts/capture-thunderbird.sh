#!/usr/bin/env bash
#
# Capture this machine's Thunderbird accounts + saved passwords into the workplace
# repo, encrypted with Ansible Vault. Run this whenever you change your Thunderbird
# setup and want the repo to reflect it.
#
# Usage:
#   scripts/capture-thunderbird.sh [profile-dir-name]
#
# Vault password: uses ./.vault-pass if present, otherwise prompts.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_DIR/roles/thunderbird/files/profile"
TB="$HOME/.thunderbird"
PROFILE="${1:-$(sed -n 's/^Default=\(.*default-release\)$/\1/p' "$TB/profiles.ini" 2>/dev/null | head -1)}"
PROFILE="${PROFILE:-o9utqzgx.default-release}"
FILES=(prefs.js logins.json key4.db cert9.db)

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v ansible-vault >/dev/null 2>&1 || die "ansible-vault not found (install ansible)."
[ -d "$TB/$PROFILE" ] || die "Profile not found: $TB/$PROFILE"
pgrep -x thunderbird >/dev/null && die "Close Thunderbird first (it rewrites its profile on exit)."

VAULT_ARGS=()
[ -f "$REPO_DIR/.vault-pass" ] && VAULT_ARGS=(--vault-password-file "$REPO_DIR/.vault-pass")

mkdir -p "$DEST"
info "Capturing profile '$PROFILE' -> $DEST"
for f in "${FILES[@]}"; do
    src="$TB/$PROFILE/$f"
    [ -f "$src" ] || { echo "  skip $f (absent)"; continue; }
    cp -f "$src" "$DEST/$f"
    ansible-vault encrypt "${VAULT_ARGS[@]}" "$DEST/$f"
    # Safety: make sure it is actually encrypted before it can be committed.
    head -c 15 "$DEST/$f" | grep -q '$ANSIBLE_VAULT' \
        || { rm -f "$DEST/$f"; die "ENCRYPTION FAILED for $f — removed to avoid leaking plaintext."; }
    echo "  encrypted $f"
done

info "Done. Review, then commit roles/thunderbird/files/profile/*"
echo "   git -C '$REPO_DIR' add roles/thunderbird/files/profile && git -C '$REPO_DIR' commit"
