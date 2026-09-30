#!/bin/bash
# Install everything needed to build podman 4.9.3 + conmon from source on Ubuntu 22.04.
#
# Runs as root inside the jammy build container. Idempotent.
set -euo pipefail

. /etc/os-release
if [ "${VERSION_CODENAME:-}" != "jammy" ]; then
    echo "error: this build targets jammy (22.04); found '${VERSION_CODENAME:-unknown}'" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    build-essential pkg-config ca-certificates curl git xz-utils \
    `# podman needs go >= 1.18; jammy ships exactly 1.18. This is why we build` \
    `# the 4.x series: podman 5.x and 6.x both require go 1.26.` \
    golang-go \
    `# cgo deps for the build tags we pin below` \
    libseccomp-dev \
    libgpgme-dev libassuan-dev \
    libsystemd-dev \
    libapparmor-dev \
    `# docs + shell completions` \
    go-md2man \
    `# install.docker generates /usr/bin/docker by substituting into docker.in` \
    gettext-base \
    `# conmon` \
    libglib2.0-dev

# Deliberately NOT installed, and why each is fine to omit:
#
#   libsubid-dev        absent from jammy. podman's hack/libsubid_tag.sh probes
#                       for it and silently drops the `libsubid` tag, falling
#                       back to parsing /etc/subuid directly (same as the
#                       distro 3.4.4 package).
#   libbtrfs-dev        we pin exclude_graphdriver_btrfs, so the btrfs
#                       graphdriver is not compiled in. jammy's btrfs-progs
#                       headers are from 2022 and untested against podman 4.9.
#   libdevmapper-dev    we pin exclude_graphdriver_devicemapper; the overlay
#                       driver is the default and what we want.
#   libostree-dev       only needed for the (unused) ostree graph driver.

echo "== toolchain =="
go version
gcc --version | head -1
