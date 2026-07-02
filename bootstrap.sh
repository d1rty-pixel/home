#!/usr/bin/env bash
#
# bootstrap.sh — provision this machine's "workplace" from the Ansible repo.
#
# Usage:
#   ./bootstrap.sh
#
# Environment overrides:
#   WORKPLACE_REPO   clone URL (default: HTTPS, so no SSH key is needed on a fresh box)
#                    e.g. WORKPLACE_REPO=git@github.com:d1rty-pixel/home.git
#   WORKPLACE_DIR    checkout location (default: $HOME/Projekte/workplace)
#
set -euo pipefail

REPO_URL="${WORKPLACE_REPO:-https://github.com/d1rty-pixel/home.git}"
REPO_DIR="${WORKPLACE_DIR:-$HOME/Projekte/workplace}"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. sudo precheck — do this before touching anything.
# ---------------------------------------------------------------------------
info "Checking sudo privileges..."
command -v sudo >/dev/null 2>&1 \
    || die "sudo is not installed. Install it and add your user to the wheel/sudo group, then re-run."

if ! id -nG "$USER" | tr ' ' '\n' | grep -qxE 'wheel|sudo|root'; then
    die "User '$USER' is not in the wheel/sudo group.
       As root run:  usermod -aG wheel $USER   (Debian/Ubuntu: usermod -aG sudo $USER)
       then log out/in and re-run this script."
fi

sudo -v || die "Could not obtain sudo. You need sudo rights to install packages."
info "sudo OK."

# ---------------------------------------------------------------------------
# 1. detect OS family
# ---------------------------------------------------------------------------
[ -r /etc/os-release ] || die "/etc/os-release not found; cannot detect the distribution."
# shellcheck disable=SC1091
. /etc/os-release

family=""
case " ${ID:-} ${ID_LIKE:-} " in
    *" arch "*)                 family="arch" ;;
    *" debian "* | *" ubuntu "*) family="debian" ;;
esac
[ -n "$family" ] || die "Unsupported distribution (ID=${ID:-?}, ID_LIKE=${ID_LIKE:-?})."
info "Detected OS family: $family"

# ---------------------------------------------------------------------------
# 2. install prerequisites
# ---------------------------------------------------------------------------
info "Installing prerequisites (git, ansible, build tools, curl)..."
case "$family" in
    arch)
        sudo pacman -Sy --needed --noconfirm git ansible base-devel curl
        ;;
    debian)
        sudo apt-get update
        sudo apt-get install -y git ansible build-essential curl
        ;;
esac

# ---------------------------------------------------------------------------
# 3. clone or update the repo
# ---------------------------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
    info "Repo already present at $REPO_DIR — pulling latest."
    git -C "$REPO_DIR" pull --ff-only || warn "git pull failed; continuing with the local copy."
else
    case "$REPO_URL" in
        git@* | ssh://*)
            info "Verifying SSH access to GitHub..."
            if ! ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 \
                    | grep -qi 'successfully authenticated'; then
                warn "SSH auth to GitHub could not be confirmed."
                warn "Add an SSH key to your GitHub account first, or re-run over HTTPS:"
                warn "    WORKPLACE_REPO=https://github.com/d1rty-pixel/home.git ./bootstrap.sh"
                die  "Aborting before clone."
            fi
            ;;
    esac
    info "Cloning $REPO_URL -> $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# ---------------------------------------------------------------------------
# 4. Ansible collections
# ---------------------------------------------------------------------------
info "Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml

# ---------------------------------------------------------------------------
# 5. run the playbook
# ---------------------------------------------------------------------------
info "Running the Ansible playbook (you'll be asked for your sudo password)..."
ansible-playbook -i inventory.ini site.yml --ask-become-pass

# ---------------------------------------------------------------------------
# 6. done
# ---------------------------------------------------------------------------
cat <<'EOF'

  ✔ Workplace provisioned.

  Next:
    • Log out and back in (or run: exec bash) so the default shell,
      $EDITOR and the starship prompt take effect.
    • Set your real git name in group_vars/all.yml if needed, then re-run.

  voilà.
EOF
