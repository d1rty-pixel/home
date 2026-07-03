# workplace

My Linux workplace as code — packages + dotfiles, deployed with Ansible.
One command rebuilds a fresh machine.

Currently populated for **Arch / CachyOS**; the structure is **multi-OS ready** so a
future **Debian / Ubuntu** box only needs its package list filled in.

## Quick start

On a fresh machine — clones over **HTTPS**, so no SSH key is needed:

```sh
git clone https://github.com/d1rty-pixel/home.git ~/Projekte/workplace
~/Projekte/workplace/bootstrap.sh
```

Don't have an SSH key yet? `bootstrap.sh` will offer to create one and walk you through adding
it to GitHub. To push changes back, point the remote at SSH once:

```sh
cd ~/Projekte/workplace
git remote set-url origin git@github.com:d1rty-pixel/home.git
```

`bootstrap.sh` will:
1. **Check you have sudo** (aborts early with instructions if not).
2. Detect the OS family and install prerequisites (`git`, `ansible`, build tools, `curl`, `openssh`).
3. **SSH key:** if you don't already have one in `~/.ssh`, it offers to generate an ed25519 key,
   prints the public half with the GitHub upload URL, waits while you add it, then tests the
   connection. (Not required for the HTTPS clone — this is so you can *push* later.)
4. Clone/update this repo to `~/Projekte/workplace`.
5. Install the required Ansible collections.
6. Run `play-workplace.yaml` (prompts once for your sudo password).

After it finishes, log out/in (or `exec bash`) so the shell change, `$EDITOR` and the
starship prompt take effect.

## What it sets up

- **Shell:** bash as the default login shell, `EDITOR`/`VISUAL=vim`.
- **Prompt:** starship (with a starter `starship.toml`).
- **Terminal:** alacritty on Arch/CachyOS (Nord theme, transparency, custom keybinds);
  distro-default terminal on Debian/Ubuntu.
- **Editors/tools:** vim, micro (catppuccin), meld, git, ripgrep, btop, glances,
  fastfetch, duf, ufw, rsync, wget.
- **GUI apps:** firefox, thunderbird, vlc, haruna, spotify, google-chrome, pavucontrol,
  and JetBrains Toolbox (which manages IntelliJ IDEA). Chrome is AUR on Arch; on Debian
  Spotify/Chrome come from vendor apt repos. Toolbox is a shared tarball-install role.
- **Steam:** native (Arch multilib is auto-enabled first; `steam-installer` on Debian).
  Optionally pre-fills your Steam login (see "Steam account" below).
- **Netflix (Arch only):** an unofficial AUR wrapper — no official Linux client exists, so
  this is community-maintained and can break; log in inside the wrapper. (Or just use
  `netflix.com` in Chrome, which handles the DRM.)
- **AUR:** installs `yay` on Arch so AUR packages can be added later.
- **Node.js:** full setup via nvm — installs the latest LTS, enables Corepack
  (yarn/pnpm), and installs any `npm_global_packages`.
- **Perl:** two module lists — `perl_os_packages` (from pacman/apt, preferred) and
  `perl_cpan_modules` (via cpanm, discouraged: source build, bypasses the OS manager).
- **Docker:** Docker Engine + Compose v2, service enabled, your user added to the
  `docker` group (re-login required).
- **Browsers:** Firefox is removed once Chrome is installed.
- **Claude Code:** installs the `claude` CLI.
- **Dotfiles:** symlinked from this repo into `$HOME`, so edits stay git-tracked.
  A `~/.gitconfig` is templated from `group_vars/all.yml`, and a `~/.ssh/config`
  (github.com host block + sane defaults; `~/.ssh` kept at `0700`) is linked in.

## Layout

```
bootstrap.sh          one-command entrypoint
play-workplace.yaml   main playbook (loads vars by OS family, runs roles)
capture-thunderbird.yml / capture-steam.yml   maintenance: capture creds/settings into the repo
ansible.cfg           inventory/roles/become defaults
inventory.ini         localhost + empty [workstation] group for remote machines
requirements.yml      Ansible collections (community.general)
group_vars/all.yml    feature toggles + git identity
vars/
  software_catalog.yml OS-agnostic "what to install" catalog (source of truth)
  Archlinux.yml       Arch role-specific vars (docker/perl/removals)
  Debian.yml          Debian role-specific vars (stub, TODO markers)
roles/
  software-facts/     resolves the catalog into an install plan (custom fact) on the host
  packages/           feeds the resolved plan to the native package modules
  aur/                Arch-only: builds yay, installs AUR pkgs, drops Firefox for Chrome
  nodejs/             full Node.js setup via nvm (LTS + corepack + global npm pkgs)
  perl/               Perl modules: OS packages (preferred) + CPAN (discouraged)
  docker/             Docker Engine + service + adds you to the docker group
  docker-compose/     Docker Compose v2 plugin
  starship/           installs starship (pacman / official installer)
  claude-code/        installs the claude CLI
  jetbrains-toolbox/  installs JetBrains Toolbox (tarball; manages IntelliJ IDEA)
  thunderbird/        deploys captured accounts + passwords (Ansible Vault)
  steam/              deploys captured Steam login settings (Ansible Vault)
  default-apps/       sets default browser (Chrome) + mail client (Thunderbird)
  dotfiles/           symlinks configs into $HOME, templates .gitconfig
  shell/              sets bash as the default login shell
```

## How packages get installed (custom facts)

