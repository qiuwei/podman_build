#!/bin/bash
# Build podman from source and install it into $STAGE.
#
# Targets the 4.9.x series (newest patch by default). The binding constraint is
# the NETWORK BACKEND, not Go: podman 5.0 removed the CNI backend, and jammy has
# no netavark/aardvark-dns packages, so CNI -- via jammy's
# containernetworking-plugins -- is the only backend available here. That makes
# 4.9.x the newest podman that can actually run on jammy at all.
#
# (Go is a separate problem: buildah forces a `go >= 1.20` floor that jammy's
# 1.18 toolchain cannot meet, so 00-build-deps.sh installs Go from upstream.)
set -euo pipefail

PODMAN_VERSION="${PODMAN_VERSION:-4.9.5}"
WORKDIR="${WORKDIR:-/build}"
STAGE="${STAGE:-${WORKDIR}/stage-podman}"
STAGE_DOCKER="${STAGE_DOCKER:-${WORKDIR}/stage-podman-docker}"

# Build tags are pinned rather than auto-detected (podman's Makefile otherwise
# probes the environment with hack/*.sh). Pinning makes the resulting runtime
# dependencies auditable -- see packaging/podman/control.in, which lists exactly
# the shared libraries these tags pull in.
BUILDTAGS="seccomp systemd apparmor exclude_graphdriver_devicemapper exclude_graphdriver_btrfs"

# No git required. The Makefile injects the commit via ldflags only when
# `git rev-parse` succeeds and otherwise omits the flag; the version string
# itself is hardcoded in the version/ source package. So this builds fine from
# a plain tarball, which is what the Dockerfile does.

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ ! -d "podman-${PODMAN_VERSION}" ]; then
    echo "== fetching podman ${PODMAN_VERSION} =="
    curl -fsSL --retry 5 --retry-all-errors \
        -o "podman-v${PODMAN_VERSION}.tar.gz" \
        "https://github.com/podman-container-tools/podman/archive/refs/tags/v${PODMAN_VERSION}.tar.gz"
    tar -xzf "podman-v${PODMAN_VERSION}.tar.gz"
fi
cd "podman-${PODMAN_VERSION}"

echo "== building podman (BUILDTAGS=${BUILDTAGS}) =="
make -j"$(nproc)" BUILDTAGS="$BUILDTAGS" binaries

echo "== staging binaries, units, man pages =="
rm -rf "$STAGE" "$STAGE_DOCKER"
make BUILDTAGS="$BUILDTAGS" PREFIX=/usr DESTDIR="$STAGE" install
make BUILDTAGS="$BUILDTAGS" PREFIX=/usr DESTDIR="$STAGE" install.completions

# podman-docker is its own package upstream; stage it separately so the two
# debs do not fight over /usr/bin/docker.
make BUILDTAGS="$BUILDTAGS" PREFIX=/usr DESTDIR="$STAGE_DOCKER" install.docker

echo "== sanity: what did we actually build? =="
"$STAGE/usr/bin/podman" --version

echo "== staged podman tree =="
find "$STAGE" -type f | sort | sed 's|^|  |'
