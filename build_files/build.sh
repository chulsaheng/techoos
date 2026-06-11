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