Package *names* and the *install method* are no longer hard-coded per OS. Instead:

1. `vars/software_catalog.yml` is one **OS-agnostic catalog** of logical software items
   (`chrome`, `vim`, `spotify`, …), each declaring its package name(s) per OS family
   and, optionally, a pinned method.
2. The `software-facts` role ships the catalog + a resolver script to the target host
   (`/etc/ansible/facts.d/`). The resolver runs **on the host** as an Ansible custom
   fact: it picks the right package name for the detected distro and **decides the
   install method** — autodetecting where not pinned:
   - in the official repos → **native** (pacman/apt)
   - Arch, but not in the official repos → **aur** (this is how `google-chrome`
     resolves to the AUR without being told to)
   - a known flatpak id + flatpak present → **flatpak**
3. The result lands at `ansible_local.software_plan.plan` (grouped by method), and the
   `packages` / `aur` roles feed each bucket to the matching module.

Inspect the resolved plan on any host with:

```sh
ansible -i inventory.ini localhost -m setup -a 'filter=ansible_local'
```

## Customizing

- **Add a package:** add an item to `vars/software_catalog.yml`. Use a plain
  `packages: <name>` if it's the same everywhere, or a per-OS map
  (`packages: { Archlinux: foo, Debian: foo-bar }`). Leave `method` off to autodetect;
  pin it (`aur`, `vendor_repo`, `flatpak`) only when needed.
- **Add a dotfile:** drop the file under `roles/dotfiles/files/` and add an entry to
  `dotfiles_links` in `roles/dotfiles/defaults/main.yml`.
- **Set your git name/email:** `group_vars/all.yml`.
- **Skip GUI apps:** set `install_gui: false` in `group_vars/all.yml`.

## Verify without changing anything

```sh
cd ~/Projekte/workplace
ansible-playbook -i inventory.ini play-workplace.yaml --syntax-check
ansible-playbook -i inventory.ini play-workplace.yaml --check --diff --ask-become-pass
```

## Thunderbird accounts (Ansible Vault)

The `thunderbird` role deploys a captured profile — accounts **and** saved passwords —
so a new machine comes up already configured. The credential files (`key4.db`,
`logins.json`) and `prefs.js` are **Ansible-Vault-encrypted**, so only ciphertext lives
in git.

**Capture** (pull your current setup into the repo) is a separate maintenance
playbook — deliberately *not* part of provisioning, and it runs the opposite
direction (local machine → repo). Do it from a configured machine, Thunderbird
**closed**, with a vault password file present (a task can't answer a vault prompt):

```sh
printf 'your-vault-password' > .vault-pass && chmod 600 .vault-pass   # gitignored
ansible-playbook capture-thunderbird.yml
git add roles/thunderbird/files/profile && git commit
```

**Deploy** is automatic during `bootstrap.sh`: it detects the vault-encrypted files and,
if `./.vault-pass` doesn't exist yet, prompts once for the vault password and stores it
there (gitignored, `0600`) for this and future runs. The role **won't overwrite**
an already-configured profile (`force: false`) and refuses to run while Thunderbird is
open. It's a no-op until a capture exists. Disable with `deploy_thunderbird: false`.

Manual run:

```sh
ansible-playbook -i inventory.ini play-workplace.yaml --ask-become-pass --ask-vault-pass
```

## Steam account (settings, Ansible Vault)

The `steam` role can pre-fill your Steam login on a new machine. **Important:** unlike
Thunderbird, this stores **no password and no session token** — Steam keeps no plaintext
password, and its auto-login artifacts (`ssfn*`, `config.vdf` `ConnectCache`) are bound to
the machine + Steam Guard and are deliberately *not* captured. What *is* captured is
`loginusers.vdf` (your account name + autologin flag) and `config.vdf` (general settings),
vault-encrypted. Result: a new machine shows your account pre-selected on the login screen;
you enter your **password + Steam Guard once**.

**Capture** (local machine → repo), Steam **closed**, vault password file present:

```sh
printf 'your-vault-password' > .vault-pass && chmod 600 .vault-pass   # gitignored
ansible-playbook capture-steam.yml
git add roles/steam/files/config && git commit
```

**Deploy** happens during provisioning like Thunderbird's: `force: false` (never clobbers an
already-configured machine), refuses to run while Steam is open, and is a no-op until a
capture exists. Disable with `deploy_steam: false`. Steam itself installs regardless (it's a
catalog item; Arch multilib is auto-enabled first).

## Chrome / Google account

Chrome is installed by the repo, but its login is **not** captured like Thunderbird —
Chrome ties cookies/passwords to the OS keyring, so a copied profile won't decrypt on
another machine. Use **Chrome Sync** instead: sign in to your Google account on each
machine and enable Sync (optionally with a sync passphrase). Bookmarks, passwords,
history and extensions then sync automatically — nothing Chrome-related is stored here.

## Adding a Debian/Ubuntu machine later

`vars/Debian.yml` and the apt task path already exist. Fill in/verify the package names
for your release (see the `TODO` markers), then run `bootstrap.sh` there — everything
branches on `ansible_facts['os_family']` automatically.

## Out of scope

- **KDE/Plasma settings** — fragile to sync; use Plasma's built-in settings sync.
- **Secrets / SSH keys** — never committed; provision your SSH key manually before the
  first SSH clone.
- **Language toolchains** (node/rust/go) — none installed today; add to `vars/*` when needed.
