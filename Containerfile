ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable
# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# ============================================================
# TechoOS — Bazzite-based creative & multimedia OS
# Base: Bazzite with NVIDIA open kernel modules (RTX/GTX 16xx+)
# For pre-Turing GPUs use: ghcr.io/ublue-os/bazzite-nvidia:stable
# For AMD/Intel use:       ghcr.io/ublue-os/bazzite:stable
# ============================================================
FROM ${BASE_IMAGE}
ARG VARIANT=gnome

# Copy TechoOS system files (flatpak list, first-boot service, branding)
COPY system_files /

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT=${VARIANT} /ctx/build.sh

### SAFETY GUARD
## Ensure we did NOT ship a broken image-built initramfs. The OSTree-managed
## initramfs must contain the ostree hook, or the installed system drops to
## dracut emergency mode at boot (the 2.0/2.0.1 bug).
RUN set -e; \
    img="$(find /usr/lib/modules -name initramfs.img | head -1)"; \
    if [ -n "$img" ]; then \
        lsinitrd "$img" 2>/dev/null | grep -q ostree \
            || { echo "FATAL: initramfs missing ostree hook — would not boot"; exit 1; }; \
        echo "initramfs sanity check passed"; \
    fi

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
