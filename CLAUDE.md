# CLAUDE.md

Guidance for AI sessions working in this repo. Keep this file current when architecture or
conventions change.

## What this is

Personal "workplace as code": packages + dotfiles for a Linux workstation, deployed with
**Ansible**. `bootstrap.sh` is the one-command entrypoint (sudo precheck → prereqs → clone →
collections → `ansible-playbook`). Primary target is **Arch / CachyOS**; **Debian/Ubuntu** is
a working stub (verify package names against the release before trusting it). Everything
branches on `ansible_facts['os_family']` (`Archlinux` / `Debian`).

Run: `ansible-playbook -i inventory.ini play-workplace.yaml --ask-become-pass [--ask-vault-pass]`.
Dry run: append `--check --diff`. Syntax: `--syntax-check`. `become` defaults to **False** in
`ansible.cfg` — tasks opt in with `become: true` per task.

## Package installation — catalog + on-host resolver (the core design)

Package **names and install method are NOT hard-coded per OS**. Instead:

1. `vars/software_catalog.yml` — one **OS-agnostic catalog**, the single source of truth for
   "what to install". Each item: `id`, `category` (`system` = always / `gui` = only when
   `install_gui`), `packages` (scalar/list, or a per-`os_family` map with optional `default`),
   optional `method`, `vendor`, `flatpak_id`, `supersedes`. Read the header of that file for
   the full schema — follow it exactly when adding software.
2. `roles/software-facts/` — renders the catalog to JSON and deploys
   `resolve_software_plan.py` to `/etc/ansible/facts.d/software_plan.fact`, then re-gathers so
   the result is a **custom fact** at `ansible_local.software_plan` (exposed as `software_plan`).
   The resolver runs **on the target host**: picks the per-distro package name and **decides the
   method**, autodetecting when `method` is omitted/`auto`:
   - in official repos → `native` (pacman/apt) · Arch + not in official repos → `aur`
     (this is how `google-chrome` / `netflix` resolve to AUR) · known `flatpak_id` + flatpak → `flatpak`
3. `roles/packages/` feeds each plan bucket to the right module; `roles/aur/` loops
   `software_plan.plan.aur` through `install_aur_pkg.yml`. Vendor-repo apps (Chrome/Spotify on
   Debian) go through `roles/packages/tasks/Debian-thirdparty.yml`, gated by the plan.

**To add software:** edit `vars/software_catalog.yml` only (no per-OS list editing). Inspect the
resolved plan on any host: `ansible -i inventory.ini localhost -m setup -a 'filter=ansible_local'`.

Test the resolver without a full run: render `software_catalog.yml`'s `software_catalog` list to
JSON next to a copy of `resolve_software_plan.py` named `*.fact`, then execute it — it prints the
plan as JSON.

## Credential/settings capture + deploy (Ansible Vault)

Two apps ship captured state, vault-encrypted, so a new machine comes up configured:
`thunderbird` (accounts + **passwords**: `key4.db`/`logins.json`/`prefs.js`/`cert9.db`) and
`steam` (**settings only** — `loginusers.vdf`/`config.vdf`; no password/token, just pre-fills the
login screen). Pattern to replicate for a new app "X":
- `roles/x/tasks/main.yml`: `set_fact` from `query('fileglob', '<dir>/*')`; a `block` gated on
  `... | length > 0`; a `pgrep -x <proc>` + `fail` guard (the app rewrites its files on exit);
  `ansible.builtin.copy` with **`force: false`** (seeds a fresh box only; auto-decrypts vaulted
  sources). Captured files + a `.gitkeep` live under `roles/x/files/<dir>/`.
- `capture-x.yml` at repo root (maintenance, **local → repo**, NOT in provisioning): require
  `./.vault-pass`, `pgrep` guard, `copy remote_src: true` into the repo, then
  `ansible-vault encrypt --vault-password-file ./.vault-pass <file>`, then a `head -c 15` check
  that each file starts with `$ANSIBLE_VAULT` (never commit plaintext).
- `group_vars/all.yml`: a `deploy_x: true` toggle; register `- role: x` in `play-workplace.yaml`
  gated on `install_gui | bool` and `deploy_x | bool`, ordered **after** `packages`.
- No `.gitignore`/`bootstrap.sh` change needed: bootstrap auto-provisions `.vault-pass` when
  `grep -rlq '$ANSIBLE_VAULT' roles/` matches. `.vault-pass` is gitignored — **never commit it**.

## Conventions

- **FQCN always** (`ansible.builtin.*`, `community.general.*`). Only `community.general` is a
  dependency (`requirements.yml`).
- **Vars:** snake_case, prefixed by domain not role (`docker_packages`, `perl_os_packages`,
  `steam_config_dir`). Booleans consumed with `| bool`; lists gated with `| length > 0`.
- **OS dispatch** via `ansible_facts['os_family']` (`include_tasks`/`include_vars`/`when`), never
  the legacy top-level `ansible_os_family`. `vars/{Archlinux,Debian}.yml` hold only role-specific
  leftovers (docker/perl/removals) now that package lists moved to the catalog.
- **Idempotent detection idiom:** `command -v <x>` / `pacman -Qq <pkg>` with
  `changed_when: false`, `failed_when: false`, `check_mode: false`, then `when: X.rc != 0`.

## Gotchas / invariants

- **Steam needs Arch `[multilib]`.** A `pre_task` in `play-workplace.yaml` enables it before the
  resolver runs; otherwise `pacman -Si steam` misses and steam is misclassified as AUR. Steam's
  catalog `method` is pinned `native` on Arch as a belt-and-suspenders.
- **AUR builder is limited:** `install_aur_pkg.yml` assumes build/runtime deps are in the official
  repos — it does **not** resolve AUR-only deps. `netflix` (unofficial AUR wrapper) may fail to
  build; that's accepted, not a bug to "fix" by force.
- **Firefox is removed only after Chrome is installed** (guarded in `roles/aur` on Arch and in
  `Debian-thirdparty.yml`), so a failed Chrome build never leaves the box browser-less. The
  catalog's `supersedes` documents these removals.
- **starship** is installed by `roles/starship` (pacman on Arch, official installer elsewhere),
  NOT via the catalog — don't re-add it as a catalog item.
- **Chrome/Netflix logins are not captured** (keyring-bound / web) — use Chrome Sync.
- Do not commit `.vault-pass` or any plaintext credential file.

## Commit convention

This repo's remote is `github.com/d1rty-pixel/home`. Only commit/push when the user asks. Branch
off the default branch first if needed.
