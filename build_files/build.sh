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
# KhmerOS font family for LibreOffice / legacy Khmer documents.
# Package name varies by release; try known names, never fail the build.
for pkg in khmer-os-fonts khmeros-fonts khmeros-base-fonts khmer-os-system-fonts; do
    dnf5 install -y "$pkg" 2>/dev/null && { echo "Installed $pkg"; break; } || true
done

# --- Pre-installed app suite (baked into the image like Nobara/Ubuntu Studio) ---
# These are native RPMs from Fedora + RPMFusion (already enabled on Bazzite), so
# they are present ON the ISO and installed DURING installation — available
# immediately at first login, no network, no first-boot download.
mkdir -p /usr/share/techoos
: > /usr/share/techoos/app-install.log
APPS=(
  firefox                        # web browser
  libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw
  libreoffice-langpack-km        # Khmer LibreOffice interface/spelling
  gimp inkscape blender darktable digikam
  vlc audacity kdenlive obs-studio HandBrake-gui
  pdfarranger qbittorrent
)
for pkg in "${APPS[@]}"; do
    if dnf5 install -y "$pkg" >>/usr/share/techoos/app-install.log 2>&1; then
        echo "OK    $pkg"   | tee -a /usr/share/techoos/app-install.log
    else
        echo "FAILED $pkg"  | tee -a /usr/share/techoos/app-install.log
    fi
done
echo "App suite layering finished. Summary in /usr/share/techoos/app-install.log"

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
systemctl enable techoos-flatpak-setup.timer

# --- De-Bazzite: artwork, hostname, fastfetch ---
# Remove Bazzite wallpapers so TechoOS artwork is the only branding
rm -rf /usr/share/backgrounds/bazzite* /usr/share/wallpapers/Bazzite* || true
# Default computer name: user@techoos instead of user@bazzite
echo "techoos" > /etc/hostname
# Bazzite's shell alias points fastfetch at its own config — replace it
if [ -f /usr/share/ublue-os/fastfetch.jsonc ]; then
    cp /etc/fastfetch/config.jsonc /usr/share/ublue-os/fastfetch.jsonc
fi

# --- TechoOS boot splash (Plymouth) ---
# Goal (your request #1): show the laptop firmware logo with the TechoOS shield
# beneath it. That is exactly what the stock "bgrt" theme does — and bgrt reads
# its watermark from the spinner theme's folder. So we simply (1) drop our logo
# in as the watermark, (2) force bgrt as the default theme, (3) remove the old
# half-built techoos theme, (4) regenerate the initramfs WITH the ostree module
# so Plymouth picks up the new watermark. The Containerfile guard fails the
# build if the initramfs ever loses its ostree hook, so boot can't break.
rm -rf /usr/share/plymouth/themes/techoos
for d in /usr/share/plymouth/themes/spinner /usr/share/plymouth/themes/bgrt; do
    [ -d "$d" ] && cp /usr/share/techoos/branding/watermark.png "$d/watermark.png" || true
done
# Single, unambiguous default theme (the diag found duplicate Theme= lines)
mkdir -p /etc/plymouth
printf '[Daemon]\nTheme=bgrt\n' > /etc/plymouth/plymouthd.conf
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme bgrt || true
fi
KVER="$(ls /usr/lib/modules | head -1)"
if [ -n "$KVER" ] && [ -d "/usr/lib/modules/$KVER" ]; then
    dracut --force --no-hostonly --add ostree --kver "$KVER" \
        "/usr/lib/modules/$KVER/initramfs.img" \
        || echo "WARNING: initramfs regen failed; Containerfile guard will catch it"
fi

# --- Login screen (GDM): TechoOS logo, not Fedora/Bazzite (your request #3) ---
# The diag found the greeter logo at /usr/share/pixmaps/fedora-gdm-logo.png.
if [ -f /usr/share/pixmaps/fedora-gdm-logo.png ]; then
    cp /usr/share/techoos/branding/watermark.png /usr/share/pixmaps/fedora-gdm-logo.png
fi
# Tell the GNOME greeter to actually show that logo
mkdir -p /etc/dconf/db/gdm.d
cat > /etc/dconf/db/gdm.d/01-techoos-logo <<'EOF'
[org/gnome/login-screen]
logo='/usr/share/pixmaps/fedora-gdm-logo.png'
EOF

