# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# ============================================================
# TechoOS — Bazzite-based creative & multimedia OS
# Base: Bazzite with NVIDIA open kernel modules (RTX/GTX 16xx+)
# For pre-Turing GPUs use: ghcr.io/ublue-os/bazzite-nvidia:stable
# For AMD/Intel use:       ghcr.io/ublue-os/bazzite:stable
# ============================================================
FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable

# Copy TechoOS system files (flatpak list, first-boot service, branding)
COPY system_files /

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
