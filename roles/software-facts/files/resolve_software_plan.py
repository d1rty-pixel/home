#!/usr/bin/env python3
"""Ansible custom fact: resolve an OS-agnostic software catalog into an install plan.

This runs ON THE TARGET HOST as a facts.d script. Ansible copies it (and a JSON
render of the catalog) into /etc/ansible/facts.d/, gathers facts, and the result
lands at ansible_local.software_plan — which the roles then feed to the native
package modules.

What it does, per catalog item:
  1. Picks the package name(s) for THIS distro (per-OS override, else `default`).
  2. Decides the install METHOD. If the item pins one (e.g. Chrome on Debian ->
     vendor_repo) that wins; otherwise it AUTODETECTS:
        - available in the official repos  -> native   (pacman/apt)
        - Arch + not in official repos      -> aur      (e.g. google-chrome)
        - a flatpak id is known + flatpak   -> flatpak
        - otherwise                         -> unresolved (surfaced, not fatal)
  3. Emits the plan grouped by method so each Ansible task can consume one bucket.

Output is always valid JSON. On any error it prints {"error": "..."} with an empty
plan so a bad catalog can never abort fact gathering.
"""

import json
import os
import shutil
import subprocess
import sys

# The catalog is deployed next to this script by the software-facts role.
CATALOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "software_catalog.json")


def run(cmd):
    """Run a command, return (rc, stdout). Never raises."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           text=True, check=False)
        return p.returncode, p.stdout
    except (OSError, ValueError):
        return 127, ""


def detect_os_family():
    """Map /etc/os-release to Ansible's os_family values (Archlinux / Debian)."""
    data = {}
    try:
        with open("/etc/os-release", encoding="utf-8") as fh:
            for line in fh:
                if "=" in line:
                    k, _, v = line.partition("=")
                    data[k.strip()] = v.strip().strip('"')
    except OSError:
        pass
    ids = " {} {} ".format(data.get("ID", ""), data.get("ID_LIKE", ""))
    if " arch " in ids:
        return "Archlinux"
    if " debian " in ids or " ubuntu " in ids:
        return "Debian"
    return data.get("ID", "unknown")


def have(binary):
    return shutil.which(binary) is not None


def native_available_arch(pkg):
    """True if pkg is in a pacman sync repo (official)."""
    rc, _ = run(["pacman", "-Si", pkg])
    return rc == 0


def native_available_debian(pkg):
    """True if apt has an installable candidate for pkg."""
    rc, out = run(["apt-cache", "policy", pkg])
    if rc != 0:
        return False
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Candidate:"):
            return "(none)" not in line
    return False


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def pick_for_family(mapping, family):
    """Resolve a per-family override map to a value, falling back to `default`.

    Accepts either a plain scalar/list (applies to every family) or a dict keyed
    by os_family with an optional `default`.
    """
    if isinstance(mapping, dict):
        if family in mapping:
            return mapping[family]
        return mapping.get("default")
    return mapping


def resolve():
    family = detect_os_family()
    has_flatpak = have("flatpak")
    aur_helper = next((h for h in ("yay", "paru") if have(h)), None)

    pkg_mgr = None
    if have("pacman"):
        pkg_mgr = "pacman"
    elif have("apt-get"):
        pkg_mgr = "apt"
    elif have("dnf"):
        pkg_mgr = "dnf"

    with open(CATALOG_PATH, encoding="utf-8") as fh:
        catalog = json.load(fh)

    plan = {
        "native_system": [],   # official-repo pkgs, always installed
        "native_gui": [],      # official-repo pkgs, gated by install_gui
        "aur": [],             # AUR package names (Arch)
        "flatpak": [],         # flatpak application ids
        "vendor": [],          # third-party-repo items: {id, vendor, packages, category}
        "absent": [],          # packages to remove once their superseder is present
        "unresolved": [],      # items with no install path on this OS (surfaced, non-fatal)
    }
    items = []

    for entry in catalog:
        item_id = entry.get("id", "?")
        category = entry.get("category", "system")
        packages = as_list(pick_for_family(entry.get("packages"), family))
        if not packages:
            # Nothing defined for this distro (e.g. alacritty on Debian) -> skip silently.
            continue

        method = pick_for_family(entry.get("method"), family) or "auto"
        flatpak_id = pick_for_family(entry.get("flatpak_id"), family)

        if method == "auto":
            method = autodetect(family, packages, has_flatpak, flatpak_id)

        resolved = {"id": item_id, "category": category,
                    "method": method, "packages": packages}
        items.append(resolved)

        if method == "native":
            bucket = "native_gui" if category == "gui" else "native_system"
            plan[bucket].extend(packages)
        elif method == "aur":
            plan["aur"].extend(packages)
        elif method == "flatpak":
            plan["flatpak"].append(flatpak_id or item_id)
        elif method == "vendor_repo":
            plan["vendor"].append({
                "id": item_id,
                "vendor": entry.get("vendor", item_id),
                "packages": packages,
                "category": category,
            })
        else:
            plan["unresolved"].append({"id": item_id, "packages": packages})

        # Packages this item replaces, removed by the roles once it is installed.
        plan["absent"].extend(as_list(pick_for_family(entry.get("supersedes"), family)))

    # De-duplicate name lists while preserving order.
    for key in ("native_system", "native_gui", "aur", "flatpak", "absent"):
        seen = set()
        plan[key] = [x for x in plan[key] if not (x in seen or seen.add(x))]

    return {
        "os_family": family,
        "pkg_mgr": pkg_mgr,
        "aur_helper": aur_helper,
        "has_flatpak": has_flatpak,
        "items": items,
        "plan": plan,
    }


def autodetect(family, packages, has_flatpak, flatpak_id):
    """Decide the install method for a catalog item that didn't pin one."""
    if family == "Archlinux":
        if all(native_available_arch(p) for p in packages):
            return "native"
        # Present on Arch but absent from the official repos -> it's an AUR package
        # (this is how google-chrome resolves to `aur` without being told to).
        return "aur"
    if family == "Debian":
        if all(native_available_debian(p) for p in packages):
            return "native"
        if has_flatpak and flatpak_id:
            return "flatpak"
        return "unresolved"
    # Unknown OS: trust flatpak if we have an id, else give up gracefully.
    if has_flatpak and flatpak_id:
        return "flatpak"
    return "unresolved"


def main():
    try:
        print(json.dumps(resolve()))
    except Exception as exc:  # noqa: BLE001 - facts must never crash the run
        print(json.dumps({
            "error": "{}: {}".format(type(exc).__name__, exc),
            "plan": {"native_system": [], "native_gui": [], "aur": [],
                     "flatpak": [], "vendor": [], "absent": [], "unresolved": []},
        }))
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
