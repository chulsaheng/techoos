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
    # TechoOS db must OUTRANK the base image's dbs, so insert it directly
    # after user-db (first system-db wins in dconf).
    mkdir -p /etc/dconf/profile
    if [ -f /etc/dconf/profile/user ]; then
        grep -v '^system-db:local$' /etc/dconf/profile/user > /tmp/dconf-user || true
        awk '{print} /^user-db:user$/ && !d {print "system-db:local"; d=1}' /tmp/dconf-user > /etc/dconf/profile/user
        grep -q '^system-db:local$' /etc/dconf/profile/user || sed -i '1i system-db:local' /etc/dconf/profile/user
    else
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
    fi
    dconf update

    # Strongest enforcement: gsettings schema override (zz1- sorts last = wins
    # over any Bazzite override file)
    cat > /usr/share/glib-2.0/schemas/zz1-techoos.gschema.override <<'OVR'
[org.gnome.desktop.interface]
enable-animations=false
icon-theme='Papirus'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/techoos/techoos-default.jpg'
picture-uri-dark='file:///usr/share/backgrounds/techoos/techoos-default.jpg'
picture-options='zoom'

[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/techoos/techoos-default.jpg'

[org.gnome.shell]
enabled-extensions=['dash-to-dock@micxgx.gmail.com']
OVR
    glib-compile-schemas /usr/share/glib-2.0/schemas/

    # Welcome app (first login: theme bullets + background bundle tick)
    chmod +x /usr/bin/techoos-welcome
fi

# --- First-boot flatpak installer (16 apps, list in /usr/share/techoos/flatpaks) ---
chmod +x /usr/bin/techoos-flatpak-setup
systemctl enable techoos-flatpak-setup.service

# --- De-Bazzite: artwork, hostname, fastfetch ---
# Remove Bazzite wallpapers so TechoOS artwork is the only branding
rm -rf /usr/share/backgrounds/bazzite* /usr/share/wallpapers/Bazzite* || true
# Default computer name: user@techoos instead of user@bazzite
echo "techoos" > /etc/hostname
# Bazzite's shell alias points fastfetch at its own config — replace it
if [ -f /usr/share/ublue-os/fastfetch.jsonc ]; then
    cp /etc/fastfetch/config.jsonc /usr/share/ublue-os/fastfetch.jsonc
fi

# --- Boot splash ---
# NOTE: deferred to 2.1. The previous approach rebuilt the initramfs at image
# build time (dracut --force), which on an OSTree/atomic base produces an
# initramfs missing the root-mount logic and drops the booted system into
# dracut emergency mode. A safe Plymouth theme (no initramfs rebuild) will
# land in a later release. Boot reliability comes first.


# --- Remove Bazzite artwork so only TechoOS branding remains ---
rm -f /usr/share/gnome-background-properties/bazzite*.xml || true
rm -rf /usr/share/backgrounds/bazzite* || true
rm -rf /usr/share/wallpapers/Bazzite* || true
# Override Bazzite's own fastfetch config so even its alias shows TechoOS
if [ -f /usr/share/ublue-os/fastfetch.jsonc ]; then
    cp /etc/fastfetch/config.jsonc /usr/share/ublue-os/fastfetch.jsonc
fi

# --- Branding: TechoOS 2.0 identity ---
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="TechoOS 2.0.2"/' /usr/lib/os-release
sed -i 's/^NAME=.*/NAME="TechoOS"/' /usr/lib/os-release
grep -q '^VERSION=' /usr/lib/os-release && \
    sed -i 's/^VERSION=.*/VERSION="2.0.2 (Angkor)"/' /usr/lib/os-release || \
    echo 'VERSION="2.0.2 (Angkor)"' >> /usr/lib/os-release
grep -q '^LOGO=' /usr/lib/os-release && \
    sed -i 's/^LOGO=.*/LOGO=techoos/' /usr/lib/os-release || \
    echo 'LOGO=techoos' >> /usr/lib/os-release

# Refresh icon cache so the techoos logo icon is picked up
gtk-update-icon-cache -f /usr/share/icons/hicolor || true

# Replace Fedora logo pixmaps where present
for f in /usr/share/pixmaps/fedora-logo.png /usr/share/pixmaps/fedora-logo-small.png \
         /usr/share/pixmaps/system-logo-white.png /usr/share/pixmaps/fedora_logo.png; do
    [ -f "$f" ] && cp /usr/share/pixmaps/techoos.png "$f" || true
done

# neofetch compatibility: alias to fastfetch (neofetch is unmaintained upstream)
cat > /etc/profile.d/techoos-fetch.sh <<'ALIAS'
alias neofetch='fastfetch'
ALIAS
chmod 644 /etc/profile.d/techoos-fetch.sh

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