# --- Installer branding (Anaconda) — your request #2 ---
# The diag confirmed the installer pixmaps ship in the image at
# /usr/share/anaconda/pixmaps (from the fedora-logos package), so we replace
# them directly in the image — the reliable way, no product.img hack needed.
APX=/usr/share/anaconda/pixmaps
if [ -d "$APX" ]; then
    [ -f /usr/share/techoos/installer/installer-sidebar-logo.png ] && cp /usr/share/techoos/installer/installer-sidebar-logo.png "$APX/sidebar-logo.png" || true
    [ -f /usr/share/techoos/installer/installer-sidebar-bg.png ]   && cp /usr/share/techoos/installer/installer-sidebar-bg.png   "$APX/sidebar-bg.png" || true
    [ -f /usr/share/techoos/installer/installer-topbar-bg.png ]    && cp /usr/share/techoos/installer/installer-topbar-bg.png    "$APX/topbar-bg.png" || true
    [ -f /usr/share/techoos/installer/installer-sidebar-logo.png ] && cp /usr/share/techoos/installer/installer-sidebar-logo.png "$APX/anaconda_header.png" || true
fi

# Compile the GDM dconf database so the login logo takes effect
dconf update || true


# --- Remove Bazzite artwork so only TechoOS branding remains ---
rm -f /usr/share/gnome-background-properties/bazzite*.xml || true
rm -rf /usr/share/backgrounds/bazzite* /usr/share/backgrounds/Bazzite* || true
rm -rf /usr/share/wallpapers/Bazzite* || true

# Replace every known distributor logo (Bazzite + Fedora) with the TechoOS shield
for f in \
    /usr/share/pixmaps/fedora-logo.png /usr/share/pixmaps/fedora-logo-small.png \
    /usr/share/pixmaps/fedora_logo.png /usr/share/pixmaps/fedora_logo_med.png \
    /usr/share/pixmaps/system-logo-white.png /usr/share/pixmaps/bazzite*.png \
    /usr/share/pixmaps/poweredby.png ; do
    [ -e "$f" ] && cp /usr/share/pixmaps/techoos.png "$f" || true
done
# GNOME "About" distributor logo lookups
for f in \
    /usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg \
    /usr/share/icons/hicolor/256x256/apps/fedora-logo-icon.png \
    /usr/share/icons/hicolor/scalable/apps/bazzite*.svg ; do
    [ -e "$f" ] && cp /usr/share/pixmaps/techoos.png "$f" || true
done

# Make the terminal fastfetch show the TechoOS shield, not Bazzite.
# Ground truth from image inspection: Bazzite's config is at
# /usr/share/ublue-os/bazzite/fastfetch.jsonc, launched by
# /etc/profile.d/bazzite-neofetch.sh -> /usr/libexec/bazzite-bling-fastfetch.
install -Dm644 /etc/fastfetch/config.jsonc /usr/share/techoos/fastfetch.jsonc
# (belt) point Bazzite's own config file at our logo
[ -d /usr/share/ublue-os/bazzite ] && \
    cp /usr/share/techoos/fastfetch.jsonc /usr/share/ublue-os/bazzite/fastfetch.jsonc || true
# (suspenders) hijack Bazzite's launcher so it always uses our config —
# single chokepoint, immune to whatever flags the original passed
if [ -f /usr/libexec/bazzite-bling-fastfetch ]; then
    cat > /usr/libexec/bazzite-bling-fastfetch <<'SH'
#!/usr/bin/bash
exec /usr/bin/fastfetch --config /usr/share/techoos/fastfetch.jsonc "$@"
SH
    chmod +x /usr/libexec/bazzite-bling-fastfetch
fi

# --- Branding: TechoOS 2.0 identity ---
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="TechoOS 2.0.6"/' /usr/lib/os-release
sed -i 's/^NAME=.*/NAME="TechoOS"/' /usr/lib/os-release
grep -q '^VERSION=' /usr/lib/os-release && \
    sed -i 's/^VERSION=.*/VERSION="2.0.6 (Angkor)"/' /usr/lib/os-release || \
    echo 'VERSION="2.0.6 (Angkor)"' >> /usr/lib/os-release
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
