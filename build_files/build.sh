#!/bin/bash

set -ouex pipefail

### TechoOS build script

# --- Layered packages (things that can't be flatpaks) ---
# Wine + helpers for running Windows software
dnf5 install -y wine winetricks

# Khmer language support: Noto Khmer fonts (sans, serif, UI).
# The Khmer keyboard layout ships with Plasma already — users add it in
# System Settings > Keyboard > Layouts > Khmer (Cambodia).
dnf5 install -y google-noto-sans-khmer-fonts google-noto-serif-khmer-fonts google-noto-sans-khmer-ui-fonts

# --- First-boot flatpak installer ---
# Installs the TechoOS app suite (VLC, Kdenlive, GIMP, Blender,
# Inkscape, Audacity, qBittorrent, Brave, darktable) from Flathub
# on first boot with network. List: /usr/share/techoos/flatpaks
chmod +x /usr/bin/techoos-flatpak-setup
systemctl enable techoos-flatpak-setup.service

# --- Branding ---
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="TechoOS"/' /usr/lib/os-release

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
