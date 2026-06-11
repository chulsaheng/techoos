# TechoOS

A custom Bazzite-based (Fedora Atomic) operating system with a full creative
and multimedia suite preinstalled, plus NVIDIA drivers and Wine baked in.

## Included out of the box

**Baked into the image:** NVIDIA driver (open kernel modules, via the
Bazzite-NVIDIA base), Wine + Winetricks, everything Bazzite ships
(gaming tweaks, codecs, KDE Plasma).

**Installed as Flatpaks on first boot:** VLC, Kdenlive, GIMP, Blender,
Inkscape, Audacity, qBittorrent, Brave Browser, darktable.

**Cambodian identity:** an original "Angkor Dawn" wallpaper (sunrise over
the five towers of Angkor Wat, with sugar palms and water reflection) set
as the system default, plus a Khmer-red accent color (`#E00025`, from the
Cambodian flag) for buttons, highlights, and selections. New user accounts
get this look automatically; existing users can pick "Angkor Dawn" in
System Settings → Wallpaper. To switch the accent to the flag's royal
blue instead, edit `system_files/etc/xdg/kdeglobals`. Noto Khmer fonts
(sans, serif, UI) are baked in, and the Khmer keyboard layout can be
enabled in System Settings → Keyboard → Layouts.

## How to build your ISO

1. **Create the repo.** Make a new GitHub repository named `techoos`
   and push these files to it. The repo name becomes the image name.

2. **Set up image signing (required).** Install [cosign](https://docs.sigstore.dev/cosign/system_config/installation/), then in the repo folder run:
   ```
   cosign generate-key-pair
   ```
   Commit `cosign.pub` to the repo. Do NOT commit `cosign.key` — instead add
   its contents as a GitHub Actions secret named `SIGNING_SECRET`
   (repo Settings → Secrets and variables → Actions).

3. **Point the ISO at your image.** In `disk_config/iso.toml`, replace
   `chulsaheng` with your GitHub username (lowercase).

4. **Enable workflows.** Go to the Actions tab and enable them. The
   `build.yml` workflow builds and publishes
   `ghcr.io/<you>/techoos:latest` on every push.

5. **Build the ISO.** Run the `Build disk images` workflow (Actions →
   build-disk → Run workflow). When it finishes, download the
   `anaconda-iso` artifact — that's your bootable TechoOS installer.

6. **Flash and install** with Fedora Media Writer, Ventoy, or `dd`.

## Choosing a different GPU base

Edit the `FROM` line in `Containerfile`:
- `ghcr.io/ublue-os/bazzite-nvidia-open:stable` — NVIDIA RTX / GTX 16xx and newer (default)
- `ghcr.io/ublue-os/bazzite-nvidia:stable` — older NVIDIA GPUs (closed driver)
- `ghcr.io/ublue-os/bazzite:stable` — AMD / Intel

## Adding or removing apps

Edit `system_files/usr/share/techoos/flatpaks` (one Flathub app ID per
line) and push. Existing installs update automatically via bootc; the
flatpak list applies on first boot of fresh installs.

## Updates

TechoOS inherits Bazzite's update system: installed machines
automatically pull your latest image from GHCR. Push a change to this
repo and every TechoOS machine gets it on the next update.

---
Built with the [Universal Blue image template](https://github.com/ublue-os/image-template).
