#!/bin/bash
# Install everything needed to build podman 4.9.x + conmon from source on Ubuntu 22.04.
#
# Runs as root inside the jammy build container. Idempotent.
set -euo pipefail

. /etc/os-release
if [ "${VERSION_CODENAME:-}" != "jammy" ]; then
    echo "error: this build targets jammy (22.04); found '${VERSION_CODENAME:-unknown}'" >&2
    exit 1
fi

# The Go toolchain is installed from upstream rather than apt.
#
# jammy's newest Go is 1.18, which is NOT enough: podman 4.9.x pulls in
# github.com/containers/buildah, whose go.mod declares `go 1.20`. Go refuses to
# build a dependency that declares a newer language version, so `make binaries`
# dies with "module ... requires go >= 1.20". containers/storage adds a `go 1.19`
# floor on top of that. Both podman 4.9.3 and 4.9.5 are affected -- their own
# `go 1.18` directive is simply stale relative to their dependency tree.
#
# 1.22 is comfortably above the 1.20 floor and still old enough not to trip over
# the 2022-era code. See the README for why the version *ceiling* for this whole
# project is the 4.9.x series -- that reason is the CNI backend, not Go.
GO_VERSION="${GO_VERSION:-1.22.12}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    build-essential pkg-config ca-certificates curl git xz-utils \
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
#   golang-go           superseded by the upstream toolchain below.
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

echo "== installing Go ${GO_VERSION} =="
curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
    -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm -f /tmp/go.tar.gz
# Symlink into /usr/local/bin so every later CI step and shell picks it up
# without needing its own PATH export.
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

echo "== toolchain =="
go version
gcc --version | head -1
