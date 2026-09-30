#!/bin/bash
# Build conmon from source and install it into $STAGE.
#
# Why we ship our own conmon: jammy's conmon is 2.0.25 (2021), four years older
# than podman 4.9.3 (2024). podman 4.x drives conmon much harder than podman 3.x
# did (exit-command handling, cgroup delegation), and that pairing is not
# something upstream or any distro tests. The podman package depends on
# `conmon (>= 2.1.0)`, so apt is structurally forced to take ours.
set -euo pipefail

CONMON_VERSION="${CONMON_VERSION:-2.2.1}"
SRC_URL="https://github.com/containers/conmon/archive/refs/tags/v${CONMON_VERSION}.tar.gz"
WORKDIR="${WORKDIR:-/build}"
STAGE="${STAGE:-${WORKDIR}/stage-conmon}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "== fetching conmon ${CONMON_VERSION} =="
curl -fsSL --retry 5 --retry-all-errors -o "conmon-v${CONMON_VERSION}.tar.gz" "$SRC_URL"
tar -xzf "conmon-v${CONMON_VERSION}.tar.gz"
cd "conmon-${CONMON_VERSION}"

echo "== building conmon =="
make -j"$(nproc)" bin/conmon

echo "== staging into ${STAGE} =="
rm -rf "$STAGE"
make install.bin DESTDIR="$STAGE" PREFIX=/usr

find "$STAGE" -type f | sort
