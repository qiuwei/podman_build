#!/bin/bash
# Build podman from source and install it into $STAGE.
#
# Targets podman 4.9.3 specifically. That is not arbitrary: it is the newest
# podman release that builds with jammy's Go 1.18. podman 5.8.x and 6.1.x both
# declare `go 1.26.0` in go.mod, and 4.9.3 also the last series with CNI
# network-backend support (removed in 5.0). jammy has no netavark/aardvark-dns,
# so CNI is the only backend available to us. v4.9.3 is the sweet spot.
set -euo pipefail

PODMAN_VERSION="${PODMAN_VERSION:-4.9.3}"
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
