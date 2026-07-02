# ~/.config/fish/config.fish  (managed by the workplace repo)

# CachyOS ships a shared fish config; source it only if present (portable).
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

fish_add_path ~/.local/bin

# Preferred editor
set -gx EDITOR vim
set -gx VISUAL vim

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
