#!/bin/bash

set -ouex pipefail

### TechoOS 2.0 build script
### VARIANT is passed from the Containerfile: "gnome" (flagship) or "kde"
VARIANT="${VARIANT:-gnome}"
echo "Building TechoOS 2.0 — ${VARIANT} edition"

# --- Layered packages (shared) ---
# Wine + helpers for running Windows software
dnf5 install -y wine winetricks

# Khmer language support: Noto Khmer fonts (sans, serif, UI)
dnf5 install -y google-noto-sans-khmer-fonts google-noto-serif-khmer-fonts google-noto-sans-khmer-ui-fonts

# --- GNOME edition extras ---
if [ "$VARIANT" = "gnome" ]; then
    # Dash to Dock + Papirus icon theme
    dnf5 install -y gnome-shell-extension-dash-to-dock papirus-icon-theme

    # System-wide GNOME defaults (animations off, dock, wallpaper, weather)
    # delivered via dconf db at /etc/dconf/db/local.d/01-techoos
    if [ -f /etc/dconf/profile/user ]; then
        grep -q '^system-db:local$' /etc/dconf/profile/user || \
            echo 'system-db:local' >> /etc/dconf/profile/user
    else
        mkdir -p /etc/dconf/profile
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
    fi
    dconf update

    # Welcome app (first login: theme bullets + background bundle tick)
    chmod +x /usr/bin/techoos-welcome
fi

# --- First-boot flatpak installer (16 apps, list in /usr/share/techoos/flatpaks) ---
chmod +x /usr/bin/techoos-flatpak-setup
systemctl enable techoos-flatpak-setup.service

# --- Boot splash: TechoOS watermark on the Plymouth spinner theme ---
for theme in spinner bgrt; do
    dir="/usr/share/plymouth/themes/${theme}"
    [ -d "$dir" ] && cp /usr/share/techoos/branding/watermark.png "$dir/watermark.png"
done

# --- Branding: TechoOS 2.0 identity ---
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="TechoOS 2.0"/' /usr/lib/os-release
sed -i 's/^NAME=.*/NAME="TechoOS"/' /usr/lib/os-release
grep -q '^VERSION=' /usr/lib/os-release && \
    sed -i 's/^VERSION=.*/VERSION="2.0 (Angkor)"/' /usr/lib/os-release || \
    echo 'VERSION="2.0 (Angkor)"' >> /usr/lib/os-release
grep -q '^LOGO=' /usr/lib/os-release && \
    sed -i 's/^LOGO=.*/LOGO=techoos/' /usr/lib/os-release || \
    echo 'LOGO=techoos' >> /usr/lib/os-release

# Refresh icon cache so the techoos logo icon is picked up
gtk-update-icon-cache -f /usr/share/icons/hicolor || true

# --- Fix anaconda-ISO depsolving ---
# bootc-image-builder reads the repo files baked into this image. Repos whose
# gpgkey points at a missing file:// path abort the ISO build. Expand dnf
# variables before checking so healthy repos (fedora, updates) stay enabled.
releasever="$(rpm -E %fedora)"
basearch="$(uname -m)"
for repo in /etc/yum.repos.d/*.repo; do
    missing=0
    for url in $(grep -oE 'file://[^[:space:]]+' "$repo" || true); do
        path="${url#file://}"
        path="${path//\$releasever/$releasever}"
        path="${path//\$basearch/$basearch}"
        path="${path//\$\{releasever\}/$releasever}"
        path="${path//\$\{basearch\}/$basearch}"
        [ -e "$path" ] || missing=1
    done
    if [ "$missing" = "1" ]; then
        echo "Disabling $repo (references missing GPG key file)"
        sed -i 's/^enabled[[:space:]]*=[[:space:]]*1/enabled=0/' "$repo"
    fi
done
# terra repos break bib's depsolver regardless (releasever mismatch inside
# the builder container) — disable them outright.
for repo in /etc/yum.repos.d/terra*.repo; do
    [ -e "$repo" ] || continue
    echo "Disabling $repo (terra repos break ISO depsolve)"
    sed -i 's/^enabled[[:space:]]*=[[:space:]]*1/enabled=0/' "$repo"
done
