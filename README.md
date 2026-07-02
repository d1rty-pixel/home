# workplace

My Linux workplace as code — packages + dotfiles, deployed with Ansible.
One command rebuilds a fresh machine.

Currently populated for **Arch / CachyOS**; the structure is **multi-OS ready** so a
future **Debian / Ubuntu** box only needs its package list filled in.

## Quick start

On a fresh machine:

```sh
# 1. Make sure your SSH key is added to GitHub (this repo clones over SSH).
# 2. Clone and run:
git clone git@github.com:equinox/workplace.git ~/Projekte/workplace
~/Projekte/workplace/bootstrap.sh
```

No SSH key yet? Clone over HTTPS for the first run:

```sh
WORKPLACE_REPO=https://github.com/equinox/workplace.git \
  bash -c 'git clone "$WORKPLACE_REPO" ~/Projekte/workplace && ~/Projekte/workplace/bootstrap.sh'
```

`bootstrap.sh` will:
1. **Check you have sudo** (aborts early with instructions if not).
2. Detect the OS family and install prerequisites (`git`, `ansible`, build tools, `curl`).
3. Clone/update this repo to `~/Projekte/workplace`.
4. Install the required Ansible collections.
5. Run `site.yml` (prompts once for your sudo password).

After it finishes, log out/in (or `exec bash`) so the shell change, `$EDITOR` and the
starship prompt take effect.

## What it sets up

- **Shell:** bash as the default login shell, `EDITOR`/`VISUAL=vim`.
- **Prompt:** starship (with a starter `starship.toml`).
- **Terminal:** alacritty on Arch/CachyOS (Nord theme, transparency, custom keybinds);
  distro-default terminal on Debian/Ubuntu.
- **Editors/tools:** vim, micro (catppuccin), meld, git, ripgrep, btop, glances,
  fastfetch, duf, ufw, rsync, wget.
- **GUI apps:** firefox, vlc, haruna, spotify (Arch), pavucontrol.
- **AUR:** installs `yay` on Arch so AUR packages can be added later.
- **Claude Code:** installs the `claude` CLI.
- **Dotfiles:** symlinked from this repo into `$HOME`, so edits stay git-tracked.
  A `~/.gitconfig` is templated from `group_vars/all.yml`.

## Layout

```
bootstrap.sh          one-command entrypoint
site.yml              main playbook (loads vars by OS family, runs roles)
ansible.cfg           inventory/roles/become defaults
inventory.ini         localhost, local connection
requirements.yml      Ansible collections (community.general, kewlfft.aur)
group_vars/all.yml    feature toggles + git identity
vars/
  Archlinux.yml       pacman + AUR + GUI package lists  (populated)
  Debian.yml          apt package lists                 (stub, TODO markers)
roles/
  packages/           installs system + GUI packages per OS family
  aur/                Arch-only: builds yay, installs AUR packages
  starship/           installs starship (pacman / official installer)
  claude-code/        installs the claude CLI
  dotfiles/           symlinks configs into $HOME, templates .gitconfig
  shell/              sets bash as the default login shell
```

## Customizing

- **Add a package:** edit `vars/Archlinux.yml` (and `vars/Debian.yml`). Package *names*
  live only in these files — tasks are OS-agnostic.
- **Add a dotfile:** drop the file under `roles/dotfiles/files/` and add an entry to
  `dotfiles_links` in `roles/dotfiles/defaults/main.yml`.
- **Set your git name/email:** `group_vars/all.yml`.
- **Skip GUI apps:** set `install_gui: false` in `group_vars/all.yml`.

## Verify without changing anything

```sh
cd ~/Projekte/workplace
ansible-playbook -i inventory.ini site.yml --syntax-check
ansible-playbook -i inventory.ini site.yml --check --diff --ask-become-pass
```

## Adding a Debian/Ubuntu machine later

`vars/Debian.yml` and the apt task path already exist. Fill in/verify the package names
for your release (see the `TODO` markers), then run `bootstrap.sh` there — everything
branches on `ansible_facts['os_family']` automatically.

## Out of scope

- **KDE/Plasma settings** — fragile to sync; use Plasma's built-in settings sync.
- **Secrets / SSH keys** — never committed; provision your SSH key manually before the
  first SSH clone.
- **Language toolchains** (node/rust/go) — none installed today; add to `vars/*` when needed.
